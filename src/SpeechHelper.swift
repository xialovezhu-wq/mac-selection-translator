import Foundation

@main
struct SpeechHelperMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--settings") {
            if !runSpeechSettings(arguments: CommandLine.arguments) { exit(2) }
            return
        }
        if CommandLine.arguments.contains("--catalog") {
            emitSpeechJSON(speechCatalog())
            return
        }
        // Streaming hs.task keeps stdin open. One JSON line is one request;
        // waiting for EOF here would leave every hotkey request silent.
        var data = Data()
        while data.count <= 65536 {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if let end = data.firstIndex(of: 10) {
                data = Data(data[..<end])
                break
            }
        }
        guard data.count <= 65536, let request = try? JSONDecoder().decode(SpeechRequest.self, from: data) else {
            emitSpeechJSON(SpeechEvent(event: "error", requestId: "invalid", error: "invalidRequest"))
            exit(2)
        }
        let runtime = SpeechRun(request: request, rendering: CommandLine.arguments.contains("--render"))
        runtime.start()
        withExtendedLifetime(runtime) { RunLoop.main.run() }
    }
}
