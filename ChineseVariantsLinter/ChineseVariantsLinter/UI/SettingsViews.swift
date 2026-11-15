import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CVLCore

struct SettingsRoot: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label(L10n.t("tab.general"), systemImage: "gearshape") }
            AppsTab().tabItem { Label(L10n.t("tab.apps"), systemImage: "app.badge") }
            DictionaryTab().tabItem { Label(L10n.t("tab.dictionary"), systemImage: "character.book.closed") }
            ShortcutsTab().tabItem { Label(L10n.t("tab.shortcuts"), systemImage: "keyboard") }
            LegalTab().tabItem { Label(L10n.t("tab.about"), systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 460)
        .id(store.settings.language)   // 切换语言后整体刷新
    }
}

struct GeneralTab: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        Form {
            Toggle(L10n.t("menu.enabled"), isOn: $store.settings.enabled)
            Picker(L10n.t("menu.target"), selection: $store.settings.targetVariant) {
                ForEach(VariantCode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker(L10n.t("menu.level"), selection: $store.settings.detectionLevel) {
                ForEach(DetectionLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker(L10n.t("general.language"), selection: $store.settings.language) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(L10n.t("general.launchAtLogin"), isOn: $store.settings.launchAtLogin)
            Text(L10n.t("general.password")).font(.footnote).foregroundStyle(.secondary)
        }.padding(20)
    }
}

struct AppsTab: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(L10n.t("apps.hint")).foregroundStyle(.secondary)
            List(selection: $selection) {
                if store.settings.disabledApps.isEmpty {
                    Text(L10n.t("apps.empty")).foregroundStyle(.secondary)
                }
                ForEach(store.settings.disabledApps, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            Text(FileManager.default.displayName(atPath: url.path))
                        } else { Text(id) }
                        Spacer()
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }.tag(id)
                }
            }
            HStack {
                Button(L10n.t("apps.add")) { addApp() }
                Button(L10n.t("apps.remove")) {
                    if let s = selection { store.settings.disabledApps.removeAll { $0 == s }; selection = nil }
                }.disabled(selection == nil)
            }
        }.padding(20)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !store.settings.disabledApps.contains(id) { store.settings.disabledApps.append(id) }
    }
}

struct DictionaryTab: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var newAllow = ""
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var message: String?

    private var variant: VariantCode { store.settings.targetVariant }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("dict.forRegion", variant.displayName)).font(.headline)

            GroupBox(L10n.t("dict.allow")) {
                VStack(alignment: .leading) {
                    Text(L10n.t("dict.allowHint")).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        TextField("", text: $newAllow).onSubmit(addAllow)
                        Button(L10n.t("dict.add"), action: addAllow)
                    }
                    List {
                        ForEach(store.settings.userDictionary.allow(variant), id: \.self) { term in
                            HStack {
                                Text(term); Spacer()
                                Button { store.settings.removeAllowPhrase(term) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }.frame(height: 80)
                }.padding(4)
            }

            GroupBox(L10n.t("dict.phrases")) {
                VStack(alignment: .leading) {
                    HStack {
                        TextField(L10n.t("dict.from"), text: $newFrom)
                        Image(systemName: "arrow.right")
                        TextField(L10n.t("dict.to"), text: $newTo).onSubmit(addPhrase)
                        Button(L10n.t("dict.add"), action: addPhrase)
                    }
                    List {
                        ForEach(store.settings.userDictionary.custom(variant)) { p in
                            HStack {
                                Toggle("", isOn: Binding(get: { p.enabled },
                                    set: { store.settings.setPhraseEnabled(variant: variant, id: p.id, enabled: $0) })).labelsHidden()
                                Text(p.from); Image(systemName: "arrow.right").foregroundStyle(.secondary); Text(p.to)
                                Spacer()
                                Button { store.settings.removePhrase(variant: variant, id: p.id) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }.frame(height: 110)
                    HStack {
                        Button(L10n.t("dict.import"), action: importFile)
                        Button(L10n.t("dict.export"), action: exportFile)
                        Button(L10n.t("dict.template"), action: exportTemplate)
                        Button(L10n.t("dict.clear")) { store.settings.userDictionary.phrases[variant] = [] }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }.padding(4)
            }
        }.padding(16)
    }

    private func addAllow() { store.settings.addAllowPhrase(newAllow); newAllow = "" }
    private func addPhrase() {
        if store.settings.addPhrase(variant: variant, from: newFrom, to: newTo) { newFrom = ""; newTo = "" }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .tabSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { message = L10n.t("dict.importFailed"); return }
        if data.count > maxImportFileBytes { message = L10n.t("dict.importTooLarge", maxImportFileBytes / 1024); return }
        guard let text = PhraseFile.decode(data) else { message = L10n.t("dict.importFailed"); return }
        let rows = PhraseFile.parse(text)
        if rows.isEmpty { message = L10n.t("dict.importEmpty"); return }
        let r = store.settings.importPhrases(variant: variant, rows: rows)
        message = L10n.t("dict.importDone", r.added, r.updated, r.skipped, maxPhrasesPerVariant)
    }

    private func save(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportFile() {
        let rows = store.settings.userDictionary.custom(variant).map { (from: $0.from, to: $0.to) }
        save(PhraseFile.serializeCSV(rows), name: "cvl-\(variant.rawValue).csv")
    }

    private func exportTemplate() {
        save(PhraseFile.serializeCSV([("软件", "軟體"), ("视频", "影片")]), name: "cvl-template.csv")
    }
}

// MARK: - 快捷键

struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject var store = SettingsStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(L10n.t("shortcut.\(action.rawValue)"))
            Spacer()
            Button(recording ? L10n.t("shortcut.record") : (store.settings.shortcuts[action]?.display ?? "—")) { toggle() }
                .frame(minWidth: 110)
            Button(L10n.t("shortcut.reset")) {
                store.settings.shortcuts[action] = Settings.defaultShortcuts[action]
            }
        }
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue) & ShortcutModifiers.mask
            if event.keyCode == 53 { stop(); return nil }                  // Esc 取消
            guard mods != 0 else { return nil }                            // 必须带修饰键
            let cg = Self.cgFlags(event.modifierFlags)
            store.settings.shortcuts[action] = ShortcutCombo(
                keyCode: event.keyCode, modifiers: cg,
                display: Self.symbols(event.modifierFlags) + (event.charactersIgnoringModifiers ?? "").uppercased())
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func cgFlags(_ f: NSEvent.ModifierFlags) -> UInt64 {
        var v: UInt64 = 0
        if f.contains(.shift) { v |= ShortcutModifiers.shift }
        if f.contains(.control) { v |= ShortcutModifiers.control }
        if f.contains(.option) { v |= ShortcutModifiers.option }
        if f.contains(.command) { v |= ShortcutModifiers.command }
        return v
    }

    private static func symbols(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }
}

struct ShortcutsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(
                [ShortcutAction.checkSelection, .convertSelection, .toggleEnabled,
                 .acceptSuggestion, .ignoreSuggestion],
                id: \.self
            ) {
                ShortcutRecorder(action: $0)
            }
            Divider()
            Text(L10n.t("shortcut.popupHint")).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(20)
    }
}

// MARK: - 法律文本

struct LegalTab: View {
    @State private var showTerms = false

    private static func load(_ name: String) -> String {
        let isChinese: Bool = {
            switch SettingsStore.shared.settings.language {
            case .en: return false
            case .system: return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
            default: return true
            }
        }()
        // 繁体界面优先 zh-Hant，缺失时回退 zh-Hans，再回退 en，避免出现空白页。
        for lang in (isChinese ? ["zh-Hant", "zh-Hans", "en"] : ["en"]) {
            if let url = Bundle.main.url(forResource: "\(name).\(lang)", withExtension: "md"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("", selection: $showTerms) {
                Text(L10n.t("legal.privacy")).tag(false)
                Text(L10n.t("legal.terms")).tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                Text(LocalizedStringKey(Self.load(showTerms ? "terms" : "privacy")))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.padding(20)
    }
}
