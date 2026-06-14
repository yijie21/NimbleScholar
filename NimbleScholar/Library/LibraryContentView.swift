import SwiftUI
import AppKit
import NimbleScholarCore

/// Export the whole library to a .bib file (shared by the toolbar menu and the ⇧⌘E command).
@MainActor func exportBibTeX() {
    let papers = (try? AppEnvironment.shared.store.searchPapers(query: nil, tag: nil)) ?? []
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "papers.bib"
    if panel.runModal() == .OK, let url = panel.url {
        try? BibTeXExporter.export(papers).data(using: .utf8)?.write(to: url)
    }
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case threePane, gallery, rows
    var id: String { rawValue }
    var label: String {
        switch self {
        case .threePane: return "Three-pane"
        case .gallery: return "Gallery"
        case .rows: return "Rows"
        }
    }
    var symbol: String {
        switch self {
        case .threePane: return "sidebar.right"
        case .gallery: return "square.grid.2x2"
        case .rows: return "list.bullet"
        }
    }
}

struct LibraryContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = LibraryViewModel()
    @AppStorage("libraryViewMode") private var mode: LibraryViewMode = .threePane
    @State private var capturing = false

    var body: some View {
        NavigationSplitView {
            SidebarView().environmentObject(vm).frame(minWidth: 200)
        } detail: {
            detail
        }
        .safeAreaInset(edge: .top) {
            if let e = env.startupError {
                Text("⚠️ Running on a temporary in-memory library — nothing will be saved.\n\(e)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
            }
        }
        .task { vm.reload() }
        .sheet(item: $vm.editingPaper) { PaperEditSheet(paper: $0).environmentObject(vm) }
        .sheet(isPresented: $capturing) { CaptureSheet().environmentObject(vm) }
    }

    @ViewBuilder private var detail: some View {
        Group {
            switch mode {
            case .threePane: ThreePaneView()
            case .gallery: GalleryView()
            case .rows: RowsView()
            }
        }
        .environmentObject(vm)
        .navigationTitle(vm.scopeTitle)
        .searchable(text: $vm.query, prompt: "Search papers, authors, DOI, tags")
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            for url in pdfs { vm.importPDF(at: url) }
            return !pdfs.isEmpty
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(LibraryViewMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Picker("Sort", selection: $vm.sort) {
                    ForEach(LibraryViewModel.SortMode.allCases) { Text($0.label).tag($0) }
                }
            }
            ToolbarItem {
                Menu {
                    Button("Download all PDFs") { Task { await vm.downloadAllPDFs() } }
                    Button("Refresh arXiv figures") { Task { await vm.refreshAllFigures() } }
                    Divider()
                    Button("Export BibTeX…") { exportBibTeX() }
                } label: { Label("Actions", systemImage: "ellipsis.circle") }
            }
            ToolbarItem {
                Button { capturing = true } label: { Label("Capture", systemImage: "link.badge.plus") }
            }
            ToolbarItem {
                Button { vm.editingPaper = Paper(title: "") } label: { Label("Add", systemImage: "plus") }
            }
        }
    }
}
