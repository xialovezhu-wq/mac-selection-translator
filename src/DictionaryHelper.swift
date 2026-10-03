import Foundation
import CoreServices
import Translation

// One request per process. No query files, history, network client, or shell.
struct Request: Decodable { let text: String }
struct Response: Encodable {
    var ok: Bool
    var result: String? = nil
    var engine: String? = nil
    var error: String? = nil
    var message: String? = nil
    var durationMs: Double = 0
}

func emit<T: Encodable>(_ value: T) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func hasChinese(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
}

func chineseGlosses(_ definition: String, word: String) -> String? {
    var body = definition
    if let bar = body.range(of: " | ") { body = String(body[bar.upperBound...]) }
    // Each numbered dictionary sense starts before its example marker (▸).
    // Extract the publisher's Chinese glosses; do not generate new examples.
    let parts = body.components(separatedBy: CharacterSet(charactersIn: "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"))
    guard let pattern = try? NSRegularExpression(pattern: "[\\p{Han}][\\p{Han}，、；：。？！“”‘’（）《》…· /-]*") else { return nil }
    var glosses: [String] = []
    for part in parts {
        let prefix = String(part.components(separatedBy: "▸").first ?? "")
        let range = NSRange(prefix.startIndex..., in: prefix)
        for match in pattern.matches(in: prefix, range: range) {
            guard let r = Range(match.range, in: prefix) else { continue }
            let gloss = String(prefix[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !gloss.isEmpty, gloss != word, !glosses.contains(gloss) { glosses.append(gloss) }
            if glosses.count >= 12 { break }
        }
        if glosses.count >= 12 { break }
    }
    return glosses.isEmpty ? nil : glosses.joined(separator: "；")
}

func dictionaryDefinition(_ text: String) -> String? {
    // Dictionary Services may otherwise return just the first word of a sentence.
    guard text.utf16.count <= 160 else { return nil }
    let cfText = text as CFString
    let range = DCSGetTermRangeInString(nil, cfText, 0)
    guard range.location == 0, range.length == text.utf16.count else { return nil }
    guard let definition = DCSCopyTextDefinition(nil, cfText, range)?.takeRetainedValue() else { return nil }
    let result = definition as String
    let heading = result.components(separatedBy: " | ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard heading?.lowercased() == text.lowercased() else { return nil }
    // An English definition must never be presented as a Chinese translation.
    return hasChinese(result) ? chineseGlosses(result, word: text) : nil
}

@main
struct DictionaryHelper {
    static func main() async {
        if CommandLine.arguments.contains("--health") {
            var status = "requires_macos_26"
            if #available(macOS 26.0, *) {
                let availability = await LanguageAvailability().status(
                    from: Locale.Language(identifier: "en"),
                    to: Locale.Language(identifier: "zh-Hans")
                )
                status = availability == .installed ? "installed" :
                    availability == .supported ? "not_downloaded" : "unsupported"
            }
            emit(["dictionaryChinese": dictionaryDefinition("hello") == nil ? "unavailable" : "available",
                  "sentenceTranslation": status])
            return
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let input = FileHandle.standardInput.readData(ofLength: 65537)
        guard input.count <= 65536,
              let request = try? JSONDecoder().decode(Request.self, from: input) else {
            emit(Response(ok: false, error: "invalid_request", message: "输入格式无效。"))
            return
        }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 2048,
              !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            emit(Response(ok: false, error: "invalid_selection", message: "请选中有效文本，最多 2048 个字符。"))
            return
        }
        func timed(_ response: Response) -> Response {
            var response = response
            response.durationMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            return response
        }

        if let definition = dictionaryDefinition(text) {
            emit(timed(Response(ok: true, result: definition, engine: "apple_dictionary")))
            return
        }

        if #available(macOS 26.0, *) {
            let en = Locale.Language(identifier: "en")
            let zh = Locale.Language(identifier: "zh-Hans")
            // installedSource cannot download models or silently use a remote service.
            let status = await LanguageAvailability().status(from: en, to: zh)
            guard status == .installed else {
                emit(timed(Response(ok: false, error: "language_pack_missing",
                    message: "英汉词典未收录此选文。苹果英中离线语言包尚未下载，可在系统翻译设置中下载后重试。")))
                return
            }
            do {
                let session = TranslationSession(installedSource: en, target: zh)
                let response = try await session.translate(text)
                emit(timed(Response(ok: true, result: response.targetText, engine: "apple_translation")))
            } catch {
                emit(timed(Response(ok: false, error: "translation_failed",
                    message: "苹果离线翻译暂时不可用，请检查已下载的英中语言包。")))
            }
        } else {
            emit(timed(Response(ok: false, error: "dictionary_miss",
                message: "本地英汉词典未收录此选文。此版本的整句离线翻译需要 macOS 26 或更新版本。")))
        }
    }
}
