import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

struct ReaderToolbar: ToolbarContent {
    @Binding var pdfView: PDFView?
    @Binding var showInspector: Bool
    /// Opens (or refocuses) the find bar — also bound to ⌘F.
    let onFind: () -> Void

    // Lean on purpose: highlight/note/color live in the selection popover, the right-click
    // menu, and Settings (highlight color) — not here.
    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button { onFind() } label: { Image(systemName: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in document (⌘F)")
            Button { pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out (⌘−)")
            Button { pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom in (⌘=)")
            Button("Fit") {
                if let pv = pdfView { pv.autoScales = true; pv.scaleFactor = pv.scaleFactorForSizeToFit }
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Fit to window (⌘0)")
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Annotations & chat (⌥⌘I)")
        }
    }
}
