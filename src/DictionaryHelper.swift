import Foundation
import CoreServices
import Translation
import NaturalLanguage

// One request per process. No query files, history, network client, or shell.
struct Request: Decodable {
    let text: String
    let forceSentence: Bool?
}
struct Response: Encodable {
    var ok: Bool
    var result: String? = nil
    var engine: String? = nil
    var lookupTerm: String? = nil
    var partsOfSpeech: [String]? = nil
    var partOfSpeechSource: String? = nil
    var selectionKind: String? = nil
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

struct DictionaryEntry {
    let term: String
    let glosses: String
    let partsOfSpeech: [String]
}

private let partOfSpeechNames = [
    "noun": "名词", "adjective": "形容词", "adverb": "副词",
    "transitive verb": "及物动词", "intransitive verb": "不及物动词", "verb": "动词",
    "auxiliary verb": "助动词", "modal verb": "情态动词", "preposition": "介词",
    "copular verb": "系动词", "article": "冠词", "definite article": "定冠词",
    "indefinite article": "不定冠词", "infinitive marker": "不定式标记",
    "pronoun": "代词", "determiner": "限定词", "conjunction": "连词",
    "exclamation": "感叹词", "interjection": "感叹词", "prefix": "前缀", "suffix": "后缀",
    "abbreviation": "缩略词"
]

func dictionaryPartsOfSpeech(_ definition: String) -> [String] {
    let names = partOfSpeechNames.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    let pattern = "(?:\\|\\s*|(?:^|\\s)[A-G]\\.\\s*|&\\s*)(" + names + ")\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
    var result: [String] = []
    for match in regex.matches(in: definition, range: NSRange(definition.startIndex..., in: definition)) {
        guard let range = Range(match.range(at: 1), in: definition),
              let name = partOfSpeechNames[String(definition[range]).lowercased()],
              !result.contains(name) else { continue }
        result.append(name)
    }
    return result
}

func inferredPartsOfSpeech(_ text: String) -> [String] {
    guard isEnglishWord(text) else { return [] }
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text
    tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
    let (tag, _) = tagger.tag(at: text.startIndex, unit: .word, scheme: .lexicalClass)
    let names: [NLTag: String] = [.noun: "名词", .verb: "动词", .adjective: "形容词",
        .adverb: "副词", .pronoun: "代词", .determiner: "限定词", .particle: "小品词",
        .preposition: "介词", .conjunction: "连词", .interjection: "感叹词"]
    return tag.flatMap { names[$0] }.map { [$0] } ?? []
}

func isEnglishWord(_ text: String) -> Bool {
    text.range(of: "^[A-Za-z]+(?:[-'’][A-Za-z]+)*$", options: .regularExpression) != nil
}

func standaloneWord(_ text: String) -> String? {
    let word = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'‘’()[]{}.,;:!?《》"))
    return isEnglishWord(word) ? word : nil
}

func dictionaryHeading(_ definition: String) -> String? {
    guard let separator = definition.range(of: " | ") else { return nil }
    let heading = String(definition[..<separator.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    // Homographs in the installed dictionary use headings such as "box 1".
    return heading.replacingOccurrences(of: "(?: [0-9]+|[¹²³⁴⁵⁶⁷⁸⁹⁰]+)$", with: "",
                                         options: .regularExpression)
}

func inflectionReference(_ definition: String) -> String? {
    // Native entries for children/went can be grammatical references without
    // Chinese glosses. Follow only explicitly labelled dictionary inflections.
    let pattern = "(?:plural|past tense|past participle|present participle|third person singular)\\s*→\\s*([A-Za-z]+(?:[-'’][A-Za-z]+)*)\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: definition, range: NSRange(definition.startIndex..., in: definition)),
          let range = Range(match.range(at: 1), in: definition) else { return nil }
    return String(definition[range])
}

func dictionaryDefinition(_ text: String) -> DictionaryEntry? {
    guard text.utf16.count <= 160 else { return nil }
    var query = text
    var visited: Set<String> = []
    for _ in 0..<4 {
        guard visited.insert(query.lowercased()).inserted else { return nil }
        let cfText = query as CFString
        let range = DCSGetTermRangeInString(nil, cfText, 0)
        // Keep the whole-selection check: no sentence-first-word lookup and
        // never pass a not-found range to DCSCopyTextDefinition.
        guard range.location == 0, range.length == query.utf16.count else { return nil }
        guard let definition = DCSCopyTextDefinition(nil, cfText, range)?.takeRetainedValue() else { return nil }
        let result = definition as String
        guard let heading = dictionaryHeading(result) else { return nil }
        // Dictionary Services resolves inflected single words itself (e.g.
        // idealists -> idealist). Accept that canonical entry rather than
        // rejecting its title. Phrases still require an identical heading.
        guard heading.lowercased() == query.lowercased() ||
                (isEnglishWord(query) && isEnglishWord(heading)) else { return nil }
        if hasChinese(result), let glosses = chineseGlosses(result, word: query) {
            return DictionaryEntry(term: heading, glosses: glosses,
                                   partsOfSpeech: dictionaryPartsOfSpeech(result))
        }
        guard isEnglishWord(query), let reference = inflectionReference(result) else { return nil }
        query = reference
    }
    return nil
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

        let word = standaloneWord(text)
        if request.forceSentence != true, let definition = dictionaryDefinition(word ?? text) {
            let dictionaryPOS = definition.partsOfSpeech
            let pos = dictionaryPOS.isEmpty ? inferredPartsOfSpeech(word ?? text) : dictionaryPOS
            emit(timed(Response(ok: true, result: definition.glosses, engine: "apple_dictionary",
                lookupTerm: definition.term, partsOfSpeech: pos,
                partOfSpeechSource: dictionaryPOS.isEmpty ? "system_tag" : "dictionary",
                selectionKind: word != nil ? "word" : "phrase")))
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
                guard hasChinese(response.targetText) else {
                    emit(timed(Response(ok: false, error: "no_chinese_translation",
                        message: "本地引擎没有返回中文释义，请检查选词拼写或连同上下文一起选中。")))
                    return
                }
                let pos = inferredPartsOfSpeech(word ?? text)
                emit(timed(Response(ok: true, result: response.targetText, engine: "apple_translation",
                    partsOfSpeech: pos, partOfSpeechSource: "system_tag",
                    selectionKind: request.forceSentence != true && word != nil ? "word" : "sentence")))
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
