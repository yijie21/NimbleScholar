import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

struct ReaderToolbar: ToolbarContent {
    @Binding var pdfView: PDFView?
    @Binding var displayMode: PDFDisplayMode
    @Binding var showInspector: Bool
    @ObservedObject var vm: ReaderViewModel
    @State private var search = ""
    @AppStorage("highlightColorHex") private var highlightColorHex = "#ffd966"

    private let highlightColors: [(name: String, hex: String)] = [
        ("Yellow", "#ffd966"), ("Green", "#a8e6a1"), ("Blue", "#9ec9ff"),
        ("Pink", "#ffb3d1"), ("Orange", "#ffc08a"),
    ]

    var body: some ToolbarContent {
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
            Menu {
                ForEach(highlightColors, id: \.hex) { c in
                    Button {
                        highlightColorHex = c.hex
                    } label: {
                        Label(c.name, systemImage: highlightColorHex == c.hex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: { Image(systemName: "paintpalette") }
            Button { addNote() } label: { Image(systemName: "note.text.badge.plus") }
            Button { exportMarkdown() } label: { Image(systemName: "square.and.arrow.up") }
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

    private func exportMarkdown() {
        let md = MarkdownExporter.export(paper: vm.paper, annotations: vm.annotations)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(vm.paper.title.prefix(40)).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? md.data(using: .utf8)?.write(to: url)
        }
    }
}
