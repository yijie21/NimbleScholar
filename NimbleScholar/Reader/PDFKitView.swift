import SwiftUI
import PDFKit
import AppKit
import CoreImage

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayMode
    @AppStorage("nightReading") private var nightReading = false
    let vm: ReaderViewModel
    let onReady: (PDFView) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = AnnotatingPDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = displayMode
        v.displayDirection = .vertical
        v.wantsLayer = true

        // Right-click menu actions on a text selection.
        v.onHighlight = { [weak v] in
            guard let v, let sel = v.currentSelection, !(sel.string ?? "").isEmpty else { return }
            AnnotationController(vm: vm).highlight(selection: sel, in: v)
        }
        v.onNote = { [weak v] in
            guard let v, let page = v.currentPage, let text = AnnotationController.promptNoteText() else { return }
            let point = v.convert(v.bounds.center, to: page)
            AnnotationController(vm: vm).addNote(text: text, at: point, on: page, pdfView: v)
        }

        onReady(v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
        v.displayMode = displayMode
        v.layer?.filters = nightReading ? [CIFilter(name: "CIColorInvert")!] : []
    }
}

/// PDFView that adds Highlight / Add Note to the right-click menu when text is selected.
final class AnnotatingPDFView: PDFView {
    var onHighlight: (() -> Void)?
    var onNote: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let s = currentSelection?.string, !s.isEmpty {
            let highlight = NSMenuItem(title: "Highlight", action: #selector(triggerHighlight), keyEquivalent: "")
            highlight.target = self
            let note = NSMenuItem(title: "Add Note…", action: #selector(triggerNote), keyEquivalent: "")
            note.target = self
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(note, at: 0)
            menu.insertItem(highlight, at: 0)
        }
        return menu
    }

    @objc private func triggerHighlight() { onHighlight?() }
    @objc private func triggerNote() { onNote?() }
}
