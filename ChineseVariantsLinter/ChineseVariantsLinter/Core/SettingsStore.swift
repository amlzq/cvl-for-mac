import Foundation
import CVLCore
import ServiceManagement
import Combine

/// 设置存储：JSON 写入 UserDefaults，仅保存在本机。
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "settings.v1"

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            if settings.launchAtLogin != oldValue.launchAtLogin { applyLaunchAtLogin() }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("登录时启动设置失败：\(error.localizedDescription)")
        }
    }

    /// 系统里的实际状态可能被用户在系统设置中改过，启动时同步一次。
    func syncLaunchAtLoginState() {
        let actual = SMAppService.mainApp.status == .enabled
        if actual != settings.launchAtLogin { settings.launchAtLogin = actual }
    }
}
