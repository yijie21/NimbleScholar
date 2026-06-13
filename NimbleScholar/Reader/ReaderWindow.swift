import SwiftUI
import PDFKit
import NimbleScholarCore

struct ReaderWindow: View {
    @StateObject private var vm: ReaderViewModel
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var showThumbs = true
    @State private var showInspector = true
    @State private var pdfView: PDFView?

    init(paperID: Int64?) {
        _vm = StateObject(wrappedValue: ReaderViewModel(paperID: paperID))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showThumbs, let pv = pdfView {
                ThumbnailSidebar(pdfView: pv).frame(width: 140)
                Divider()
            }
            Group {
                if let doc = vm.document {
                    PDFKitView(document: doc, displayMode: $displayMode) { self.pdfView = $0 }
                } else {
                    ContentUnavailableView(vm.status, systemImage: "doc.richtext")
                }
            }
            .frame(minWidth: 420)
        }
        .toolbar {
            ReaderToolbar(pdfView: $pdfView, displayMode: $displayMode,
                          showThumbs: $showThumbs, showInspector: $showInspector, vm: vm)
        }
        .inspector(isPresented: $showInspector) {
            if let pv = pdfView {
                InspectorPanel(pdfView: pv, vm: vm)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(vm.paper.title)
        .task { await vm.load() }
    }
}
