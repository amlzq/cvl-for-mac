import AppKit
import Carbon.HIToolbox
import CVLCore

/// 合成按键的统一入口。带标记，便于自己的事件监听忽略。
enum Synth {
    static let marker: Int64 = 0x43564C // "CVL"

    /// 等待用户松开修饰键（热键触发时通常还按着 ⌃⇧），避免与合成按键叠加。
    static func waitForModifiersReleased(timeout: TimeInterval = 1.0) async {
        let mask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(mask).isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    static func press(_ key: Int, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    static func paste() { press(kVK_ANSI_V, flags: .maskCommand) }
    static func copy() { press(kVK_ANSI_C, flags: .maskCommand) }
}

/// 建议浮窗打开时被拦截的按键。
enum PopupKey { case replace, ignore, allow, dismiss }

/// 全局按键监听（需要辅助功能 + 输入监控）。用途：
/// 1. 全局快捷键；2. 建议浮窗的数字键 / Tab / Esc；3. 识别粘贴（Cmd+V）；
/// 4. 粗略判断输入法是否正在组词。
@MainActor
final class KeyTap {
    var shortcuts: [ShortcutAction: ShortcutCombo] = [:]
    var onShortcut: ((ShortcutAction) -> Void)?
    /// 浮窗可见时返回 true 的回调决定是否拦截。
    var popupVisible: () -> Bool = { false }
    var onPopupKey: ((PopupKey) -> Void)?
    var onPaste: (() -> Void)?
    /// 任意普通按键（用于触发文本变化之外的重新检查，如组词提交）。
    var onKeyDown: (() -> Void)?

    private(set) var isComposing = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { me.handle(type: type, event: event) }
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
    }

    func resetComposition() { isComposing = false }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == .keyDown else { return pass }
        if event.getIntegerValueField(.eventSourceUserData) == Synth.marker { return pass }

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = event.flags.rawValue & ShortcutModifiers.mask

        // 全局快捷键
        for (action, combo) in shortcuts where combo.keyCode == code && combo.modifiers == mods {
            DispatchQueue.main.async { [weak self] in self?.onShortcut?(action) }
            return nil
        }

        // 粘贴：Cmd+V
        if mods == ShortcutModifiers.command, code == UInt16(kVK_ANSI_V) {
            DispatchQueue.main.async { [weak self] in self?.onPaste?() }
            return pass
        }

        // 建议浮窗按键（不带修饰键）
        if mods == 0, popupVisible() {
            var key: PopupKey?
            switch Int(code) {
            case kVK_Tab, kVK_ANSI_1, kVK_ANSI_Keypad1: key = .replace
            case kVK_ANSI_2, kVK_ANSI_Keypad2: key = .ignore
            case kVK_ANSI_3, kVK_ANSI_Keypad3: key = .allow
            case kVK_Escape: key = .dismiss
            default: break
            }
            if let key {
                DispatchQueue.main.async { [weak self] in self?.onPopupKey?(key) }
                return nil
            }
        }

        updateComposition(code: code, mods: mods)
        DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
        return pass
    }

    /// 输入法组词的粗略判断：当前输入源是输入法，且最近一次是字母键，直到出现提交键（空格、回车、数字选词、Esc、Tab）。
    private func updateComposition(code: UInt16, mods: UInt64) {
        guard Self.currentSourceIsIME(), mods & ~ShortcutModifiers.shift == 0 else { isComposing = false; return }
        let commit: Set<Int> = [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
                                kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        if commit.contains(Int(code)) { isComposing = false }
        else if code != UInt16(kVK_Delete) || isComposing { isComposing = true }
    }

    private static func currentSourceIsIME() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue()
        return (type as String) == (kTISTypeKeyboardInputMode as String)
    }
}
