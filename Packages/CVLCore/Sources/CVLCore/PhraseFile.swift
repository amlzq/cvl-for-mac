import Foundation

/// 自定义词组的导入导出：CSV（两列 `from,to`，首行可选表头）与 OpenCC 词条格式（`原词<Tab>目标词`）。
public enum PhraseFile {
    public static let csvHeader = ["from", "to"]

    // MARK: CSV

    private static func parseRows(_ input: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(input.unicodeScalars.drop(while: { $0.value == 0xFEFF }))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.unicodeScalars.append("\""); i += 1 }
                    else { quoted = false }
                } else { field.unicodeScalars.append(ch) }
            } else if ch == "\"" {
                quoted = true
            } else if ch == "," {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" {
                if ch == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.unicodeScalars.append(ch) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private static let formulaChars: Set<Character> = ["=", "+", "-", "@"]

    /// CSV 公式注入防护：以 = + - @ 开头的单元格前置单引号，导入时去掉，保证往返一致。
    private static func guardFormula(_ v: String) -> String {
        if let f = v.first, formulaChars.contains(f) { return "'" + v }
        return v
    }

    private static func unguardFormula(_ v: String) -> String {
        if v.hasPrefix("'"), let second = v.dropFirst().first, formulaChars.contains(second) { return String(v.dropFirst()) }
        return v
    }

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    public static func parseCSV(_ text: String) -> [(from: String, to: String)] {
        var out: [(String, String)] = []
        for (index, cells) in parseRows(text).enumerated() {
            let from = trim(cells.indices.contains(0) ? cells[0] : "")
            let to = trim(cells.indices.contains(1) ? cells[1] : "")
            if index == 0, from.lowercased() == "from", to.lowercased() == "to" { continue }
            if !from.isEmpty, !to.isEmpty { out.append((unguardFormula(from), unguardFormula(to))) }
        }
        return out
    }

    private static func escape(_ raw: String) -> String {
        let v = guardFormula(raw)
        if v.contains(where: { $0 == "\"" || $0 == "," || $0 == "\r" || $0 == "\n" || $0 == "\r\n" }) {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    public static func serializeCSV(_ phrases: [(from: String, to: String)]) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for p in phrases { lines.append("\(escape(p.from)),\(escape(p.to))") }
        // BOM 让 Excel 以 UTF-8 打开。
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: OpenCC 词条

    private static func dedupeKeepLast(_ rows: [(String, String)]) -> [(from: String, to: String)] {
        var order: [String] = [], map: [String: String] = [:]
        for (f, t) in rows {
            if map[f] == nil { order.append(f) }
            map[f] = t
        }
        return order.map { ($0, map[$0]!) }
    }

    private static func lines(_ text: String) -> [String] {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        return t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func isComment(_ line: String) -> Bool {
        line.drop(while: { $0.isWhitespace }).hasPrefix("#")
    }

    /// OpenCC 风格词条：每行 `原词<Tab>目标词`，`#` 开头为注释；多个候选只取第一个；原词重复以最后一条为准。
    public static func parseTabDictionary(_ text: String) -> [(from: String, to: String)] {
        var out: [(String, String)] = []
        for line in lines(text) {
            if trim(line).isEmpty || isComment(line) { continue }
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let from = trim(String(line[..<tab]))
            let rest = trim(String(line[line.index(after: tab)...]))
            let to = rest.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if !from.isEmpty, !to.isEmpty { out.append((from, to)) }
        }
        return dedupeKeepLast(out)
    }

    /// 导入入口：含制表符的非注释行视为 OpenCC 词条格式，否则按 CSV 解析。
    public static func parse(_ text: String) -> [(from: String, to: String)] {
        let all = lines(text)
        if all.contains(where: { !isComment($0) && $0.contains("\t") }) { return parseTabDictionary(text) }
        let body = all.filter { !isComment($0) }.joined(separator: "\n")
        return dedupeKeepLast(parseCSV(body))
    }

    /// 解码导入文件：先严格按 UTF-8，失败（Excel 默认保存的 GBK / ANSI）再按 GB18030。
    public static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb))
    }
}
