import Foundation

/// OpenCC 字典树，行为与 opencc-js 的 `Trie` 一致：最长匹配，未匹配的字符原样保留，
/// 表意文字描述序列（IDS）整体跳过。
final class DictTrie: @unchecked Sendable {
    private final class Node {
        var children: [UInt32: Node] = [:]
        var value: [UInt16]?
    }

    private let root = Node()

    func add(_ source: String, _ target: String) {
        var node = root
        for scalar in source.unicodeScalars {
            if let next = node.children[scalar.value] {
                node = next
            } else {
                let next = Node()
                node.children[scalar.value] = next
                node = next
            }
        }
        node.value = Array(target.utf16)
    }

    /// 从 `index` 起的最长匹配，返回结束下标与替换值。
    private func matchPrefix(_ s: [UInt16], _ index: Int) -> (end: Int, value: [UInt16])? {
        var node = root
        var best: (Int, [UInt16])?
        var j = index
        while j < s.count {
            let (cp, len) = Self.scalar(s, j)
            j += len
            guard let next = node.children[cp] else { break }
            node = next
            if let v = node.value { best = (j, v) }
        }
        return best
    }

    func convert(_ s: [UInt16]) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if let m = matchPrefix(s, i) {
                out.append(contentsOf: m.value)
                i = m.end
            } else {
                let n = Self.unmatchedLength(s, i)
                out.append(contentsOf: s[i..<(i + n)])
                i += n
            }
        }
        return out
    }

    // MARK: UTF-16 辅助

    static func scalar(_ s: [UInt16], _ i: Int) -> (UInt32, Int) {
        let hi = s[i]
        if hi >= 0xD800, hi <= 0xDBFF, i + 1 < s.count {
            let lo = s[i + 1]
            if lo >= 0xDC00, lo <= 0xDFFF {
                return (0x10000 + ((UInt32(hi) - 0xD800) << 10) + (UInt32(lo) - 0xDC00), 2)
            }
        }
        return (UInt32(hi), 1)
    }

    private static func idsArity(_ cp: UInt32) -> Int {
        if cp >= 0x2FF0 && cp <= 0x2FF1 { return 2 }
        if cp >= 0x2FF2 && cp <= 0x2FF3 { return 3 }
        if cp >= 0x2FF4 && cp <= 0x2FFF { return 2 }
        return 0
    }

    private static func idsEnd(_ s: [UInt16], _ i: Int) -> Int {
        let (cp, len) = scalar(s, i)
        let arity = idsArity(cp)
        if arity == 0 { return 0 }
        var end = i + len
        for _ in 0..<arity {
            if end >= s.count { return 0 }
            let child = idsEnd(s, end)
            end = child != 0 ? child : end + scalar(s, end).1
        }
        return end
    }

    private static func unmatchedLength(_ s: [UInt16], _ i: Int) -> Int {
        let end = idsEnd(s, i)
        return end > i ? end - i : scalar(s, i).1
    }
}

/// 一组 OpenCC 字典（词组 + 单字）。单字先加载、词组后加载，词组优先。
struct DictGroup: Sendable {
    let phrases: [(String, String)]
    let chars: [(String, String)]
}

final class OpenCCStage: @unchecked Sendable {
    let trie: DictTrie
    init(group: DictGroup) {
        trie = DictTrie()
        for (a, b) in group.chars { trie.add(a, b) }
        for (a, b) in group.phrases { trie.add(a, b) }
    }
}

/// 字形转换：把任意变体文本转换为目标地区的字形。
///
/// 管线与扩展版一致：先把台湾、香港异体归一后转为简体，再由简体转到目标。
/// 这样繁体输入中合法的简繁同形字（「干擾」「里長」）不会被误转。
public final class ScriptConverter: @unchecked Sendable {
    public static let shared = ScriptConverter()

    private let lock = NSLock()
    private var groups: [String: DictGroup] = [:]
    private var stages: [String: OpenCCStage] = [:]
    private var ambiguousCache: [String: Set<UInt32>] = [:]

    private init() {}

    private func group(_ name: String) -> DictGroup {
        if let g = groups[name] { return g }
        let g = DictGroup(
            phrases: Self.loadDict("opencc/\(name).phrases"),
            chars: Self.loadDict("opencc/\(name).chars"))
        groups[name] = g
        return g
    }

    private func stage(_ name: String) -> OpenCCStage {
        if let s = stages[name] { return s }
        let s = OpenCCStage(group: group(name))
        stages[name] = s
        return s
    }

    static func loadDict(_ resource: String) -> [(String, String)] {
        guard let url = Bundle.module.url(forResource: "Resources/\(resource)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("缺少 OpenCC 词典资源：\(resource)")
            return []
        }
        var out: [(String, String)] = []
        text.enumerateLines { line, _ in
            guard let tab = line.firstIndex(of: "\t") else { return }
            out.append((String(line[..<tab]), String(line[line.index(after: tab)...])))
        }
        return out
    }

    private static func chain(for variant: VariantCode) -> [String] {
        let toSimplified = ["from_tw", "from_hk", "to_cn"]
        switch variant {
        case .zhCN: return toSimplified
        case .zhTW: return toSimplified + ["from_cn", "to_tw"]
        case .zhHK: return toSimplified + ["from_cn", "to_hk"]
        case .zhHant: return toSimplified + ["from_cn"]
        }
    }

    /// 转换到目标变体的字形（UTF-16 数组形式，供检测定位使用）。
    func convert(_ text: [UInt16], to variant: VariantCode) -> [UInt16] {
        lock.lock(); defer { lock.unlock() }
        return Self.chain(for: variant).reduce(text) { stage($1).trie.convert($0) }
    }

    public func convert(_ text: String, to variant: VariantCode) -> String {
        String(decoding: convert(Array(text.utf16), to: variant), as: UTF16.self)
    }

    func toSimplified(_ text: [UInt16]) -> [UInt16] { convert(text, to: .zhCN) }

    /// 从词组字典推导「一对多」字：某字在词组里的转换结果与单字默认结果不同，说明依赖上下文。
    private func ambiguousChars(_ name: String) -> Set<UInt32> {
        if let cached = ambiguousCache[name] { return cached }
        let g = group(name)
        var charMap: [UInt32: String] = [:]
        for (a, b) in g.chars {
            let key = a.unicodeScalars.map(\.value)
            if key.count == 1 { charMap[key[0]] = b }
        }
        var result = Set<UInt32>()
        for (a, b) in g.phrases {
            let src = a.unicodeScalars.map { $0 }, dst = b.unicodeScalars.map { $0 }
            guard src.count == dst.count else { continue }
            for (i, ch) in src.enumerated() {
                let def = charMap[ch.value] ?? String(ch)
                if String(dst[i]) != def { result.insert(ch.value) }
            }
        }
        ambiguousCache[name] = result
        return result
    }

    /// 判断一段字形转换是否依赖上下文（决定置信度）。
    func isContextSensitive(_ source: [UInt16], variant: VariantCode) -> Bool {
        lock.lock(); defer { lock.unlock() }
        func scalarValues(_ s: [UInt16]) -> [UInt32] {
            var out: [UInt32] = []; var i = 0
            while i < s.count { let (cp, n) = DictTrie.scalar(s, i); out.append(cp); i += n }
            return out
        }
        if variant == .zhCN {
            let amb = ambiguousChars("to_cn")
            return scalarValues(source).contains(where: amb.contains)
        }
        let simplified = Self.chain(for: .zhCN).reduce(source) { stage($1).trie.convert($0) }
        let amb = ambiguousChars("from_cn")
        return scalarValues(simplified).contains(where: amb.contains)
    }
}
