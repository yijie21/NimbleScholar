import AppKit
import UniformTypeIdentifiers

/// Shared "choose a PDF" open panel for the Import / Attach commands.
enum PDFPicker {
    static func pick(allowsMultiple: Bool, message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : []
    }
}
