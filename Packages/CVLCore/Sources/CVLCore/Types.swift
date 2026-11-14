import Foundation

/// 目标地区。与浏览器扩展版的 `VariantCode` 取值一致。
public enum VariantCode: String, Codable, CaseIterable, Sendable {
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case zhHK = "zh-HK"
    case zhHant = "zh-Hant"
}

public enum DetectionLevel: String, Codable, CaseIterable, Sendable {
    /// 字形 + 地区用词。
    case standard
    /// 只检查字形。
    case relaxed
}

public enum IssueType: String, Codable, Sendable {
    case script
    case variantTerm = "variant_term"
}

public enum Confidence: String, Codable, Sendable {
    case high
    case medium
}

/// 一个检测结果。`start` / `end` 是 UTF-16 下标（与 NSString、Accessibility 的范围一致）。
public struct Issue: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: IssueType
    public var subtype: String
    public var sourceText: String
    public var targetVariant: VariantCode
    public var start: Int
    public var end: Int
    public var confidence: Confidence
    public var ruleId: String
    /// 建议替换文本（目前每个问题只有一个建议）。
    public var suggestion: String

    public var range: Range<Int> { start..<end }
    public var nsRange: NSRange { NSRange(location: start, length: end - start) }
}

/// 用户自定义词组：命中 `from` 时建议替换为 `to`；按目标地区分开存放。
public struct CustomPhrase: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var enabled: Bool

    public init(id: String, from: String, to: String, enabled: Bool = true) {
        self.id = id
        self.from = from
        self.to = to
        self.enabled = enabled
    }
}

/// 内置词汇规则（`Shared/data/term-rules.json`）和用户词组共用的形态。
public struct TermRule: Codable, Equatable, Sendable {
    public var id: String
    public var sourceTerm: String
    public var targets: [String: String]
    public var safe: Bool
    public var enabled: Bool
    public var priority: Int
    public var isUser: Bool

    enum CodingKeys: String, CodingKey {
        case id, sourceTerm, targets, safe, enabled, priority, source
    }

    public init(id: String, sourceTerm: String, targets: [String: String], safe: Bool,
                enabled: Bool, priority: Int, isUser: Bool) {
        self.id = id; self.sourceTerm = sourceTerm; self.targets = targets
        self.safe = safe; self.enabled = enabled; self.priority = priority; self.isUser = isUser
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourceTerm = try c.decode(String.self, forKey: .sourceTerm)
        targets = try c.decode([String: String].self, forKey: .targets)
        safe = try c.decode(Bool.self, forKey: .safe)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        priority = try c.decode(Int.self, forKey: .priority)
        isUser = (try c.decode(String.self, forKey: .source)) == "user"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceTerm, forKey: .sourceTerm)
        try c.encode(targets, forKey: .targets)
        try c.encode(safe, forKey: .safe)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(priority, forKey: .priority)
        try c.encode(isUser ? "user" : "builtin", forKey: .source)
    }
}
