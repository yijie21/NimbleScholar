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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let v = AnnotatingPDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = displayMode
        v.displayDirection = .vertical
        v.wantsLayer = true

        v.onHighlight = { [weak v] in
            guard let v, let sel = v.currentSelection, !(sel.string ?? "").isEmpty else { return }
            AnnotationController(vm: vm).highlight(selection: sel, in: v)
        }
        v.onNote = { [weak v] in
            guard let v, let page = v.currentPage, let text = AnnotationController.promptNoteText() else { return }
            let point = v.convert(v.bounds.center, to: page)
            AnnotationController(vm: vm).addNote(text: text, at: point, on: page, pdfView: v)
        }
        v.onDeleteAnnotation = { [weak v] annotation, page in
            guard let v else { return }
            AnnotationController(vm: vm).deleteAnnotation(annotation, on: page, pdfView: v)
        }

        // Restore last reading position.
        let saved = vm.savedPageIndex
        if saved > 0, saved < document.pageCount, let page = document.page(at: saved) {
            DispatchQueue.main.async { v.go(to: page) }
        }
        // Persist position as the user pages through. Capture only the Sendable key
        // string; reach the view via the notification object inside MainActor isolation.
        let key = "readingPage.\(vm.paper.id ?? -1)"
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: v, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let view = note.object as? PDFView, let cur = view.currentPage,
                      let idx = view.document?.index(for: cur) else { return }
                UserDefaults.standard.set(idx, forKey: key)
            }
        }

        // Defer to the next runloop tick: calling back synchronously here would set the
        // caller's @State during SwiftUI's view-update pass (ignored / doesn't propagate),
        // leaving the inspector stuck because its `pdfView` never updates.
        DispatchQueue.main.async { onReady(v) }
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
        v.displayMode = displayMode
        v.layer?.filters = nightReading ? [CIFilter(name: "CIColorInvert")!] : []
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }

    final class Coordinator {
        var observer: NSObjectProtocol?
    }
}

/// PDFView that adds Highlight / Add Note (on a selection) and Delete Annotation
/// (on an existing annotation) to the right-click menu.
final class AnnotatingPDFView: PDFView {
    var onHighlight: (() -> Void)?
    var onNote: (() -> Void)?
    var onDeleteAnnotation: ((PDFAnnotation, PDFPage) -> Void)?
    private var pendingDelete: (PDFAnnotation, PDFPage)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let viewPoint = convert(event.locationInWindow, from: nil)

        // Right-clicking an existing annotation → offer to delete it.
        if let page = page(for: viewPoint, nearest: true) {
            let pagePoint = convert(viewPoint, to: page)
            if let annotation = page.annotation(at: pagePoint) {
                pendingDelete = (annotation, page)
                let del = NSMenuItem(title: "Delete Annotation", action: #selector(triggerDelete), keyEquivalent: "")
                del.target = self
                menu.insertItem(.separator(), at: 0)
                menu.insertItem(del, at: 0)
                return menu
            }
        }

        // Otherwise, on a text selection → highlight / note.
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
    @objc private func triggerDelete() { if let (a, p) = pendingDelete { onDeleteAnnotation?(a, p) } }
}
