import AppKit

// Owned synthetic text for native AX integration checks, never a personal document.
@main
struct SelectionFixture {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Selection Translator Synthetic Fixture"
        let text = NSTextView(frame: NSRect(x: 24, y: 100, width: 450, height: 80))
        text.font = .systemFont(ofSize: 28)
        text.string = CommandLine.arguments.dropFirst().first ?? "response"
        text.isRichText = false
        window.contentView?.addSubview(text)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        application.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            window.makeFirstResponder(text)
            text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            application.terminate(nil)
        }
        application.run()
    }
}
