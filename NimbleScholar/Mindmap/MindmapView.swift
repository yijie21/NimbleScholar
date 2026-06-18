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
            KeyboardHintsButton()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// A small keyboard-key chip (e.g. `Tab`, `␣`, `↩`) used in the shortcuts legend.
struct KeyCap: View {
    var text: String? = nil
    var systemImage: String? = nil
    var body: some View {
        Group {
            if let systemImage { Image(systemName: systemImage) }
            else if let text { Text(text) }
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .frame(minWidth: 16, minHeight: 16)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.18)))
        .foregroundStyle(.primary)
    }
}

/// Replaces the plain shortcut text on the toolbar with a help button whose popover shows an
/// illustrated legend — key chips paired with the matching action icon — to match the app's
/// iconographic style instead of a sentence of text.
struct KeyboardHintsButton: View {
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Label("Shortcuts", systemImage: "questionmark.circle")
        }
        .help("Keyboard & mouse shortcuts")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shortcuts").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    row(icon: "arrow.turn.down.right", label: "Add child") { KeyCap(text: "Tab") }
                    row(icon: "arrow.down", label: "Add sibling") { KeyCap(systemImage: "return") }
                    row(icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Move selection") {
                        KeyCap(systemImage: "arrow.up")
                        KeyCap(systemImage: "arrow.down")
                        KeyCap(systemImage: "arrow.left")
                        KeyCap(systemImage: "arrow.right")
                    }
                    row(icon: "rectangle.compress.vertical", label: "Collapse / expand") { KeyCap(text: "Space") }
                    row(icon: "trash", label: "Delete node") { KeyCap(systemImage: "delete.left") }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    row(icon: "pencil", label: "Edit text") { KeyCap(systemImage: "cursorarrow.click.2") }
                    row(icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Move / reparent") {
                        KeyCap(systemImage: "hand.draw")
                    }
                }
            }
            .padding(18)
            .frame(width: 320)
        }
    }

    @ViewBuilder
    private func row<K: View>(icon: String, label: String, @ViewBuilder keys: () -> K) -> some View {
        GridRow {
            HStack(spacing: 4) { keys() }
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(label).font(.callout)
        }
    }
}
