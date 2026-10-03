import AppKit
import SwiftUI
import Translation

private let sample = "The committee invited several idealists to discuss the plan."

@MainActor
func report(_ values: [String: String]) {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--report"), args.indices.contains(i + 1),
          let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) else { return }
    try? data.write(to: URL(fileURLWithPath: args[i + 1]), options: .atomic)
}

struct PreparationView: View {
    @State private var configuration: TranslationSession.Configuration? = .init(
        source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans"))
    @State private var status = "正在准备苹果英中离线翻译。"
    @State private var translation = ""
    @State private var ready = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("启用英中整句离线翻译").font(.title2)
            Text("如苹果系统提示下载语言，请下载英语和简体中文。下载完成后，划词快捷键也可以翻译整句话。")
                .foregroundStyle(.secondary)
            Text(status).textSelection(.enabled)
            if !translation.isEmpty {
                Divider()
                Text(sample).foregroundStyle(.secondary)
                Text(translation).font(.headline).textSelection(.enabled)
            }
            HStack {
                Button("重新准备") { ready = false; configuration?.invalidate() }
                if ready { Button("完成") { NSApplication.shared.terminate(nil) } }
            }
        }
        .padding(28)
        .frame(width: 520)
        .translationTask(configuration) { session in
            report(["state": "preparing"])
            do {
                try await session.prepareTranslation()
                let response = try await session.translate(sample)
                translation = response.targetText
                status = "英中离线翻译已就绪。"
                ready = true
                report(["state": "ready", "testTranslation": response.targetText])
            } catch {
                status = "尚未完成准备：" + error.localizedDescription
                report(["state": "error", "message": error.localizedDescription])
            }
        }
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
}

@main
struct LanguagePreparationApp: App {
    var body: some Scene {
        WindowGroup("整句离线翻译准备") { PreparationView() }
            .windowResizability(.contentSize)
    }
}
