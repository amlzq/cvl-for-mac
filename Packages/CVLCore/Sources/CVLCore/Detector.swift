import Foundation

/// 内置词汇规则（`Shared/data/term-rules.json`），只加载一次。
public enum BuiltinRules {
    public static let all: [TermRule] = {
        guard let url = Bundle.module.url(forResource: "Resources/term-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([TermRule].self, from: data) else {
            assertionFailure("缺少内置词汇规则")
            return []
        }
        return rules
    }()
}

private struct Ranked {
    var issue: Issue
    var priority: Int
    var order: Int
}

/// 检测器：输入文本和设置，输出问题列表。行为与浏览器扩展版 `detectText` 一致。
public struct Detector: Sendable {
    public init() {}

    private static let scriptPriority = 100

    public func detect(text: String, settings: Settings, ignoredIssueIDs: Set<String> = []) -> [Issue] {
        let units = Array(text.utf16)
        guard text.contains(where: { !$0.isWhitespace }) else { return [] }
        let variant = settings.targetVariant

        let allow = Set(settings.userDictionary.allow(variant))
        let rules = Self.termRules(settings: settings, variant: variant)

        var issues: [Ranked] = []
        if settings.detectionLevel == .standard {
            issues = Self.pickNonOverlapping(
                Self.detectTerms(units, variant: variant, rules: rules, allow: allow, ignored: ignoredIssueIDs))
        }

        let scripts = Self.pickNonOverlapping(
            Self.detectScripts(units, variant: variant, allow: allow, ignored: ignoredIssueIDs))
        let occupied = issues.map(\.issue)
        for c in scripts where !occupied.contains(where: { Self.overlaps($0, c.issue) }) {
            issues.append(c)
        }
        return Self.sorted(issues).map(\.issue)
    }

    // MARK: 规则

    static func termRules(settings: Settings, variant: VariantCode) -> [TermRule] {
        let user: [TermRule] = settings.userDictionary.custom(variant).enumerated()
            .filter { $0.element.enabled }
            .map { index, p in
                TermRule(id: p.id.isEmpty ? "user-phrase-\(index)" : p.id, sourceTerm: p.from,
                         targets: [variant.rawValue: p.to], safe: true, enabled: true,
                         priority: 10_000, isUser: true)
            }
        let builtin = BuiltinRules.all.filter { $0.enabled && $0.targets[variant.rawValue] != nil }
        return user + builtin
    }

    // MARK: 词汇

    private static func detectTerms(_ text: [UInt16], variant: VariantCode, rules: [TermRule],
                                    allow: Set<String>, ignored: Set<String>) -> [Ranked] {
        let sorted = rules.enumerated().sorted { l, r in
            let ll = l.element.sourceTerm.utf16.count, rl = r.element.sourceTerm.utf16.count
            if ll != rl { return ll > rl }
            if l.element.priority != r.element.priority { return l.element.priority > r.element.priority }
            return l.offset < r.offset
        }.map(\.element)

        var matches: [Ranked] = []
        for rule in sorted {
            guard let replacement = rule.targets[variant.rawValue], replacement != rule.sourceTerm,
                  !allow.contains(rule.sourceTerm) else { continue }
            let term = Array(rule.sourceTerm.utf16)
            guard !term.isEmpty else { continue }
            for index in occurrences(of: term, in: text) {
                let end = index + term.count
                let id = "\(rule.id):\(index):\(end):\(variant.rawValue)"
                if ignored.contains(id) { continue }
                matches.append(Ranked(
                    issue: Issue(id: id, type: .variantTerm, subtype: rule.isUser ? "user-phrase" : "builtin-term",
                                 sourceText: rule.sourceTerm, targetVariant: variant, start: index, end: end,
                                 confidence: rule.safe ? .high : .medium, ruleId: rule.id, suggestion: replacement),
                    priority: rule.priority, order: matches.count))
            }
        }
        return matches
    }

    // MARK: 字形

    private struct ScriptChange {
        var start: Int, end: Int
        var source: [UInt16], target: [UInt16]
    }

    /// 目标地区中可接受、不应报告的「原字 → 转换结果」。
    private static let tolerated: [VariantCode: [String: String]] = [.zhTW: ["台": "臺"]]

    private static func findScriptChanges(_ text: [UInt16], variant: VariantCode) -> [ScriptChange] {
        let converted = ScriptConverter.shared.convert(text, to: variant)
        if converted == text { return [] }

        let tolerance = tolerated[variant]
        let src = scalarChunks(text), dst = scalarChunks(converted)
        var changes: [ScriptChange] = []

        if src.count == dst.count {
            var offset = 0
            for (i, s) in src.enumerated() {
                let t = dst[i]
                if s != t {
                    let sStr = String(decoding: s, as: UTF16.self), tStr = String(decoding: t, as: UTF16.self)
                    if tolerance?[sStr] != tStr {
                        changes.append(ScriptChange(start: offset, end: offset + s.count, source: s, target: t))
                    }
                }
                offset += s.count
            }
        } else {
            var prefix = 0
            while prefix < text.count, prefix < converted.count, text[prefix] == converted[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < text.count - prefix, suffix < converted.count - prefix,
                  text[text.count - 1 - suffix] == converted[converted.count - 1 - suffix] { suffix += 1 }
            // 不在代理对中间切分。
            if prefix > 0, isLowSurrogate(text[prefix]) { prefix -= 1 }
            if suffix > 0, isLowSurrogate(text[text.count - suffix]) { suffix -= 1 }
            changes.append(ScriptChange(
                start: prefix, end: text.count - suffix,
                source: Array(text[prefix..<(text.count - suffix)]),
                target: Array(converted[prefix..<(converted.count - suffix)])))
        }
        return changes
    }

    private static func detectScripts(_ text: [UInt16], variant: VariantCode,
                                      allow: Set<String>, ignored: Set<String>) -> [Ranked] {
        let allowUnits = allow.filter { !$0.isEmpty }.map { Array($0.utf16) }
        var out: [Ranked] = []
        for change in findScriptChanges(text, variant: variant) {
            let source = String(decoding: change.source, as: UTF16.self)
            let target = String(decoding: change.target, as: UTF16.self)
            if allow.contains(source) { continue }
            if isCovered(text, start: change.start, end: change.end, by: allowUnits) { continue }
            let sensitive = ScriptConverter.shared.isContextSensitive(change.source, variant: variant)
            let ruleId = "opencc:\(source)>\(target)"
            let id = "\(ruleId):\(change.start):\(change.end):\(variant.rawValue)"
            if ignored.contains(id) { continue }
            out.append(Ranked(
                issue: Issue(id: id, type: .script, subtype: sensitive ? "context-sensitive-char" : "safe-char",
                             sourceText: source, targetVariant: variant, start: change.start, end: change.end,
                             confidence: sensitive ? .medium : .high, ruleId: ruleId, suggestion: target),
                priority: scriptPriority, order: out.count))
        }
        return out
    }

    // MARK: 选择

    private static func overlaps(_ a: Issue, _ b: Issue) -> Bool { a.start < b.end && b.start < a.end }

    private static func sorted(_ items: [Ranked]) -> [Ranked] {
        items.sorted { l, r in
            if l.issue.start != r.issue.start { return l.issue.start < r.issue.start }
            let ll = l.issue.end - l.issue.start, rl = r.issue.end - r.issue.start
            if ll != rl { return ll > rl }
            if l.priority != r.priority { return l.priority > r.priority }
            return l.order < r.order
        }
    }

    private static func pickNonOverlapping(_ candidates: [Ranked]) -> [Ranked] {
        var selected: [Ranked] = []
        for c in sorted(candidates) {
            guard let conflictIndex = selected.firstIndex(where: { overlaps($0.issue, c.issue) }) else {
                selected.append(c); continue
            }
            let conflict = selected[conflictIndex]
            if conflict.issue.start == c.issue.start, conflict.issue.end == c.issue.end, c.priority > conflict.priority {
                selected[conflictIndex] = c
            }
        }
        return sorted(selected)
    }

    // MARK: UTF-16 辅助

    private static func isLowSurrogate(_ u: UInt16) -> Bool { u >= 0xDC00 && u <= 0xDFFF }

    private static func scalarChunks(_ s: [UInt16]) -> [[UInt16]] {
        var out: [[UInt16]] = []
        var i = 0
        while i < s.count {
            let n = DictTrie.scalar(s, i).1
            out.append(Array(s[i..<(i + n)]))
            i += n
        }
        return out
    }

    private static func isCovered(_ text: [UInt16], start: Int, end: Int, by terms: [[UInt16]]) -> Bool {
        for term in terms {
            for index in occurrences(of: term, in: text) where index <= start && end <= index + term.count {
                return true
            }
        }
        return false
    }
}

/// `term` 在 `text` 中所有（可重叠起点之后不重叠推进的）出现位置，与 JS 的 indexOf 循环一致。
func occurrences(of term: [UInt16], in text: [UInt16]) -> [Int] {
    guard !term.isEmpty, term.count <= text.count else { return [] }
    var result: [Int] = []
    var i = 0
    let last = text.count - term.count
    while i <= last {
        if text[i] == term[0], text[i..<(i + term.count)].elementsEqual(term) {
            result.append(i)
            i += term.count
        } else {
            i += 1
        }
    }
    return result
}
