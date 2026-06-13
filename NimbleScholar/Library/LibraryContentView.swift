import SwiftUI
import NimbleScholarCore

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
    @StateObject private var vm = LibraryViewModel()
    @AppStorage("libraryViewMode") private var mode: LibraryViewMode = .threePane
    @State private var editing: Paper?
    @State private var capturing = false

    var body: some View {
        NavigationSplitView {
            SidebarView().environmentObject(vm).frame(minWidth: 200)
        } detail: {
            detail
        }
        .task { vm.reload() }
        .sheet(item: $editing) { PaperEditSheet(paper: $0).environmentObject(vm) }
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
        .navigationTitle(vm.selectedTag ?? "All papers")
        .searchable(text: $vm.query, prompt: "Search papers, authors, DOI, tags")
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
                Button { capturing = true } label: { Label("Capture", systemImage: "link.badge.plus") }
            }
            ToolbarItem {
                Button { editing = Paper(title: "") } label: { Label("Add", systemImage: "plus") }
            }
        }
    }
}
