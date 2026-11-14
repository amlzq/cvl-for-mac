import AppKit
import SwiftUI

struct OnboardingView: View {
    @State private var ax = Permissions.accessibilityGranted
    @State private var input = Permissions.inputMonitoringGranted
    let onDone: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("onb.title")).font(.title2.bold())
            Text(L10n.t("onb.body"))
            permissionRow(L10n.t("onb.ax"), granted: ax) {
                Permissions.requestAccessibility(); Permissions.openAccessibilitySettings()
            }
            permissionRow(L10n.t("onb.input"), granted: input) {
                Permissions.requestInputMonitoring(); Permissions.openInputMonitoringSettings()
            }
            Text(L10n.t("onb.restartHint")).font(.footnote).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L10n.t("onb.done"), action: onDone).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 480)
        .onReceive(timer) { _ in ax = Permissions.accessibilityGranted; input = Permissions.inputMonitoringGranted }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary)
            Text(title)
            Spacer()
            if granted { Text(L10n.t("onb.granted")).foregroundStyle(.secondary) }
            else { Button(L10n.t("onb.open"), action: action) }
        }
    }
}
