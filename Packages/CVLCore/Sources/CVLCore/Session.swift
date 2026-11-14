import Foundation

/// 会话状态：忽略一次、替换后复查。不落盘。
public final class CheckSession: @unchecked Sendable {
    private let lock = NSLock()
    private var ignored = Set<String>()
    private let detector = Detector()

    public init() {}

    public func ignoreOnce(_ issue: Issue) {
        lock.lock(); ignored.insert(issue.id); lock.unlock()
    }

    public func reset() {
        lock.lock(); ignored.removeAll(); lock.unlock()
    }

    public func check(_ text: String, settings: Settings) -> [Issue] {
        lock.lock(); let ids = ignored; lock.unlock()
        return detector.detect(text: text, settings: settings, ignoredIssueIDs: ids)
    }
}

public enum TextEdit {
    /// 把 UTF-16 范围内的文本替换为 `replacement`。范围越界时返回 nil。
    public static func replacing(_ text: String, range: Range<Int>, with replacement: String) -> String? {
        let units = Array(text.utf16)
        guard range.lowerBound >= 0, range.upperBound <= units.count else { return nil }
        let out = Array(units[..<range.lowerBound]) + Array(replacement.utf16) + Array(units[range.upperBound...])
        return String(decoding: out, as: UTF16.self)
    }

    /// 应用全部建议（从后往前，下标不受影响），用于「转换选中文本」。
    public static func applyingAll(_ issues: [Issue], to text: String) -> String {
        var units = Array(text.utf16)
        for issue in issues.sorted(by: { $0.start > $1.start }) where issue.end <= units.count {
            units.replaceSubrange(issue.start..<issue.end, with: Array(issue.suggestion.utf16))
        }
        return String(decoding: units, as: UTF16.self)
    }
}
