import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

struct ReaderToolbar: ToolbarContent {
    @Binding var pdfView: PDFView?
    @Binding var showInspector: Bool
    @ObservedObject var vm: ReaderViewModel
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
            Button { pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit") {
                if let pv = pdfView { pv.autoScales = true; pv.scaleFactor = pv.scaleFactorForSizeToFit }
            }
            Button { highlightSelection() } label: { Image(systemName: "highlighter") }
                .help("Highlight the selected text")
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("Annotations & chat")
        }
    }

    private func highlightSelection() {
        guard let pv = pdfView, let sel = pv.currentSelection else { return }
        AnnotationController(vm: vm).highlight(selection: sel, in: pv)
    }
}
