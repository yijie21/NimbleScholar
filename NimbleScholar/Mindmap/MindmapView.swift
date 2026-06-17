import SwiftUI
import NimbleScholarCore

/// The 4th library view mode: a narrow paper shelf beside the map bar + canvas.
struct MindmapView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @StateObject private var vm = MindmapViewModel()
    @State private var previewPaper: Paper?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                PaperShelf(previewPaper: $previewPaper)
                    .environmentObject(vm)
                    .environmentObject(libraryVM)
                    .frame(width: 250)
                Divider()
                VStack(spacing: 0) {
                    MapBar().environmentObject(vm)
                    Divider()
                    if vm.activeMapID == nil {
                        MindmapEmptyState().environmentObject(vm)
                    } else {
                        CanvasToolbar().environmentObject(vm)
                        Divider()
                        MindmapCanvas()
                            .environmentObject(vm)
                            .environmentObject(libraryVM)
                    }
                }
            }
            if let p = previewPaper {
                FigurePreviewOverlay(paper: p) { previewPaper = nil }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: previewPaper)
    }
}

/// Shown when no map exists/selected — one button to create the first map.
struct MindmapEmptyState: View {
    @EnvironmentObject var vm: MindmapViewModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No mindmap yet").font(.headline)
            Text("Create a map for a research idea, then drag papers onto its nodes.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { vm.createMap(name: "Untitled idea") } label: {
                Label("New mindmap", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Guaranteed-usable mirror of the keyboard ops (in case a key is captured by the system).
struct CanvasToolbar: View {
    @EnvironmentObject var vm: MindmapViewModel
    private var hasSelection: Bool { vm.selectedNodeID != nil }
    private var selectionIsRoot: Bool { vm.selectedNodeID == vm.rootID }

    var body: some View {
        HStack(spacing: 10) {
            Button { vm.addChildToSelected() } label: { Label("Child", systemImage: "arrow.turn.down.right") }
                .disabled(!hasSelection)
            Button { vm.addSiblingToSelected() } label: { Label("Sibling", systemImage: "arrow.down") }
                .disabled(!hasSelection || selectionIsRoot)
            Button { vm.deleteSelectedSubtree() } label: { Label("Delete", systemImage: "trash") }
                .disabled(!hasSelection || selectionIsRoot)
            Button { if let s = vm.selectedNodeID { vm.toggleCollapse(s) } } label: { Label("Collapse", systemImage: "rectangle.compress.vertical") }
                .disabled(!hasSelection)
            Button { vm.tidy() } label: { Label("Tidy", systemImage: "wand.and.stars") }
                .disabled(vm.rootID == nil)
            Divider().frame(height: 16)
            Button { vm.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!vm.canUndo)
            Button { vm.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!vm.canRedo)
            Spacer()
            Text("Tab: child · Return: sibling · arrows: move · Space: collapse")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
