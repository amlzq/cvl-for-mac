import Foundation
import CVLCore

/// 界面文案：英文、简体中文为手写，台湾、香港繁体由 CVLCore 从简体转换得到
/// （字形 + 地区用词，与检测使用同一套 OpenCC 词典）。
enum L10n {
    nonisolated(unsafe) static var language: InterfaceLanguage = .system
    private nonisolated(unsafe) static var derived: [String: String] = [:]
    private static let lock = NSLock()

    private enum Resolved { case en, zhHans, zhTW, zhHK }

    private static var resolved: Resolved {
        switch language {
        case .en: return .en
        case .zhHans: return .zhHans
        case .zhHant: return .zhTW
        case .zhHK: return .zhHK
        case .system:
            let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if !first.hasPrefix("zh") { return .en }
            if first.contains("hk") || first.contains("mo") { return .zhHK }
            if first.contains("tw") || first.contains("hant") { return .zhTW }
            return .zhHans
        }
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        guard let entry = table[key] else { return key }
        let text: String
        switch resolved {
        case .en: text = entry.en
        case .zhHans: text = entry.zh
        case .zhTW: text = derive(entry.zh, .zhTW)
        case .zhHK: text = derive(entry.zh, .zhHK)
        }
        return args.isEmpty ? text : String(format: text, arguments: args)
    }

    private static func derive(_ zh: String, _ variant: VariantCode) -> String {
        let cacheKey = "\(variant.rawValue)|\(zh)"
        lock.lock(); defer { lock.unlock() }
        if let hit = derived[cacheKey] { return hit }
        let settings = Settings(targetVariant: variant, detectionLevel: .standard)
        let issues = Detector().detect(text: zh, settings: settings)
        let out = TextEdit.applyingAll(issues, to: zh)
        derived[cacheKey] = out
        return out
    }

    static let table: [String: (en: String, zh: String)] = [
        "app.name": ("Chinese Variants Linter", "中文变体检查器"),
        "menu.enabled": ("Enabled", "启用检查"),
        "menu.target": ("Target region", "目标地区"),
        "menu.level": ("Detection level", "检测强度"),
        "menu.thisApp": ("Enable in %@", "在“%@”中启用"),
        "menu.settings": ("Settings…", "设置…"),
        "menu.permissions": ("Permissions…", "权限引导…"),
        "menu.quit": ("Quit", "退出"),
        "menu.checkSelection": ("Check selection", "检查选中文本"),
        "menu.convertSelection": ("Convert selection", "转换选中文本"),
        "menu.noPermission": ("Accessibility permission required", "需要辅助功能权限"),
        "variant.zh-CN": ("Simplified Chinese", "简体中文"),
        "variant.zh-TW": ("Chinese (Taiwan)", "中文（台湾）"),
        "variant.zh-HK": ("Chinese (Hong Kong)", "中文（香港）"),
        "variant.zh-Hant": ("Traditional Chinese", "繁体中文"),
        "level.standard": ("Standard (glyphs + regional terms)", "标准（字形 + 地区用词）"),
        "level.relaxed": ("Relaxed (glyphs only)", "宽松（仅字形）"),
        "lang.system": ("Follow system", "跟随系统"),
        "lang.en": ("English", "English"),
        "lang.zh-Hans": ("简体中文", "简体中文"),
        "lang.zh-Hant-TW": ("中文（台灣）", "中文（台灣）"),
        "lang.zh-Hant-HK": ("中文（香港）", "中文（香港）"),
        "tab.general": ("General", "通用"),
        "tab.apps": ("Apps", "应用"),
        "tab.dictionary": ("Dictionary", "词库"),
        "tab.shortcuts": ("Shortcuts", "快捷键"),
        "tab.about": ("Privacy & Terms", "隐私与条款"),
        "general.language": ("Interface language", "界面语言"),
        "general.launchAtLogin": ("Launch at login", "登录时自动启动"),
        "general.password": ("Password fields are never read or checked.", "密码框不会被读取或检查。"),
        "apps.hint": ("Turn off checking in specific apps.", "在指定应用中关闭检查。"),
        "apps.add": ("Add App…", "添加应用…"),
        "apps.remove": ("Remove", "移除"),
        "apps.empty": ("No disabled apps", "没有被禁用的应用"),
        "dict.allow": ("Allowed words", "允许词"),
        "dict.allowHint": ("Matches are never flagged. Kept separately for each target region.", "命中后不再提示。按目标地区分开保存。"),
        "dict.phrases": ("Custom phrases", "自定义词组"),
        "dict.from": ("From", "原词"),
        "dict.to": ("To", "替换为"),
        "dict.add": ("Add", "添加"),
        "dict.import": ("Import…", "导入…"),
        "dict.export": ("Export…", "导出…"),
        "dict.template": ("Template…", "模板…"),
        "dict.clear": ("Clear", "清空"),
        "dict.forRegion": ("For: %@", "适用地区：%@"),
        "dict.importDone": ("Imported: %d added, %d updated, %d skipped (limit %d).", "导入完成：新增 %d，更新 %d，跳过 %d（上限 %d）。"),
        "dict.importEmpty": ("No usable rows in this file.", "文件里没有可导入的词条。"),
        "dict.importTooLarge": ("File is larger than %d KB.", "文件超过 %d KB。"),
        "dict.importFailed": ("Could not read the file.", "无法读取该文件。"),
        "shortcut.checkSelection": ("Check selected text", "检查选中文本"),
        "shortcut.convertSelection": ("Convert selected text", "转换选中文本并写回"),
        "shortcut.toggleEnabled": ("Toggle checking", "开关检查"),
        "shortcut.acceptSuggestion": ("Accept the current suggestion", "接受当前建议"),
        "shortcut.ignoreSuggestion": ("Ignore the current suggestion once", "忽略当前建议（本次）"),
        "shortcut.record": ("Press keys…", "按下快捷键…"),
        "shortcut.reset": ("Reset", "恢复默认"),
        "shortcut.popupHint": ("While a suggestion is shown: Tab or 1 replace · 2 ignore once · 3 add to allowed words · Esc dismiss.", "建议浮窗显示时：Tab 或 1 替换 · 2 忽略一次 · 3 加入允许词 · Esc 关闭。"),
        "popup.replace": ("Replace with “%@”", "替换为“%@”"),
        "popup.ignore": ("Ignore once", "忽略一次"),
        "popup.allow": ("Always allow", "加入允许词"),
        "issue.script": ("%@ glyph: “%@” → “%@”", "%@字形：“%@” → “%@”"),
        "issue.term": ("%@ wording: “%@” → “%@”", "%@用词：“%@” → “%@”"),
        "issue.medium": ("May depend on context", "可能依赖上下文"),
        "badge.title": ("%d issue(s)", "%d 处问题"),
        "result.title": ("Check result", "检查结果"),
        "result.none": ("No issues found.", "没有发现问题。"),
        "result.replaceAll": ("Replace all", "全部替换"),
        "result.close": ("Close", "关闭"),
        "result.copyFailed": ("Could not read the selection. Select some text and try again.", "没有读到选中文本。请先选中文字再试。"),
        "result.pasteFailed": ("Could not write back.", "写回失败。"),
        "onb.title": ("Welcome", "欢迎使用"),
        "onb.body": ("This app checks Chinese text you type in other apps. It needs permission to read the focused text field and to place a suggestion next to it. Text is processed on this Mac only and never uploaded.", "本应用检查你在其他应用中输入的中文。它需要读取焦点输入框的权限，并在旁边显示建议。文本只在本机处理，不会上传。"),
        "onb.ax": ("Accessibility (required)", "辅助功能（必需）"),
        "onb.input": ("Input Monitoring (for shortcuts and suggestion keys)", "输入监控（快捷键和建议按键需要）"),
        "onb.granted": ("Granted", "已授权"),
        "onb.open": ("Open System Settings", "打开系统设置"),
        "onb.restartHint": ("If a permission doesn’t take effect, quit and reopen the app.", "授权后如未生效，请退出并重新打开本应用。"),
        "onb.done": ("Done", "完成"),
        "legal.privacy": ("Privacy Policy", "隐私政策"),
        "legal.terms": ("Terms of Service", "服务条款"),
    ]
}

extension VariantCode {
    var displayName: String { L10n.t("variant.\(rawValue)") }
}
extension DetectionLevel {
    var displayName: String { L10n.t("level.\(rawValue)") }
}
extension InterfaceLanguage {
    var displayName: String { L10n.t("lang.\(rawValue)") }
}
