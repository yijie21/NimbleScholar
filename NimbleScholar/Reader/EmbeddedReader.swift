import SwiftUI
import PDFKit
import NimbleScholarCore

/// The PDF reader hosted inside the library window (full-window reading mode).
/// Reuses the reader internals; no page-thumbnail sidebar. `onClose` returns to the library.
struct EmbeddedReader: View {
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @StateObject private var vm: ReaderViewModel
    // Continuous single-page is the only reading mode.
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var showInspector = false
    @State private var pdfView: PDFView?
    @State private var showFind = false
    @State private var findFocusRequest = 0   // bumped by ⌘F to (re)focus the find field
    let onClose: () -> Void

    init(paperID: Int64?, onClose: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ReaderViewModel(paperID: paperID))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Group {
                    if let doc = vm.document {
                        PDFKitView(document: doc, displayMode: $displayMode, vm: vm) { pv in
                            self.pdfView = pv
                            AnnotationController(vm: vm).reconcile(pdfView: pv)
                        }
                        // Find bar floats centered over the top of the page (Preview-style).
                        .overlay(alignment: .top) {
                            if showFind {
                                FindBar(pdfView: pdfView, isPresented: $showFind,
                                        focusRequest: findFocusRequest)
                                    .padding(.top, 12)
                            }
                        }
                    } else {
                        ContentUnavailableView(vm.status, systemImage: "doc.richtext")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Inline inspector panel (annotations / chat). Laid out directly
                // rather than via `.inspector`, which only renders at the window level and
                // shows nothing when the reader is nested in the three-pane detail pane.
                if showInspector {
                    Divider()
                    Group {
                        if let pv = pdfView {
                            InspectorPanel(pdfView: pv, vm: vm)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 300)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { vm.flushSave(); onClose() } label: {
                        Label("Library", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .navigation) {
                    Button { libraryVM.showPaperList.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Toggle the papers list")
                }
                ReaderToolbar(pdfView: $pdfView, showInspector: $showInspector, vm: vm) {
                    showFind = true
                    findFocusRequest += 1   // refocus the field if the bar is already open
                }
            }
            .navigationTitle(vm.paper.title)
        }
        .task { await vm.load() }
        .onDisappear { vm.flushSave() }
    }
}
