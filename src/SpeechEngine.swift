import AVFoundation
import Foundation

struct SpeechVoice: Codable, Sendable {
    let identifier: String
    let name: String
    let language: String
    let quality: Int
    let qualityName: String
    let recommended: Bool
}

enum SpeechFailure: String, Error {
    case invalidRequest, invalidRate, unsupportedAccent, noVoiceForAccent
    case voiceCreationFailed, voiceMismatch, synthesisFailed, synthesisTimeout
}

struct SpeechRequest: Decodable {
    let requestId: String
    let text: String
    let language: String
    let voiceIdentifier: String?
    let rate: Float
    let outputPath: String?
    var progressPath: String? = nil

    func validate() throws {
        guard requestId.range(of: "^[A-Za-z0-9_.-]{1,96}$", options: .regularExpression) != nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= 8192, !text.contains("\0") else { throw SpeechFailure.invalidRequest }
        guard ["en-US", "en-GB", "zh-CN"].contains(language) else { throw SpeechFailure.unsupportedAccent }
        guard rate.isFinite && (0.35...0.65).contains(rate) else { throw SpeechFailure.invalidRate }
    }
}

func speechVoice(_ voice: AVSpeechSynthesisVoice) -> SpeechVoice {
    let quality = voice.quality.rawValue
    let novelty = voice.voiceTraits.contains(.isNoveltyVoice)
    let personal = voice.voiceTraits.contains(.isPersonalVoice)
    let modern = voice.identifier.hasPrefix("com.apple.voice.")
    return SpeechVoice(identifier: voice.identifier, name: voice.name, language: voice.language,
        quality: quality, qualityName: quality >= 3 ? "优质" : quality == 2 ? "增强" : "基础",
        recommended: !novelty && !personal && (modern || quality > 1))
}

func speechCatalog() -> [SpeechVoice] {
    var seen = Set<String>()
    return AVSpeechSynthesisVoice.speechVoices().filter {
        ["en-US", "en-GB", "zh-CN"].contains($0.language)
            && $0.identifier.hasPrefix("com.apple.")
            && !$0.voiceTraits.contains(.isNoveltyVoice)
            && !$0.voiceTraits.contains(.isPersonalVoice)
            && seen.insert($0.identifier).inserted
    }.map(speechVoice).sorted {
        if $0.language != $1.language { return $0.language < $1.language }
        if $0.quality != $1.quality { return $0.quality > $1.quality }
        if $0.recommended != $1.recommended { return $0.recommended }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

func resolveSpeechVoice(language: String, preferred: String?, catalog: [SpeechVoice]) throws
    -> (SpeechVoice, String?) {
    let eligible = catalog.filter { $0.language == language }
    if let preferred, !preferred.isEmpty,
       let selected = eligible.first(where: { $0.identifier == preferred }) {
        return (selected, nil)
    }
    let humanVoices = eligible.filter(\.recommended)
    guard !humanVoices.isEmpty else { throw SpeechFailure.noVoiceForAccent }
    let familiar = ["en-US": "Samantha", "en-GB": "Daniel", "zh-CN": "Tingting"][language]
    let ranked = humanVoices.sorted {
        if $0.quality != $1.quality { return $0.quality > $1.quality }
        if ($0.name == familiar) != ($1.name == familiar) { return $0.name == familiar }
        return $0.identifier < $1.identifier
    }
    let reason = preferred == nil || preferred == "" ? nil : "所选声音不可用，暂用同口音的可用声音；已保存的选择未被覆盖。"
    return (ranked[0], reason)
}

let speechSample = "Hello. Comfortable. Development. Opportunity. Children. Went. Responses. I usually go to the gym in the morning. What I enjoy most is learning something new."

func emitSpeechJSON<T: Encodable>(_ value: T) {
    if let data = try? JSONEncoder().encode(value) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

struct SpeechEvent: Encodable {
    let event: String
    let requestId: String
    var engine = "AVSpeechSynthesizer"
    var voice: SpeechVoice?
    var requestedVoice: String?
    var fallbackReason: String?
    var rate: Float?
    var elapsedMs: Double?
    var error: String?
    var frames: Int64?
    var sampleRate: Double?
}

private struct SpeechPCM: Sendable {
    let samples: [Data]
    let frames: AVAudioFrameCount
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let format: UInt
    let interleaved: Bool

    init(_ buffer: AVAudioPCMBuffer) {
        frames = buffer.frameLength
        sampleRate = buffer.format.sampleRate
        channels = buffer.format.channelCount
        format = buffer.format.commonFormat.rawValue
        interleaved = buffer.format.isInterleaved
        samples = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList).map {
            guard let pointer = $0.mData, $0.mDataByteSize > 0 else { return Data() }
            return Data(bytes: pointer, count: Int($0.mDataByteSize))
        }
    }
}

@MainActor
final class SpeechRun: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let request: SpeechRequest
    private let rendering: Bool
    private let begin = DispatchTime.now().uptimeNanoseconds
    private var resolved: SpeechVoice?
    private var completed = false
    private var cancelled = false
    private var started = false
    private var signals: [DispatchSourceSignal] = []
    private var audioFile: AVAudioFile?
    private var frames: Int64 = 0
    private var sampleRate: Double = 0
    private var fallbackReason: String?
    private let parentPID = getppid()
    private var parentWatch: DispatchSourceTimer?

    private func emit(_ value: SpeechEvent) {
        var event = value
        event.requestedVoice = request.voiceIdentifier
        event.fallbackReason = fallbackReason
        // Only voice/runtime metadata is written. No selection text or audio.
        if let path = request.progressPath, path.hasPrefix("/"),
           let data = try? JSONEncoder().encode(event) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        emitSpeechJSON(event)
    }

    init(request: SpeechRequest, rendering: Bool) {
        self.request = request
        self.rendering = rendering
        super.init()
        synthesizer.delegate = self
    }

    private var elapsed: Double { Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000 }

    func start() {
        do {
            try request.validate()
            let (choice, fallback) = try resolveSpeechVoice(language: request.language,
                preferred: request.voiceIdentifier, catalog: speechCatalog())
            fallbackReason = fallback
            guard let voice = AVSpeechSynthesisVoice(identifier: choice.identifier) else {
                throw SpeechFailure.voiceCreationFailed
            }
            guard voice.identifier == choice.identifier && voice.language == request.language else {
                throw SpeechFailure.voiceMismatch
            }
            resolved = speechVoice(voice)
            // Plain-string utterances preserve the actual selection, including
            // inflections. They do not interpret the text as SSML or shell code.
            let utterance = AVSpeechUtterance(string: request.text)
            utterance.voice = voice
            utterance.rate = request.rate
            utterance.volume = 1
            utterance.pitchMultiplier = 1
            guard utterance.voice?.identifier == choice.identifier else { throw SpeechFailure.voiceMismatch }
            guard abs(utterance.rate - request.rate) < 0.0001 else { throw SpeechFailure.invalidRate }
            emit(SpeechEvent(event: "resolved", requestId: request.requestId,
                voice: resolved, requestedVoice: request.voiceIdentifier, fallbackReason: fallback,
                rate: request.rate, elapsedMs: elapsed))
            for number in [SIGTERM, SIGINT] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { [weak self] in self?.cancel() }
                source.resume(); signals.append(source)
            }
            let owner = parentPID
            let watch = DispatchSource.makeTimerSource(queue: .main)
            watch.schedule(deadline: .now() + 0.2, repeating: 0.2)
            watch.setEventHandler { [weak self] in
                if getppid() != owner { DispatchQueue.main.async { self?.cancel() } }
            }
            watch.resume(); parentWatch = watch
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, !self.started && !self.completed else { return }
                self.fail(.synthesisTimeout)
            }
            if rendering {
                guard let output = request.outputPath, output.hasPrefix("/") else {
                    throw SpeechFailure.invalidRequest
                }
                synthesizer.write(utterance) { [weak self] buffer in
                    guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
                    // AVFoundation owns callback buffers. Copy their bytes before
                    // returning, then serialize file writes and lifecycle on main.
                    let snapshot = SpeechPCM(pcm)
                    DispatchQueue.main.async { self.accept(snapshot, output: output) }
                }
            } else {
                synthesizer.speak(utterance)
            }
        } catch let error as SpeechFailure { fail(error) }
        catch { fail(.synthesisFailed) }
    }

    private func accept(_ snapshot: SpeechPCM, output: String) {
        guard !completed && !cancelled else { return }
        if snapshot.frames == 0 { audioFile = nil; finish("finished"); return }
        guard let format = AVAudioCommonFormat(rawValue: snapshot.format),
              let audioFormat = AVAudioFormat(commonFormat: format, sampleRate: snapshot.sampleRate,
                channels: snapshot.channels, interleaved: snapshot.interleaved),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: snapshot.frames) else {
            fail(.synthesisFailed); return
        }
        buffer.frameLength = snapshot.frames
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard buffers.count == snapshot.samples.count else { fail(.synthesisFailed); return }
        for i in snapshot.samples.indices {
            guard let destination = buffers[i].mData,
                  snapshot.samples[i].count <= Int(buffers[i].mDataByteSize) else {
                fail(.synthesisFailed); return
            }
            snapshot.samples[i].withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { memcpy(destination, base, bytes.count) }
            }
        }
        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: output),
                    settings: audioFormat.settings, commonFormat: audioFormat.commonFormat,
                    interleaved: audioFormat.isInterleaved)
                sampleRate = audioFormat.sampleRate
            }
            try audioFile?.write(from: buffer)
            frames += Int64(buffer.frameLength)
        } catch { fail(.synthesisFailed) }
    }

    func cancel() {
        guard !completed else { return }
        cancelled = true
        let stopping = synthesizer.stopSpeaking(at: .immediate)
        if !stopping { finish("cancelled"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finish("cancelled")
        }
    }

    private func fail(_ error: SpeechFailure) {
        guard !completed else { return }
        completed = true
        synthesizer.stopSpeaking(at: .immediate)
        emit(SpeechEvent(event: "error", requestId: request.requestId, voice: resolved,
            rate: request.rate, elapsedMs: elapsed, error: error.rawValue))
        exit(2)
    }

    private func finish(_ event: String) {
        guard !completed else { return }
        completed = true
        emit(SpeechEvent(event: cancelled ? "cancelled" : event, requestId: request.requestId,
            voice: resolved, rate: request.rate, elapsedMs: elapsed,
            frames: rendering ? frames : nil, sampleRate: rendering ? sampleRate : nil))
        exit(0)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.didStart() }
    }

    private func didStart() {
        guard !completed && !cancelled else { return }
        started = true
        emit(SpeechEvent(event: "started", requestId: request.requestId, voice: resolved,
            rate: request.rate, elapsedMs: elapsed))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if !self.rendering { self.finish("finished") } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.finish("cancelled") }
    }
}
