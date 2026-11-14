import AppKit
import ApplicationServices

/// 对 `AXUIElement` 的薄封装。对其他应用的所有读写都集中在 AX/ 目录下。
struct AXElement {
    let raw: AXUIElement
    init(_ raw: AXUIElement) { self.raw = raw }

    static func application(pid: pid_t) -> AXElement { AXElement(AXUIElementCreateApplication(pid)) }

    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(raw, name as CFString, &value)
        return err == .success ? value : nil
    }

    func string(_ name: String) -> String? { attribute(name) as? String }

    func element(_ name: String) -> AXElement? {
        guard let v = attribute(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXElement(v as! AXUIElement)
    }

    func range(_ name: String) -> CFRange? {
        guard let v = attribute(name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }

    func rect(_ name: String) -> CGRect? {
        guard let v = attribute(name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var pid: pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(raw, &p) == .success ? p : nil
    }

    var isSecure: Bool {
        subrole == (kAXSecureTextFieldSubrole as String) || role == "AXSecureTextField"
    }

    /// 屏幕坐标（AX：左上角为原点）下某段字符范围的外接矩形。读不到返回 nil。
    func bounds(of range: CFRange) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(raw, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out)
        guard err == .success, let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    @discardableResult
    func setSelectedRange(_ range: CFRange) -> Bool {
        var r = range
        guard let v = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(raw, kAXSelectedTextRangeAttribute as CFString, v) == .success
    }

    func setBool(_ name: String, _ value: Bool) {
        _ = AXUIElementSetAttributeValue(raw, name as CFString, value as CFBoolean)
    }
}

extension CGRect {
    /// AX 坐标（左上角原点，主屏）转 Cocoa 坐标（左下角原点）。
    var cocoa: CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: origin.x, y: h - origin.y - size.height, width: size.width, height: size.height)
    }
}

/// 焦点输入框的一次快照。
struct FocusedText {
    let element: AXElement
    let pid: pid_t
    let bundleID: String?
    let text: String
    /// UTF-16 下标的选区。
    let selection: CFRange
}

enum AXReader {
    /// 当前焦点元素。密码框在读取任何内容之前就被丢弃。
    static func focusedElement() -> (element: AXElement, pid: pid_t)? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
        let appEl = AXElement.application(pid: app.processIdentifier)
        guard let el = appEl.element(kAXFocusedUIElementAttribute) else { return nil }
        return (el, app.processIdentifier)
    }

    static let maxTextLength = 50_000

    static func snapshot() -> FocusedText? {
        guard let (el, pid) = focusedElement() else { return nil }
        if el.isSecure { return nil }                  // 先判断类型，再读内容
        guard let text = el.string(kAXValueAttribute), text.utf16.count <= maxTextLength else { return nil }
        let sel = el.range(kAXSelectedTextRangeAttribute) ?? CFRange(location: 0, length: 0)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return FocusedText(element: el, pid: pid, bundleID: bundle, text: text, selection: sel)
    }
}
