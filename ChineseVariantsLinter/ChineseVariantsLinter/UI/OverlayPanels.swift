import AppKit
import SwiftUI
import CVLCore

// MARK: - 标记覆盖层（透明、置顶、点击穿透）

final class MarkView: NSView {
    struct Mark { var rect: CGRect; var medium: Bool }
    var marks: [Mark] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        for m in marks {
            (m.medium ? NSColor.systemOrange : NSColor.systemRed).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            // 波浪下划线
            let y = m.rect.minY + 1
            var x = m.rect.minX
            path.move(to: NSPoint(x: x, y: y))
            var up = true
            while x < m.rect.maxX {
                x = min(x + 2.5, m.rect.maxX)
                path.line(to: NSPoint(x: x, y: y + (up ? 2 : 0)))
                up.toggle()
            }
            path.stroke()
        }
    }
}

@MainActor
final class OverlayController {
    private let window: NSWindow
    private let view = MarkView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = view
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreens() }
        }
        fitToScreens()
    }

    private func fitToScreens() {
        let union = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        window.setFrame(union, display: false)
    }

    /// `rects` 为 Cocoa 屏幕坐标。
    func show(_ marks: [(rect: CGRect, medium: Bool)]) {
        guard !marks.isEmpty else { hide(); return }
        let origin = window.frame.origin
        view.marks = marks.map { .init(rect: $0.rect.offsetBy(dx: -origin.x, dy: -origin.y), medium: $0.medium) }
        window.orderFrontRegardless()
    }

    func hide() {
        view.marks = []
        window.orderOut(nil)
    }
}

// MARK: - 非激活浮动面板基类

class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present<V: View>(_ view: V, near rect: CGRect) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        contentView = host
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 4)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            if origin.y < f.minY { origin.y = rect.maxY + 4 }           // 下方放不下则放上方
            origin.x = min(max(origin.x, f.minX), f.maxX - size.width)
        }
        setFrame(CGRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }
}

// MARK: - 建议浮窗

struct SuggestionView: View {
    let issue: Issue
    let onReplace: () -> Void
    let onIgnore: () -> Void
    let onAllow: () -> Void

    private var header: String {
        let region = issue.targetVariant.displayName
        return issue.type == .script
            ? L10n.t("issue.script", region, issue.sourceText, issue.suggestion)
            : L10n.t("issue.term", region, issue.sourceText, issue.suggestion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header).font(.system(size: 12)).foregroundStyle(.secondary)
            if issue.confidence == .medium {
                Text(L10n.t("issue.medium")).font(.system(size: 11)).foregroundStyle(.orange)
            }
            row("1", L10n.t("popup.replace", issue.suggestion), onReplace)
            row("2", L10n.t("popup.ignore"), onIgnore)
            row("3", L10n.t("popup.allow"), onAllow)
        }
        .padding(8)
        .frame(minWidth: 200, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .padding(2)
    }

    private func row(_ key: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(key).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 16, height: 16).background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
        }.buttonStyle(.plain)
    }
}

@MainActor
final class SuggestionController {
    private let panel = FloatingPanel()
    private(set) var issue: Issue?
    var isVisible: Bool { issue != nil }

    func show(issue: Issue, near rect: CGRect, onReplace: @escaping () -> Void,
              onIgnore: @escaping () -> Void, onAllow: @escaping () -> Void) {
        self.issue = issue
        panel.present(SuggestionView(issue: issue, onReplace: onReplace, onIgnore: onIgnore, onAllow: onAllow), near: rect)
    }

    func hide() {
        issue = nil
        panel.orderOut(nil)
    }
}

// MARK: - 第二层：计数徽标

struct BadgeView: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("\(count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 2)
                .background(Color.orange, in: Capsule())
        }.buttonStyle(.plain)
    }
}

@MainActor
final class BadgeController {
    private let panel = FloatingPanel()
    var isVisible: Bool { panel.isVisible }

    /// `frame` 为输入框的 Cocoa 坐标矩形；徽标放在右上角外侧。
    func show(count: Int, frame: CGRect, action: @escaping (_ anchor: CGPoint) -> Void) {
        let anchor = CGPoint(x: frame.maxX, y: frame.maxY)
        let host = NSHostingView(rootView: BadgeView(count: count) { action(NSEvent.mouseLocation) })
        let size = host.fittingSize
        panel.contentView = host
        panel.hasShadow = false
        panel.setFrame(CGRect(x: anchor.x - size.width - 2, y: anchor.y - size.height - 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

// MARK: - 第三层：检查结果

struct ResultView: View {
    let original: String
    let issues: [Issue]
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("result.title")).font(.headline)
            if issues.isEmpty {
                Text(L10n.t("result.none")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(issues) { issue in
                            HStack {
                                Text(issue.sourceText).foregroundStyle(issue.confidence == .medium ? .orange : .red)
                                Text("→")
                                Text(issue.suggestion).bold()
                            }.font(.system(size: 13))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
            }
            HStack {
                Spacer()
                Button(L10n.t("result.close"), action: onClose).keyboardShortcut(.cancelAction)
                if !issues.isEmpty {
                    Button(L10n.t("result.replaceAll"), action: onReplaceAll).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(12).frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        .padding(2)
    }
}

@MainActor
final class ResultController {
    private let panel = FloatingPanel()
    func show(original: String, issues: [Issue], near point: CGPoint,
              onReplaceAll: @escaping () -> Void) {
        panel.present(ResultView(original: original, issues: issues,
                                 onReplaceAll: { [weak self] in self?.hide(); onReplaceAll() },
                                 onClose: { [weak self] in self?.hide() }),
                      near: CGRect(x: point.x, y: point.y, width: 1, height: 1))
    }
    func hide() { panel.orderOut(nil) }
}
