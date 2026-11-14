import AppKit
import CVLCore
import Combine

/// 串起整条数据流：焦点 / 文本变化 → 过滤 → 防抖 → 检测 → 标记 / 浮窗 / 徽标 → 替换 → 复查。
@MainActor
final class Coordinator {
    static let shared = Coordinator()

    let store = SettingsStore.shared
    let session = CheckSession()
    private let monitor = FocusMonitor()
    private let keyTap = KeyTap()
    private let overlay = OverlayController()
    private let suggestion = SuggestionController()
    private let badge = BadgeController()
    private let result = ResultController()

    private var debounce: Task<Void, Never>?
    private var generation = 0
    private var refreshTimer: Timer?
    private var current: (focus: FocusedText, issues: [Issue])?
    private var dismissedIssueIDs = Set<String>()
    private var lastPaste = Date.distantPast
    private var bag = Set<AnyCancellable>()

    static let debounceDelay: UInt64 = 300_000_000

    func start() {
        store.syncLaunchAtLoginState()
        L10n.language = store.settings.language
        store.$settings.sink { [weak self] s in
            DispatchQueue.main.async { self?.settingsChanged(s) }
        }.store(in: &bag)

        monitor.onEvent = { [weak self] e in self?.handle(e) }
        keyTap.onShortcut = { [weak self] a in self?.runShortcut(a) }
        keyTap.popupVisible = { [weak self] in self?.suggestion.isVisible ?? false }
        keyTap.onPopupKey = { [weak self] k in self?.handlePopupKey(k) }
        keyTap.onPaste = { [weak self] in self?.lastPaste = Date(); self?.scheduleCheck(immediate: true) }
        keyTap.onKeyDown = { [weak self] in
            // 组词提交后文本变化会触发 valueChanged；这里只在输入法状态变化时兜底复查。
            guard let self, !self.keyTap.isComposing else { return }
            self.scheduleCheck(immediate: false)
        }
        keyTap.shortcuts = store.settings.shortcuts

        if Permissions.accessibilityGranted { monitor.start() }
        if Permissions.inputMonitoringGranted { keyTap.start() }
        // 权限在授权后才生效，轮询到位后再启动对应组件。
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryStartIfNeeded() }
        }
    }

    private var monitorStarted = false
    private func retryStartIfNeeded() {
        if Permissions.accessibilityGranted, !monitorStarted { monitorStarted = true; monitor.start() }
        if Permissions.inputMonitoringGranted, !keyTap.isRunning { keyTap.start() }
    }

    var shortcutsActive: Bool { keyTap.isRunning }

    private func settingsChanged(_ s: Settings) {
        L10n.language = s.language
        keyTap.shortcuts = s.shortcuts
        clearUI()
        scheduleCheck(immediate: true)
    }

    // MARK: 事件

    private func handle(_ event: FocusEvent) {
        switch event {
        case .focusChanged:
            keyTap.resetComposition(); dismissedIssueIDs.removeAll(); session.reset()
            clearUI(); scheduleCheck(immediate: false)
        case .valueChanged:
            scheduleCheck(immediate: Date().timeIntervalSince(lastPaste) < 0.5)
        case .selectionChanged:
            updatePopup()
        case .windowChanged:
            refreshGeometry()
        }
    }

    func scheduleCheck(immediate: Bool) {
        debounce?.cancel()
        generation += 1
        let gen = generation
        debounce = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: Self.debounceDelay) }
            guard !Task.isCancelled else { return }
            await self?.runCheck(generation: gen)
        }
    }

    private func runCheck(generation gen: Int) async {
        let settings = store.settings
        guard settings.enabled, Permissions.accessibilityGranted else { clearUI(); return }
        // 输入法组词期间不检查，组词结束后再检查。
        if keyTap.isRunning, keyTap.isComposing { return }
        guard let focus = AXReader.snapshot() else { clearUI(); return }
        guard settings.isAppEnabled(focus.bundleID) else { clearUI(); return }

        let session = self.session
        let issues = await Task.detached(priority: .userInitiated) {
            session.check(focus.text, settings: settings)
        }.value
        guard gen == generation else { return }
        current = (focus, issues)
        present()
    }

    // MARK: 展示

    private func present() {
        guard let cur = current else { return }
        refreshTimer?.invalidate(); refreshTimer = nil
        if cur.issues.isEmpty { clearUI(); return }

        let marks = markRects(cur)
        if marks.contains(where: { $0 != nil }) {
            badge.hide()
            overlay.show(zip(cur.issues, marks).compactMap { issue, rect in
                rect.map { ($0, issue.confidence == .medium) }
            })
            updatePopup()
            // 滚动、缩放不一定有通知，存在问题时低频刷新位置。
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }
        } else {
            // 第二层：能读到文本但定位不准，只显示计数徽标。
            overlay.hide(); suggestion.hide()
            if let frame = cur.focus.element.rect("AXFrame") {
                badge.show(count: cur.issues.count, frame: frame.cocoa) { [weak self] anchor in
                    self?.showBadgeMenu(at: anchor)
                }
            }
        }
    }

    /// 每个问题的屏幕矩形（Cocoa 坐标）；定位不可信返回 nil。
    private func markRects(_ cur: (focus: FocusedText, issues: [Issue])) -> [CGRect?] {
        let frame = cur.focus.element.rect("AXFrame")
        return cur.issues.map { issue -> CGRect? in
            guard let r = cur.focus.element.bounds(of: CFRange(location: issue.start, length: issue.end - issue.start)),
                  r.width > 0, r.height > 0, r.height < 200 else { return nil }
            if let frame, !frame.insetBy(dx: -4, dy: -4).intersects(r) { return nil }
            return r.cocoa
        }
    }

    private func refreshGeometry() {
        guard let cur = current, !cur.issues.isEmpty else { return }
        // 文本已变化则交给防抖检查；否则只更新位置。
        guard let snap = AXReader.snapshot(), snap.text == cur.focus.text else { scheduleCheck(immediate: false); return }
        current = (snap, cur.issues)
        let marks = markRects(current!)
        overlay.show(zip(cur.issues, marks).compactMap { issue, rect in
            rect.map { ($0, issue.confidence == .medium) }
        })
        updatePopup()
    }

    /// 光标落在问题词上时，在光标旁弹出建议浮窗。
    private func updatePopup() {
        guard let cur = current, let snap = AXReader.snapshot(), snap.text == cur.focus.text else { suggestion.hide(); return }
        let caret = snap.selection.location
        guard snap.selection.length == 0,
              let issue = cur.issues.first(where: { caret > $0.start && caret <= $0.end && !dismissedIssueIDs.contains($0.id) }),
              let rect = markRects((snap, [issue])).first ?? nil else { suggestion.hide(); return }
        if suggestion.issue?.id == issue.id { return }
        suggestion.show(issue: issue, near: rect,
                        onReplace: { [weak self] in self?.apply(issue) },
                        onIgnore: { [weak self] in self?.ignore(issue) },
                        onAllow: { [weak self] in self?.allow(issue) })
    }

    private func showBadgeMenu(at point: CGPoint) {
        guard let cur = current else { return }
        let menu = NSMenu()
        for issue in cur.issues {
            let item = NSMenuItem(title: "\(issue.sourceText) → \(issue.suggestion)", action: nil, keyEquivalent: "")
            item.target = self
            item.action = #selector(menuReplace(_:))
            item.representedObject = issue.id
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y), in: nil)
    }

    @objc private func menuReplace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let issue = current?.issues.first(where: { $0.id == id }) else { return }
        apply(issue)
    }

    func clearUI() {
        refreshTimer?.invalidate(); refreshTimer = nil
        overlay.hide(); suggestion.hide(); badge.hide()
        current = nil
    }

    // MARK: 动作

    private func handlePopupKey(_ key: PopupKey) {
        guard let issue = suggestion.issue else { return }
        switch key {
        case .replace: apply(issue)
        case .ignore: ignore(issue)
        case .allow: allow(issue)
        case .dismiss: dismissedIssueIDs.insert(issue.id); suggestion.hide()
        }
    }

    /// 替换一个问题，替换后自动复查。
    func apply(_ issue: Issue) {
        suggestion.hide()
        guard let snap = AXReader.snapshot(),
              Self.substring(snap.text, issue.range) == issue.sourceText else {
            scheduleCheck(immediate: true); return        // 文本已变，重新检查
        }
        Task {
            let ok = await TextReplacer.replace(element: snap.element, range: issue.range, with: issue.suggestion)
            if !ok { NSSound.beep() }
            scheduleCheck(immediate: true)
        }
    }

    private func ignore(_ issue: Issue) {
        session.ignoreOnce(issue)
        suggestion.hide()
        scheduleCheck(immediate: true)
    }

    private func allow(_ issue: Issue) {
        suggestion.hide()
        store.settings.addAllowPhrase(issue.sourceText)
    }

    private static func substring(_ text: String, _ range: Range<Int>) -> String? {
        let units = Array(text.utf16)
        guard range.upperBound <= units.count else { return nil }
        return String(decoding: units[range], as: UTF16.self)
    }

    // MARK: 第三层：快捷键

    func runShortcut(_ action: ShortcutAction) {
        switch action {
        case .toggleEnabled:
            store.settings.enabled.toggle()
        case .checkSelection:
            Task { await selectionAction(convert: false) }
        case .convertSelection:
            Task { await selectionAction(convert: true) }
        case .acceptSuggestion, .ignoreSuggestion:
            break
        }
    }

    func selectionAction(convert: Bool) async {
        let settings = store.settings
        guard settings.enabled, Permissions.accessibilityGranted else { return }
        if let (el, _) = AXReader.focusedElement(), el.isSecure { return }   // 密码框：不读取
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, !settings.isAppEnabled(bundle) { return }

        let point = NSEvent.mouseLocation
        guard let text = await TextReplacer.copySelection() else {
            result.show(original: "", issues: [], near: point, onReplaceAll: {})
            return
        }
        let issues = session.check(text, settings: settings)
        let converted = TextEdit.applyingAll(issues, to: text)
        if convert {
            guard !issues.isEmpty else { return }
            if !(await TextReplacer.paste(converted)) { NSSound.beep() }
            scheduleCheck(immediate: false)
        } else {
            result.show(original: text, issues: issues, near: point) { [weak self] in
                Task { _ = await TextReplacer.paste(converted); self?.scheduleCheck(immediate: false) }
            }
        }
    }
}
