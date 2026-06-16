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
    @State private var columns: NavigationSplitViewVisibility = .all   // collapse sidebar while reading

    private func openSelectedReader() {
        if let id = vm.currentPaperID, let paper = vm.papers.first(where: { $0.id == id }) {
            vm.openReader(paper)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if vm.readingPaperID != nil {
                ReadingRail()
                    .environmentObject(vm)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            splitView
        }
        .animation(.easeInOut(duration: 0.25), value: vm.readingPaperID)
    }

    @ViewBuilder private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView().environmentObject(vm).frame(minWidth: 200)
        } detail: {
            detail
        }
        .onChange(of: vm.readingPaperID) { _, reading in
            withAnimation(.easeInOut(duration: 0.25)) {
                columns = (reading != nil) ? .detailOnly : .all
            }
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
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .task { vm.reload() }
        .sheet(item: $vm.editingPaper) { PaperEditSheet(paper: $0).environmentObject(vm) }
    }

    @ViewBuilder private var detail: some View {
        Group {
            // While reading, always use the three-pane layout so the reader has its
            // detail pane (with the paper list still beside it).
            if vm.readingPaperID != nil {
                ThreePaneView()
            } else {
                switch mode {
                case .threePane: ThreePaneView()
                case .gallery: GalleryView()
                case .rows: RowsView()
                }
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
        .onDeleteCommand { vm.bulkDelete() }
        .background(
            Button("") { openSelectedReader() }
                .keyboardShortcut("o", modifiers: [.command])
                .hidden()
        )
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
                    Button("Load missing figures & PDFs") { vm.retryAllIncomplete() }
                    Button("Re-fetch all figures") { vm.refetchAllFigures() }
                    Button("Check for code now") {
                        Task { await AppEnvironment.shared.codeWatcher?.sweep(force: true) }
                    }
                    Button("Re-validate code links") {
                        Task { await AppEnvironment.shared.codeWatcher?.revalidate() }
                    }
                    Divider()
                    Button("Export BibTeX…") { exportBibTeX() }
                } label: { Label("Actions", systemImage: "ellipsis.circle") }
            }
        }
    }
}
