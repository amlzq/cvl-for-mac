import Foundation

public let maxPhrasesPerVariant = 1000
public let maxAllowPhrases = 1000
public let maxImportFileBytes = 1024 * 1024
/// 实时检查的最大字符数（UTF-16 码元），与浏览器扩展的 MAX_FULLTEXT_LENGTH 一致。
public let maxCheckLength = 20_000

/// 用户词库：允许词与自定义词组，均按目标地区分开保存。
public struct UserDictionary: Codable, Equatable, Sendable {
    public var allowPhrases: [VariantCode: [String]]
    public var phrases: [VariantCode: [CustomPhrase]]

    public init(allowPhrases: [VariantCode: [String]] = [:], phrases: [VariantCode: [CustomPhrase]] = [:]) {
        self.allowPhrases = allowPhrases
        self.phrases = phrases
    }

    public func allow(_ v: VariantCode) -> [String] { allowPhrases[v] ?? [] }
    public func custom(_ v: VariantCode) -> [CustomPhrase] { phrases[v] ?? [] }
}

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    /// 检查选中文本并弹窗。
    case checkSelection
    /// 转换选中文本并写回。
    case convertSelection
    /// 总开关。
    case toggleEnabled
    /// 接受当前建议（浮窗打开时）。
    case acceptSuggestion
    /// 忽略当前建议。
    case ignoreSuggestion
}

/// 全局快捷键组合。`keyCode` 是 macOS 虚拟键码，`modifiers` 是 CGEventFlags 的 rawValue 子集。
public struct ShortcutCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var display: String

    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
    }
}

public enum InterfaceLanguage: String, Codable, CaseIterable, Sendable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant-TW", zhHK = "zh-Hant-HK"
}

public struct Settings: Codable, Equatable, Sendable {
    /// 总开关。
    public var enabled: Bool
    public var targetVariant: VariantCode
    public var detectionLevel: DetectionLevel
    public var userDictionary: UserDictionary
    /// 被禁用的应用（bundle identifier）。
    public var disabledApps: [String]
    public var shortcuts: [ShortcutAction: ShortcutCombo]
    public var language: InterfaceLanguage
    public var launchAtLogin: Bool
    public var onboardingCompleted: Bool

    public static let defaultShortcuts: [ShortcutAction: ShortcutCombo] = [
        // ctrl+shift 修饰；键码取自 Carbon kVK_ANSI_*。
        .checkSelection: ShortcutCombo(keyCode: 40, modifiers: ShortcutModifiers.ctrlShift, display: "⌃⇧K"),
        .convertSelection: ShortcutCombo(keyCode: 37, modifiers: ShortcutModifiers.ctrlShift, display: "⌃⇧L"),
        .toggleEnabled: ShortcutCombo(keyCode: 32, modifiers: ShortcutModifiers.ctrlShift, display: "⌃⇧U"),
        // 对应扩展版的「接受下一处建议」：有浮窗时接受浮窗项，否则接受光标处问题。
        .acceptSuggestion: ShortcutCombo(keyCode: 38, modifiers: ShortcutModifiers.ctrlShift, display: "⌃⇧J"),
        // 对应扩展版的「忽略」：仅本次会话，不落盘。
        .ignoreSuggestion: ShortcutCombo(keyCode: 34, modifiers: ShortcutModifiers.ctrlShift, display: "⌃⇧I"),
    ]

    public init(
        enabled: Bool = true,
        targetVariant: VariantCode = Settings.detectDefaultVariant(),
        detectionLevel: DetectionLevel = .standard,
        userDictionary: UserDictionary = UserDictionary(),
        disabledApps: [String] = [],
        shortcuts: [ShortcutAction: ShortcutCombo] = Settings.defaultShortcuts,
        language: InterfaceLanguage = .system,
        launchAtLogin: Bool = false,
        onboardingCompleted: Bool = false
    ) {
        self.enabled = enabled
        self.targetVariant = targetVariant
        self.detectionLevel = detectionLevel
        self.userDictionary = userDictionary
        self.disabledApps = disabledApps
        self.shortcuts = shortcuts
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.onboardingCompleted = onboardingCompleted
    }

    /// 根据系统首选语言推断默认目标地区；无法识别时为简体中文。
    public static func detectDefaultVariant(preferredLanguages: [String] = Locale.preferredLanguages) -> VariantCode {
        guard let first = preferredLanguages.first?.lowercased(), first.hasPrefix("zh") else { return .zhCN }
        if first.contains("tw") { return .zhTW }
        if first.contains("hk") || first.contains("mo") { return .zhHK }
        if first.contains("hant") { return .zhHant }
        return .zhCN
    }

    // 向前兼容：缺失字段使用默认值，异常数据被收拢。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        targetVariant = try c.decodeIfPresent(VariantCode.self, forKey: .targetVariant) ?? d.targetVariant
        detectionLevel = try c.decodeIfPresent(DetectionLevel.self, forKey: .detectionLevel) ?? d.detectionLevel
        userDictionary = try c.decodeIfPresent(UserDictionary.self, forKey: .userDictionary) ?? d.userDictionary
        disabledApps = try c.decodeIfPresent([String].self, forKey: .disabledApps) ?? d.disabledApps
        // 新增动作在旧配置里缺失时回落到默认键位，避免设置页出现空绑定。
        let decodedShortcuts = try c.decodeIfPresent([ShortcutAction: ShortcutCombo].self, forKey: .shortcuts) ?? [:]
        shortcuts = Settings.defaultShortcuts.merging(decodedShortcuts) { _, new in new }
        language = try c.decodeIfPresent(InterfaceLanguage.self, forKey: .language) ?? d.language
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        userDictionary = Settings.normalized(userDictionary)
    }

    /// 去空白、去重、截断上限，丢弃 `from` 为空的词组。
    public static func normalized(_ dict: UserDictionary) -> UserDictionary {
        var out = UserDictionary()
        for v in VariantCode.allCases {
            var seen = Set<String>(), allow: [String] = []
            for item in dict.allow(v) {
                let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || !seen.insert(t).inserted { continue }
                allow.append(t)
                if allow.count >= maxAllowPhrases { break }
            }
            var phrases: [CustomPhrase] = []
            for p in dict.custom(v) {
                let from = p.from.trimmingCharacters(in: .whitespacesAndNewlines)
                let to = p.to.trimmingCharacters(in: .whitespacesAndNewlines)
                if from.isEmpty { continue }
                phrases.append(CustomPhrase(id: p.id.isEmpty ? "phrase-\(phrases.count)" : p.id,
                                            from: from, to: to, enabled: p.enabled))
                if phrases.count >= maxPhrasesPerVariant { break }
            }
            out.allowPhrases[v] = allow
            out.phrases[v] = phrases
        }
        return out
    }

    /// 某应用是否启用检查。
    public func isAppEnabled(_ bundleID: String?) -> Bool {
        guard enabled else { return false }
        guard let id = bundleID else { return true }
        return !disabledApps.contains(id)
    }
}

public enum ShortcutModifiers {
    // 与 CGEventFlags 的 rawValue 一致：shift 0x20000，control 0x40000，option 0x80000，command 0x100000。
    public static let shift: UInt64 = 0x20000
    public static let control: UInt64 = 0x40000
    public static let option: UInt64 = 0x80000
    public static let command: UInt64 = 0x100000
    public static let mask: UInt64 = shift | control | option | command
    public static let ctrlShift: UInt64 = control | shift
}

// MARK: - 词库编辑

public struct PhraseImportResult: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    /// 因超过每个地区的数量上限而被跳过的新词组数。
    public var skipped = 0
}

extension Settings {
    /// 加入允许词（目标地区 = 当前目标）。已存在或为空时返回 false。
    @discardableResult
    public mutating func addAllowPhrase(_ term: String) -> Bool {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = userDictionary.allow(targetVariant)
        guard !t.isEmpty, !list.contains(t), list.count < maxAllowPhrases else { return false }
        list.append(t)
        userDictionary.allowPhrases[targetVariant] = list
        return true
    }

    public mutating func removeAllowPhrase(_ term: String) {
        userDictionary.allowPhrases[targetVariant] = userDictionary.allow(targetVariant).filter { $0 != term }
    }

    /// 新增或更新自定义词组；原词已存在时更新其替换词。
    @discardableResult
    public mutating func addPhrase(variant: VariantCode, from: String, to: String) -> Bool {
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !t.isEmpty else { return false }
        var list = userDictionary.custom(variant)
        if let i = list.firstIndex(where: { $0.from == f }) {
            list[i].to = t
        } else {
            guard list.count < maxPhrasesPerVariant else { return false }
            list.append(CustomPhrase(id: "phrase-\(UUID().uuidString)", from: f, to: t))
        }
        userDictionary.phrases[variant] = list
        return true
    }

    public mutating func removePhrase(variant: VariantCode, id: String) {
        userDictionary.phrases[variant] = userDictionary.custom(variant).filter { $0.id != id }
    }

    public mutating func setPhraseEnabled(variant: VariantCode, id: String, enabled: Bool) {
        var list = userDictionary.custom(variant)
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].enabled = enabled }
        userDictionary.phrases[variant] = list
    }

    /// 导入词条：同一原词已存在时更新替换词，否则追加；超过上限的新词条被跳过并计数。
    @discardableResult
    public mutating func importPhrases(variant: VariantCode, rows: [(from: String, to: String)]) -> PhraseImportResult {
        var result = PhraseImportResult()
        var list = userDictionary.custom(variant)
        for row in rows {
            if let i = list.firstIndex(where: { $0.from == row.from }) {
                list[i].to = row.to
                result.updated += 1
            } else if list.count >= maxPhrasesPerVariant {
                result.skipped += 1
            } else {
                list.append(CustomPhrase(id: "phrase-\(UUID().uuidString)", from: row.from, to: row.to))
                result.added += 1
            }
        }
        userDictionary.phrases[variant] = list
        return result
    }
}
