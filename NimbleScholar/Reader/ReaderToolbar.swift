import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

struct ReaderToolbar: ToolbarContent {
    @Binding var pdfView: PDFView?
    @Binding var displayMode: PDFDisplayMode
    @Binding var showThumbs: Bool
    @Binding var showInspector: Bool
    @ObservedObject var vm: ReaderViewModel
    @State private var search = ""

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showThumbs.toggle() } label: { Image(systemName: "sidebar.left") }
        }
        ToolbarItemGroup {
            TextField("Search", text: $search)
                .frame(width: 160)
                .onSubmit(runSearch)
            Button { pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit") {
                if let pv = pdfView { pv.autoScales = true; pv.scaleFactor = pv.scaleFactorForSizeToFit }
            }
            Picker("", selection: $displayMode) {
                Image(systemName: "doc").tag(PDFDisplayMode.singlePage)
                Image(systemName: "doc.on.doc").tag(PDFDisplayMode.singlePageContinuous)
                Image(systemName: "book.pages").tag(PDFDisplayMode.twoUpContinuous)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            Button { highlightSelection() } label: { Image(systemName: "highlighter") }
            Button { addNote() } label: { Image(systemName: "note.text.badge.plus") }
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
        }
    }

    private func runSearch() {
        guard let pv = pdfView, !search.isEmpty,
              let sel = pv.document?.findString(search, withOptions: .caseInsensitive).first else { return }
        pv.setCurrentSelection(sel, animate: true)
        pv.go(to: sel)
    }

    private func highlightSelection() {
        guard let pv = pdfView, let sel = pv.currentSelection else { return }
        AnnotationController(vm: vm).highlight(selection: sel, in: pv)
    }

    private func addNote() {
        guard let pv = pdfView, let page = pv.currentPage,
              let text = AnnotationController.promptNoteText() else { return }
        let center = pv.convert(pv.bounds.center, to: page)
        AnnotationController(vm: vm).addNote(text: text, at: center, on: page, pdfView: pv)
    }
}
