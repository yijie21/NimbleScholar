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
    case threePane, gallery, rows, mindmap
    var id: String { rawValue }
    var label: String {
        switch self {
        case .threePane: return "Three-pane"
        case .gallery: return "Gallery"
        case .rows: return "Rows"
        case .mindmap: return "Mindmap"
        }
    }
    var symbol: String {
        switch self {
        case .threePane: return "sidebar.right"
        case .gallery: return "square.grid.2x2"
        case .rows: return "list.bullet"
        case .mindmap: return "brain"
        }
    }
}

/// The two top-level sections of the window, toggled at the top of the sidebar.
enum AppSection: String { case papers, links }

/// Applies `.searchable` only when `active` — so a view can host its own search field instead.
struct OptionalSearchable: ViewModifier {
    let active: Bool
    @Binding var text: String
    let prompt: String
    func body(content: Content) -> some View {
        if active { content.searchable(text: $text, prompt: prompt) }
        else { content }
    }
}

struct LibraryContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = LibraryViewModel()
    @StateObject private var linksVM = LinksViewModel()
    @AppStorage("libraryViewMode") private var mode: LibraryViewMode = .threePane
    @AppStorage("appSection") private var section: AppSection = .papers

    /// Sidebar collapses while reading, derived directly from readingPaperID so it animates
    /// in the SAME transaction as the rail/list (avoids the two-tick stutter of an onChange).
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { vm.readingPaperID != nil ? .detailOnly : .all }, set: { _ in })
    }

    /// Drives the view-mode picker. While reading, the layout is forced to three-pane (the reader
    /// lives in its detail pane), so the picker reflects .threePane; picking Card/Item then closes
    /// the reader and switches to that view. Outside reading it's just the stored `mode`.
    private var modeSelection: Binding<LibraryViewMode> {
        Binding(
            get: { vm.readingPaperID != nil ? .threePane : mode },
            set: { newMode in
                if vm.readingPaperID != nil { vm.closeReader() }
                mode = newMode
            }
        )
    }

    private func openSelectedReader() {
        if let id = vm.currentPaperID, let paper = vm.papers.first(where: { $0.id == id }) {
            vm.openReader(paper)
        }
    }

    var body: some View {
        // StatusBar is a dedicated bottom row (not a `.safeAreaInset`): the inset didn't
        // reliably reserve space inside the detail column's scroll view, so the translucent
        // bar overlapped the last paper row. As a real VStack row it always spans its own
        // space, full width, without occluding content.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if vm.readingPaperID != nil {
                    ReadingRail()
                        .environmentObject(vm)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                splitView
            }
            // No implicit animation here: animating the whole NavigationSplitView subtree is
            // what made open/close laggy. Structural changes (rail/sidebar/list width) are now
            // instant; only the detail-pane content swap fades, scoped locally in ThreePaneView.
            Divider()
            StatusBar()
        }
    }

    @ViewBuilder private var splitView: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    Label("Papers", systemImage: "doc.text").tag(AppSection.papers)
                    Label("Links", systemImage: "link").tag(AppSection.links)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .padding(8)
                Divider()
                if section == .papers {
                    SidebarView().environmentObject(vm)
                } else {
                    LinkSidebarView().environmentObject(linksVM)
                }
            }
            .frame(minWidth: 200)
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
    }

    @ViewBuilder private var detail: some View {
        if section == .links {
            LinksView().environmentObject(linksVM)
        } else {
            papersDetail
        }
    }

    @ViewBuilder private var papersDetail: some View {
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
                case .mindmap: MindmapView()
                }
            }
        }
        .environmentObject(vm)
        .navigationTitle(vm.scopeTitle)
        // Gallery/Rows use the toolbar search. Three-pane hosts its own search atop the paper-list
        // column, and mindmap has its own paper-shelf search — so neither uses the toolbar one.
        // (Reading also uses three-pane.)
        .modifier(OptionalSearchable(active: vm.readingPaperID == nil && mode != .threePane && mode != .mindmap,
                                     text: $vm.query, prompt: "Search papers, authors, DOI, tags"))
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
            // Library-navigation controls are noise while reading a paper (reading forces
            // the three-pane layout anyway) — show them only in browsing mode.
            if vm.readingPaperID == nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: modeSelection) {
                        ForEach(LibraryViewMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Picker("Sort", selection: $vm.sort) {
                        ForEach(LibraryViewModel.SortMode.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            ToolbarItem {
                Menu {
                    Button("Import PDF…") {
                        for url in PDFPicker.pick(allowsMultiple: true, message: "Choose PDF(s) to add to your library") {
                            vm.importPDF(at: url)
                        }
                    }
                    Divider()
                    Button("Download all PDFs") { Task { await vm.downloadAllPDFs() } }
                    Button("Load missing figures & PDFs") { vm.retryAllIncomplete() }
                    Button("Re-fetch all figures") { vm.refetchAllFigures() }
                    Button("Regenerate figures from PDF") { vm.regenerateFiguresFromPDF() }
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
