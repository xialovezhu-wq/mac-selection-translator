import AppKit
import Foundation

struct SpeechPreferences: Codable {
    var schemaVersion = 1
    var englishAccent = "en-US"
    var voiceByLanguage: [String: String] = [:]
    var rate: Float = 0.5
    var slowRate: Float = 0.43
    var userConfirmed = false

    init() {}
    private enum CodingKeys: String, CodingKey { case schemaVersion, englishAccent, voiceByLanguage, rate, slowRate, userConfirmed }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        englishAccent = try values.decodeIfPresent(String.self, forKey: .englishAccent) ?? "en-US"
        if let dictionary = try? values.decode([String: String].self, forKey: .voiceByLanguage) {
            voiceByLanguage = dictionary
        } else if let array = try? values.decode([String].self, forKey: .voiceByLanguage), array.isEmpty {
            // Hammerspoon serializes an empty Lua table as an empty JSON array.
            voiceByLanguage = [:]
        } else if !values.contains(.voiceByLanguage) { voiceByLanguage = [:] }
        else { throw DecodingError.dataCorruptedError(forKey: .voiceByLanguage, in: values, debugDescription: "Expected a voice mapping") }
        rate = try values.decodeIfPresent(Float.self, forKey: .rate) ?? 0.5
        slowRate = try values.decodeIfPresent(Float.self, forKey: .slowRate) ?? 0.43
        userConfirmed = try values.decodeIfPresent(Bool.self, forKey: .userConfirmed) ?? false
    }
}


@MainActor
private final class SpeechSettingsContentView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

@MainActor
final class SpeechSettings: NSObject, NSWindowDelegate {
    private let path: URL
    private let screen: NSScreen
    private var preferences: SpeechPreferences
    private var voices: [SpeechVoice] = []
    private var choices: [String?] = []
    private var draftAccent: String
    private var window: NSPanel!
    private let accent = NSPopUpButton()
    private let voice = NSPopUpButton()
    private let rate = NSSlider(value: 0.5, minValue: 0.35, maxValue: 0.65, target: nil, action: nil)
    private let rateLabel = NSTextField(labelWithString: "正常语速")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?

    init(path: URL, screen: NSScreen) {
        self.path = path
        self.screen = screen
        if let data = try? Data(contentsOf: path),
           let saved = try? JSONDecoder().decode(SpeechPreferences.self, from: data),
           ["en-US", "en-GB"].contains(saved.englishAccent), (0.35...0.65).contains(saved.rate) {
            preferences = saved
        } else { preferences = SpeechPreferences() }
        draftAccent = preferences.englishAccent
        super.init()
    }

    private func label(_ text: String, size: CGFloat = 14) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    func show(snapshot: URL? = nil) {
        let visible = screen.visibleFrame
        let width = min(620, visible.width - 48)
        let height = min(720, visible.height - 96)
        let frame = NSRect(x: visible.minX + 24, y: visible.maxY - height - 24, width: width, height: height)
        // Position before displaying; no activation or main-screen fallback.
        window = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .nonactivatingPanel],
                         backing: .buffered, defer: false, screen: screen)
        window.title = "划词朗读设置"
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        let root = SpeechSettingsContentView(frame: NSRect(x: 0, y: 0, width: width, height: 720))
        scroll.documentView = root
        window.contentView = scroll
        func place(_ view: NSView, x: CGFloat = 24, y: CGFloat, w: CGFloat? = nil, h: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: w ?? (width - 48), height: h)
            root.addSubview(view)
        }
        place(label("选择适合跟读的声音", size: 21), y: 24, h: 30)
        place(label("英音、美音都可用于雅思。按清晰度、语调和自己的听感选择。"), y: 66, h: 42)
        accent.addItems(withTitles: ["美音 · en-US", "英音 · en-GB"])
        accent.selectItem(at: draftAccent == "en-GB" ? 1 : 0)
        accent.target = self; accent.action = #selector(accentChanged)
        place(label("主要口音"), y: 128, w: 85, h: 25)
        place(accent, x: 121, y: 123, w: width - 150, h: 32)
        voice.target = self; voice.action = #selector(voiceChanged)
        place(label("具体声音"), y: 174, w: 85, h: 25)
        place(voice, x: 121, y: 169, w: width - 150, h: 32)
        rate.doubleValue = Double(preferences.rate)
        rate.numberOfTickMarks = 7
        rate.target = self; rate.action = #selector(rateChanged)
        place(label("朗读速度"), y: 220, w: 85, h: 25)
        place(rate, x: 121, y: 215, w: width - 150, h: 32)
        place(rateLabel, x: 121, y: 254, w: width - 150, h: 24)
        place(button("试听当前速度", #selector(previewNormal)), y: 297, w: 144, h: 32)
        place(button("适度慢读", #selector(previewSlow)), x: 178, y: 297, w: 120, h: 32)
        place(button("停止", #selector(stopAudio)), x: 308, y: 297, w: 86, h: 32)
        place(button("刷新声音", #selector(refresh)), x: 404, y: 297, w: 120, h: 32)
        place(button("保存为日常朗读设置", #selector(save)), y: 348, w: 260, h: 32)
        status.font = .systemFont(ofSize: 13)
        status.textColor = .secondaryLabelColor
        place(status, y: 397, h: 92)
        feedback.font = .systemFont(ofSize: 13)
        place(feedback, y: 493, h: 44)
        let hint = label("试听包含多音节词、children / went / responses 和两句自然短句。朗读始终保留选区原词形。read、record、live 等词请结合整句判断读法。", size: 12)
        hint.textColor = .secondaryLabelColor
        place(hint, y: 553, h: 62)
        let download = label("列表只显示已安装声音。增强音色可在系统设置 → 辅助功能中的朗读设置 → 系统声音管理中下载，完成后点“刷新声音”。保存的具体声音不会被自动质量排序替换。", size: 12)
        download.textColor = .secondaryLabelColor
        place(download, y: 625, h: 70)
        refresh(); rateChanged(); refreshStatus()
        window.contentView!.layoutSubtreeIfNeeded()
        // AppKit can constrain a newly created panel to a default screen. Set
        // its final global frame explicitly after layout and before display.
        var finalFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height))
        finalFrame.origin = NSPoint(x: visible.minX + 24, y: visible.maxY - finalFrame.height - 24)
        window.setFrame(finalFrame, display: false)
        let placement: [String: Any] = ["screenID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
            "visible": ["x": visible.minX, "y": visible.minY, "w": visible.width, "h": visible.height],
            "frame": ["x": window.frame.minX, "y": window.frame.minY, "w": window.frame.width, "h": window.frame.height],
            "contained": visible.contains(window.frame)]
        if let data = try? JSONSerialization.data(withJSONObject: placement) {
            try? data.write(to: path.deletingLastPathComponent().appendingPathComponent("speech-settings-window.json"), options: .atomic)
        }
        guard visible.contains(window.frame) else {
            feedback.stringValue = "窗口无法安全放入工作屏，未显示。"
            return
        }
        if let snapshot, let view = window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: snapshot) }
            return
        }
        window.orderFrontRegardless()
        let actual = window.frame
        let metadata: [String: Any] = [
            "screenID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
            "screenName": screen.localizedName,
            "frame": ["x": actual.minX, "y": actual.minY, "w": actual.width, "h": actual.height],
            "contained": visible.contains(actual), "nonactivating": true
        ]
        if !visible.contains(actual) { window.orderOut(nil) }
        if let data = try? JSONSerialization.data(withJSONObject: metadata) {
            try? data.write(to: path.deletingLastPathComponent().appendingPathComponent("speech-settings-window.json"), options: .atomic)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    private var selectedVoice: String? {
        let index = voice.indexOfSelectedItem
        return choices.indices.contains(index) ? choices[index] : nil
    }

    @objc private func accentChanged() {
        if let id = selectedVoice { preferences.voiceByLanguage[draftAccent] = id }
        else { preferences.voiceByLanguage.removeValue(forKey: draftAccent) }
        draftAccent = accent.indexOfSelectedItem == 1 ? "en-GB" : "en-US"
        populateVoices()
    }

    @objc private func voiceChanged() { feedback.stringValue = "选择尚未保存，可先试听。" }

    private func populateVoices() {
        voice.removeAllItems(); choices = [nil]
        voice.addItem(withTitle: "自动选择可用最佳音色")
        let saved = preferences.voiceByLanguage[draftAccent]
        var selected = 0
        for item in voices where item.language == draftAccent {
            voice.addItem(withTitle: item.name + " · " + item.qualityName + (item.recommended ? "" : " · 传统音色"))
            choices.append(item.identifier)
            if item.identifier == saved { selected = choices.count - 1 }
        }
        if let saved, !choices.contains(where: { $0 == saved }) {
            voice.addItem(withTitle: "已保存的声音当前不可用（将提示同口音回退）")
            choices.append(saved); selected = choices.count - 1
        }
        voice.selectItem(at: selected)
    }

    @objc private func refresh() { voices = speechCatalog(); populateVoices(); send(["action": "refresh"]) }
    @objc private func rateChanged() {
        let value = rate.doubleValue
        rateLabel.stringValue = abs(value - 0.5) < 0.015 ? "正常语速" : value < 0.5 ? "较慢（便于跟读）" : "稍快"
    }
    @objc private func previewNormal() { preview(rate: Float(rate.doubleValue)) }
    @objc private func previewSlow() { preview(rate: 0.43) }
    private func preview(rate: Float) {
        var command: [String: Any] = ["action": "preview", "language": draftAccent, "rate": rate]
        if let id = selectedVoice { command["voiceIdentifier"] = id }
        send(command)
        feedback.stringValue = "试听使用固定测试文本；你的日常设置尚未改变。"
    }
    @objc private func stopAudio() { send(["action": "stop"]) }

    @objc private func save() {
        preferences.englishAccent = draftAccent
        preferences.rate = Float(rate.doubleValue)
        preferences.userConfirmed = true
        if let id = selectedVoice { preferences.voiceByLanguage[draftAccent] = id }
        else { preferences.voiceByLanguage.removeValue(forKey: draftAccent) }
        do {
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            feedback.stringValue = "已保存。下一次划词朗读将使用新设置。"
        } catch { feedback.stringValue = "保存失败，请检查本地设置目录。" }
    }

    private func send(_ values: [String: Any]) {
        var command = values; command["id"] = UUID().uuidString
        guard let data = try? JSONSerialization.data(withJSONObject: command) else { return }
        try? data.write(to: path.deletingLastPathComponent().appendingPathComponent("speech-command.json"), options: .atomic)
    }

    private func refreshStatus() {
        let url = path.deletingLastPathComponent().appendingPathComponent("speech-status.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            status.stringValue = "尚无播放状态。请确认划词模块已启动。"; return
        }
        let phase = state["phase"] as? String ?? "stopped"
        let translated = ["waiting": "等待合成", "playing": "正在播放", "stopped": "已停止", "error": "播放失败"][phase] ?? phase
        var text = "状态：" + translated
        if let voice = state["actualVoice"] as? [String: Any] {
            text += "\n实际声音：\(voice["name"] ?? "") · \(voice["language"] ?? "") · \(voice["qualityName"] ?? "")"
        }
        if let warning = state["fallbackReason"] as? String, !warning.isEmpty { text += "\n" + warning }
        if let error = state["error"] as? String { text += "\n错误：" + error }
        if state["contextSensitive"] as? Bool == true { text += "\n当前孤立选词可能有多种读法，建议朗读完整句子。" }
        status.stringValue = text
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate(); NSApplication.shared.terminate(nil) }
}

@MainActor
func runSpeechSettings(arguments: [String]) -> Bool {
    func option(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    guard let path = option("--preferences"), path.hasPrefix("/"),
          let screenText = option("--screen-id"), let screenID = UInt32(screenText),
          let screen = NSScreen.screens.first(where: {
              ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID
          }), !screen.localizedName.lowercased().contains("ipad"),
          !screen.localizedName.lowercased().contains("opendisplay") else { return false }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let settings = SpeechSettings(path: URL(fileURLWithPath: path), screen: screen)
    let snapshot = option("--snapshot").map { URL(fileURLWithPath: $0) }
    settings.show(snapshot: snapshot)
    if snapshot == nil { withExtendedLifetime(settings) { app.run() } }
    return true
}
