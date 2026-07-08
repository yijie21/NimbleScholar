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
            guard let v, let sel = v.currentSelection, !(sel.string ?? "").isEmpty,
                  let text = AnnotationController.promptNoteText() else { return }
            AnnotationController(vm: vm).addNote(text: text, selection: sel, in: v)
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
        // The detail view shows "Last read: p. X of Y" without opening the PDF.
        UserDefaults.standard.set(document.pageCount, forKey: "readingPageCount.\(vm.paper.id ?? -1)")
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

    // Hover state for note dots. The popover only closes when we tell it to (.applicationDefined),
    // so we manage show/close on mouse enter/leave of a dot. `hoveredDot` keeps the dot's original
    // bounds so the transient "grow" can be undone without ever persisting it.
    private lazy var notePopover: NSPopover = {
        let p = NSPopover(); p.behavior = .applicationDefined; p.animates = false; return p
    }()
    private var hoveredDot: (annotation: PDFAnnotation, original: CGRect)?

    // Quick action menu shown next to a fresh text selection. Transient so clicking away (or
    // starting a new selection) dismisses it.
    private lazy var selectionPopover: NSPopover = {
        let p = NSPopover(); p.behavior = .transient; p.animates = false; return p
    }()

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

    // MARK: - Selection quick-menu

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        showSelectionMenuIfNeeded()
    }

    /// After a drag-select, float a small Highlight / Add Note menu next to the selection.
    private func showSelectionMenuIfNeeded() {
        guard let sel = currentSelection, !(sel.string ?? "").isEmpty, let page = sel.pages.first else {
            if selectionPopover.isShown { selectionPopover.close() }
            return
        }
        let host = NSHostingController(rootView: SelectionMenu(
            onHighlight: { [weak self] in self?.selectionPopover.close(); self?.onHighlight?() },
            onNote:      { [weak self] in self?.selectionPopover.close(); self?.onNote?() }))
        host.view.layoutSubtreeIfNeeded()
        selectionPopover.contentViewController = host
        selectionPopover.contentSize = host.view.fittingSize
        selectionPopover.show(relativeTo: convert(sel.bounds(for: page), from: page),
                              of: self, preferredEdge: .maxY)
    }

    // MARK: - Note-dot hover (grow + popover)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    /// The note dot (a small `.circle` annotation) under a view-space point, with its page.
    private func noteDot(at viewPoint: NSPoint) -> (PDFAnnotation, PDFPage)? {
        guard let page = page(for: viewPoint, nearest: false) else { return nil }
        let pagePoint = convert(viewPoint, to: page)
        guard let a = page.annotation(at: pagePoint), a.type == "Circle" else { return nil }
        return (a, page)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let hit = noteDot(at: convert(event.locationInWindow, from: nil))
        if hit?.0 === hoveredDot?.annotation { return }   // no change in hovered dot
        clearHover()
        guard let (dot, page) = hit else { return }
        // Grow the dot a touch — transient, restored on exit, never saved.
        let original = dot.bounds
        dot.bounds = original.insetBy(dx: -3, dy: -3)
        needsDisplay = true
        hoveredDot = (dot, original)
        // Read-only popover with the note text, pointing inward over the page.
        let host = NSHostingController(rootView: NoteHoverView(text: dot.contents ?? ""))
        host.view.layoutSubtreeIfNeeded()
        notePopover.contentViewController = host
        notePopover.contentSize = host.view.fittingSize
        let onLeft = original.midX < page.bounds(for: .mediaBox).midX
        notePopover.show(relativeTo: convert(original, from: page), of: self,
                         preferredEdge: onLeft ? .maxX : .minX)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }

    /// Restore a hovered dot's size and dismiss the popover.
    private func clearHover() {
        if let prev = hoveredDot {
            prev.annotation.bounds = prev.original
            needsDisplay = true
            hoveredDot = nil
        }
        if notePopover.isShown { notePopover.close() }
    }
}

/// Quick actions shown next to a fresh text selection.
private struct SelectionMenu: View {
    let onHighlight: () -> Void
    let onNote: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onHighlight) { Label("Highlight", systemImage: "highlighter") }
            Divider().frame(height: 16)
            Button(action: onNote) { Label("Add Note", systemImage: "note.text") }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize()
    }
}

/// Small read-only body shown in the popover when hovering a note dot.
private struct NoteHoverView: View {
    let text: String
    var body: some View {
        Text(text.isEmpty ? "Note" : text)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: 280, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
    }
}
