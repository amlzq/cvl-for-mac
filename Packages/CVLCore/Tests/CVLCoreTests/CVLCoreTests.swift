import Foundation
import Testing
@testable import CVLCore

private struct Vector: Decodable {
    struct Expected: Decodable {
        let id, type, subtype, sourceText, confidence, ruleId: String
        let start, end: Int
        let suggestion: String?
    }
    struct Dict: Decodable {
        let allowPhrases: [String: [String]]?
        let phrases: [String: [P]]?
        struct P: Decodable { let id, from, to: String; let enabled: Bool }
    }
    struct S: Decodable {
        let defaultVariant: String
        let detectionLevel: String
        let userDictionary: Dict?
    }
    let name, text: String
    let settings: S
    let expected: [Expected]
}

private func loadVectors() throws -> [Vector] {
    // Packages/CVLCore/Tests/CVLCoreTests/CVLCoreTests.swift → 仓库根目录
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode([Vector].self, from: Data(contentsOf: root.appendingPathComponent("Shared/test-vectors.json")))
}

private func settings(for v: Vector.S) -> Settings {
    var s = Settings(targetVariant: VariantCode(rawValue: v.defaultVariant)!,
                     detectionLevel: DetectionLevel(rawValue: v.detectionLevel)!)
    for (k, list) in v.userDictionary?.allowPhrases ?? [:] {
        s.userDictionary.allowPhrases[VariantCode(rawValue: k)!] = list
    }
    for (k, list) in v.userDictionary?.phrases ?? [:] {
        s.userDictionary.phrases[VariantCode(rawValue: k)!] = list.map {
            CustomPhrase(id: $0.id, from: $0.from, to: $0.to, enabled: $0.enabled)
        }
    }
    return s
}

@Test func sharedVectorsMatchExtension() throws {
    let vectors = try loadVectors()
    #expect(vectors.count > 300)
    let detector = Detector()
    var failures: [String] = []
    for v in vectors {
        let got = detector.detect(text: v.text, settings: settings(for: v.settings))
        let actual = got.map { "\($0.id)|\($0.type.rawValue)|\($0.subtype)|\($0.start)-\($0.end)|\($0.confidence.rawValue)|\($0.suggestion)" }
        let want = v.expected.map { "\($0.id)|\($0.type)|\($0.subtype)|\($0.start)-\($0.end)|\($0.confidence)|\($0.suggestion ?? "")" }
        if actual != want { failures.append("\(v.name)\n  期望 \(want)\n  实际 \(actual)") }
    }
    #expect(failures.isEmpty, Comment(rawValue: "\(failures.count) 条不一致：\n" + failures.prefix(8).joined(separator: "\n")))
}

@Test func csvRoundTripAndFormulaGuard() {
    let rows = [(from: "软件", to: "軟體"), (from: "=cmd", to: "a,\"b\"")]
    let text = PhraseFile.serializeCSV(rows)
    let back = PhraseFile.parse(text)
    #expect(back.map(\.from) == ["软件", "=cmd"])
    #expect(back.map(\.to) == ["軟體", "a,\"b\""])
}

@Test func tabDictionaryAndComments() {
    let rows = PhraseFile.parse("# 注释\n软件\t軟體 軟件\n视频\t影片\n软件\t軟件\n")
    #expect(rows.map(\.from) == ["软件", "视频"])
    #expect(rows.map(\.to) == ["軟件", "影片"])
}

@Test func gbkDecoding() {
    let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    let data = "from,to\n软件,軟體\n".data(using: String.Encoding(rawValue: gb))!
    #expect(PhraseFile.decode(data)?.contains("软件") == true)
}

@Test func replaceAndConvert() {
    var s = Settings(targetVariant: .zhTW)
    s.detectionLevel = .standard
    let text = "这个软件很好"
    let issues = Detector().detect(text: text, settings: s)
    #expect(TextEdit.applyingAll(issues, to: text) == "這個軟體很好")
    #expect(TextEdit.replacing(text, range: 2..<4, with: "軟體") == "这个軟體很好")
}

@Test func allowAndSettingsLimits() {
    var s = Settings(targetVariant: .zhTW)
    let first = s.addAllowPhrase("软件")
    let second = s.addAllowPhrase("软件")
    #expect(first)
    #expect(!second)
    let issues = Detector().detect(text: "软件", settings: s)
    #expect(issues.isEmpty)
    #expect(s.isAppEnabled("com.apple.TextEdit"))
    s.disabledApps = ["com.apple.TextEdit"]
    #expect(!s.isAppEnabled("com.apple.TextEdit"))
}
