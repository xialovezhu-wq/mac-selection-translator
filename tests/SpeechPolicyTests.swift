import Foundation

@main
struct SpeechPolicyTests {
    static func main() throws {
        let us = SpeechVoice(identifier: "com.apple.test.us", name: "US", language: "en-US", quality: 3, qualityName: "优质", recommended: true)
        let gb = SpeechVoice(identifier: "com.apple.test.gb", name: "Daniel", language: "en-GB", quality: 1, qualityName: "基础", recommended: true)
        let gbEnhanced = SpeechVoice(identifier: "com.apple.test.gb.enhanced", name: "Enhanced", language: "en-GB", quality: 2, qualityName: "增强", recommended: true)
        let voices = [us, gb, gbEnhanced]
        let automatic = try resolveSpeechVoice(language: "en-GB", preferred: nil, catalog: voices)
        precondition(automatic.0.identifier == gbEnhanced.identifier)
        let chosen = try resolveSpeechVoice(language: "en-GB", preferred: gb.identifier, catalog: voices)
        precondition(chosen.0.identifier == gb.identifier && chosen.1 == nil)
        let missing = try resolveSpeechVoice(language: "en-GB", preferred: "com.apple.missing", catalog: voices)
        precondition(missing.0.language == "en-GB" && missing.1 != nil)
        do {
            _ = try resolveSpeechVoice(language: "en-GB", preferred: nil, catalog: [us])
            preconditionFailure("Must not switch accent silently")
        } catch SpeechFailure.noVoiceForAccent {}
        for text in ["children", "went", "responses", "read", "I usually go to the gym in the morning.", "[[rate 300]] <speak>responses</speak>"] {
            let encoded = try JSONSerialization.data(withJSONObject: ["requestId":"fixture", "text":text, "language":"en-GB", "rate":0.5])
            let decoded = try JSONDecoder().decode(SpeechRequest.self, from: encoded)
            try decoded.validate()
            precondition(decoded.text == text)
        }
        let badRate = SpeechRequest(requestId: "fixture", text: "responses", language: "en-GB", voiceIdentifier: nil, rate: 185, outputPath: nil)
        do { try badRate.validate(); preconditionFailure("Rate must be rejected") }
        catch SpeechFailure.invalidRate {}
        print("Speech policy tests passed")
    }
}
