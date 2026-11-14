//
//  ChineseVariantsLinterApp.swift
//  ChineseVariantsLinter
//

import SwiftUI
import CVLCore

@main
struct ChineseVariantsLinterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SettingsStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: store.settings.enabled ? "character.book.closed.fill" : "character.book.closed")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Coordinator.shared.start()
            let s = SettingsStore.shared.settings
            if !s.onboardingCompleted || !Permissions.accessibilityGranted {
                WindowManager.shared.showOnboarding()
            }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        let frontApp = NSWorkspace.shared.frontmostApplication
        Toggle(L10n.t("menu.enabled"), isOn: $store.settings.enabled)
        if !Permissions.accessibilityGranted {
            Button(L10n.t("menu.noPermission")) { WindowManager.shared.showOnboarding() }
        }
        Divider()
        Picker(L10n.t("menu.target"), selection: $store.settings.targetVariant) {
            ForEach(VariantCode.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        Picker(L10n.t("menu.level"), selection: $store.settings.detectionLevel) {
            ForEach(DetectionLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        if let id = frontApp?.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            Toggle(L10n.t("menu.thisApp", frontApp?.localizedName ?? id), isOn: Binding(
                get: { !store.settings.disabledApps.contains(id) },
                set: { on in
                    if on { store.settings.disabledApps.removeAll { $0 == id } }
                    else if !store.settings.disabledApps.contains(id) { store.settings.disabledApps.append(id) }
                }))
        }
        Divider()
        Button(L10n.t("menu.checkSelection")) { Coordinator.shared.runShortcut(.checkSelection) }
        Button(L10n.t("menu.convertSelection")) { Coordinator.shared.runShortcut(.convertSelection) }
        Divider()
        Button(L10n.t("menu.settings")) { WindowManager.shared.showSettings() }.keyboardShortcut(",")
        Button(L10n.t("menu.permissions")) { WindowManager.shared.showOnboarding() }
        Divider()
        Button(L10n.t("menu.quit")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
