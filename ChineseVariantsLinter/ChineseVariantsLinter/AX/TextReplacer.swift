import AppKit
import CVLCore

/// 剪贴板快照：保存和恢复全部内容，替换期间不丢用户剪贴板。
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    static func save(_ pb: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(_ pb: NSPasteboard = .general) {
        pb.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }

    /// 写入临时文本，并标记为临时内容，剪贴板管理器不会记录。
    static func setTransient(_ text: String, _ pb: NSPasteboard = .general) {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pb.writeObjects([item])
    }
}

enum TextReplacer {
    /// 选中目标范围后模拟粘贴替换，保留撤销栈；结束后恢复原剪贴板。
    /// 不直接写 AXValue（会破坏撤销栈和光标位置）。
    static func replace(element: AXElement, range: Range<Int>, with replacement: String) async -> Bool {
        let target = CFRange(location: range.lowerBound, length: range.count)
        guard element.setSelectedRange(target) else { return false }
        guard let now = element.range(kAXSelectedTextRangeAttribute),
              now.location == target.location, now.length == target.length else { return false }
        await Synth.waitForModifiersReleased()
        return await paste(replacement)
    }

    /// 把文本通过剪贴板粘贴到当前焦点（调用前选区已设置好）。
    static func paste(_ text: String) async -> Bool {
        let snapshot = PasteboardSnapshot.save()
        PasteboardSnapshot.setTransient(text)
        Synth.paste()
        try? await Task.sleep(nanoseconds: 250_000_000)
        snapshot.restore()
        return true
    }

    /// 模拟复制读取选中文本，随后恢复剪贴板。
    static func copySelection() async -> String? {
        await Synth.waitForModifiersReleased()
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.save()
        pb.clearContents()
        let before = pb.changeCount
        Synth.copy()
        var text: String?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { text = pb.string(forType: .string); break }
        }
        snapshot.restore()
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
