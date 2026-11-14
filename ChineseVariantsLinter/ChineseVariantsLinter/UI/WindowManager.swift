import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettings() { show(&settingsWindow, title: L10n.t("menu.settings"), content: SettingsRoot()) }

    func showOnboarding() {
        show(&onboardingWindow, title: L10n.t("onb.title"), content: OnboardingView { [weak self] in
            SettingsStore.shared.settings.onboardingCompleted = true
            self?.onboardingWindow?.close()
        })
    }

    private func show<V: View>(_ slot: inout NSWindow?, title: String, content: V) {
        if let w = slot { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentViewController: NSHostingController(rootView: content))
        w.title = title
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        slot = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.settingsWindow === w { self?.settingsWindow = nil }
                if self?.onboardingWindow === w { self?.onboardingWindow = nil }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
