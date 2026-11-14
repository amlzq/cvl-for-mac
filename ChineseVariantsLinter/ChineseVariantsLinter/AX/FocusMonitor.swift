import AppKit
import ApplicationServices

enum FocusEvent { case focusChanged, valueChanged, selectionChanged, windowChanged }

/// 通过 `AXObserver` 监听前台应用的焦点、文本、选区和窗口变化。
@MainActor
final class FocusMonitor {
    var onEvent: ((FocusEvent) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXElement?
    private var observedPID: pid_t = 0
    private var focused: AXElement?
    private var workspaceToken: NSObjectProtocol?

    func start() {
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachToFrontmost() }
        }
        attachToFrontmost()
    }

    func stop() {
        if let t = workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        detach()
    }

    func attachToFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else {
            detach(); onEvent?(.focusChanged); return
        }
        if app.processIdentifier == observedPID, observer != nil { onEvent?(.focusChanged); return }
        detach()
        attach(pid: app.processIdentifier)
        onEvent?(.focusChanged)
    }

    private func attach(pid: pid_t) {
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<FocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            DispatchQueue.main.async { me.handle(notification: name, element: element) }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let app = AXElement.application(pid: pid)
        // Chromium / Electron 默认不暴露辅助功能树，需要主动开启。
        app.setBool("AXManualAccessibility", true)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification,
                  kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, app.raw, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs; appElement = app; observedPID = pid
        observeFocusedElement()
    }

    private func detach() {
        unobserveFocused()
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observer = nil; appElement = nil; observedPID = 0
    }

    private func observeFocusedElement() {
        unobserveFocused()
        guard let obs = observer, let app = appElement, let el = app.element(kAXFocusedUIElementAttribute),
              !el.isSecure else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
            AXObserverAddNotification(obs, el.raw, n as CFString, refcon)
        }
        focused = el
    }

    private func unobserveFocused() {
        guard let obs = observer, let el = focused else { focused = nil; return }
        for n in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
            AXObserverRemoveNotification(obs, el.raw, n as CFString)
        }
        focused = nil
    }

    private func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification:
            observeFocusedElement(); onEvent?(.focusChanged)
        case kAXValueChangedNotification: onEvent?(.valueChanged)
        case kAXSelectedTextChangedNotification: onEvent?(.selectionChanged)
        default: onEvent?(.windowChanged)
        }
    }
}
