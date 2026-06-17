import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// Transient drag state shared with the canvas (the dragged node, its live canvas center, and the
/// current re-parent target). The connectors layer reads `center` so edges follow the drag in real
/// time; the drop indicator reads `target`.
struct NodeDragInfo: Equatable {
    var nodeID: Int64
    var center: CGPoint
    var target: MindmapViewModel.DropTarget?
}

/// One tree node card: selectable, inline-editable, collapsible, drag-to-reparent, with attached
/// paper chips. Equatable so moving/selecting one node doesn't re-render its siblings.
struct NodeView: View, Equatable {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    let node: MindmapNode
    let size: CGSize
    let selected: Bool
    let editingField: NodeField?
    let paperIDs: [Int64]
    let canCollapse: Bool
    @Binding var dragInfo: NodeDragInfo?
    let coordSpace: String

    @GestureState private var dragOffset: CGSize = .zero
    @State private var draft = ""
    @State private var contentDraft = ""
    @FocusState private var headingFocused: Bool
    @FocusState private var contentFocused: Bool
    @State private var dropTargeted = false

    private let reparentThreshold: CGFloat = 24   // min drag distance (screen pts) to re-parent
    private var nodeID: Int64 { node.id ?? -1 }
    private var isEditingHeading: Bool { editingField == .heading }
    private var isEditingContent: Bool { editingField == .content }

    static func == (l: NodeView, r: NodeView) -> Bool {
        l.node == r.node && l.size == r.size && l.selected == r.selected
            && l.editingField == r.editingField && l.paperIDs == r.paperIDs && l.canCollapse == r.canCollapse
    }

    private var attachedPapers: [Paper] {
        let byID = Dictionary(uniqueKeysWithValues: libraryVM.papers.compactMap { p in p.id.map { ($0, p) } })
        return paperIDs.map { id in
            byID[id] ?? ((try? AppEnvironment.shared.store.paper(id: id)) ?? nil) ?? Paper(title: "Paper #\(id)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if canCollapse {
                    Button { vm.toggleCollapse(nodeID) } label: {
                        Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                            .font(.callout).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                if isEditingHeading {
                    TextField("Idea", text: $draft)
                        .textFieldStyle(.plain).font(.title.bold())
                        .focused($headingFocused)
                        .onSubmit { vm.commitHeading(draft) }
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: headingFocused) { _, f in if !f { vm.commitHeading(draft) } }
                        .onAppear { draft = node.text; headingFocused = true }
                } else {
                    Text(node.text.isEmpty ? "Untitled" : node.text)
                        .font(.title.bold())
                        .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
                        .onTapGesture(count: 2) { vm.beginEdit(nodeID) }
                }
            }
            if !node.collapsed {
                if isEditingContent {
                    TextField("Note", text: $contentDraft, axis: .vertical)
                        .textFieldStyle(.plain).font(.title3)
                        .focused($contentFocused)
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: contentFocused) { _, f in if !f { vm.commitContent(contentDraft) } }
                        .onAppear { contentDraft = node.content; contentFocused = true }
                } else {
                    Text(node.content.isEmpty ? "Add note…" : node.content)
                        .font(.title3)
                        .foregroundStyle(node.content.isEmpty ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { vm.beginEditContent(nodeID) }
                }
                ForEach(attachedPapers) { p in
                    NodePaperChip(paper: p,
                                  onOpen: { libraryVM.openReader(p) },
                                  onRemove: { if let pid = p.id { vm.detach(pid, from: nodeID) } })
                }
            }
        }
        .padding(10)
        .frame(width: size.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: selected || dropTargeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .offset(dragOffset)
        .gesture(moveOrReparentGesture)
        .onTapGesture { vm.select(nodeID) }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let pid = Int64(s) else { return false }
            vm.attach(pid, to: nodeID); return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Add Child") { vm.addChild(to: nodeID) }
            if nodeID != vm.rootID { Button("Add Sibling") { vm.addSibling(of: nodeID) } }
            Button("Edit Heading") { vm.beginEdit(nodeID) }
            Button("Edit Note") { vm.beginEditContent(nodeID) }
            if canCollapse {
                Button(node.collapsed ? "Expand" : "Collapse") { vm.toggleCollapse(nodeID) }
            }
            if nodeID != vm.rootID {
                Divider()
                Button("Move Up") { vm.reorder(nodeID, before: true) }
                Button("Move Down") { vm.reorder(nodeID, before: false) }
                Divider()
                Button("Delete", role: .destructive) { vm.deleteSubtree(nodeID) }
            }
        }
    }

    private var borderColor: Color {
        if dropTargeted { return .accentColor }
        return selected ? .accentColor : .black.opacity(0.12)
    }

    /// Drag the node body to MOVE it, or to RE-PARENT it (when released over another node).
    /// Moves locally during the drag (no model write); commits move-or-reparent on release.
    private var moveOrReparentGesture: some Gesture {
        DragGesture(coordinateSpace: .named(coordSpace))
            .updating($dragOffset) { value, state, _ in
                // The node is rendered inside the canvas's .scaleEffect(zoom); divide by zoom so this
                // local offset scales back up to the actual screen drag distance.
                let z = vm.transform.zoom
                state = CGSize(width: value.translation.width / z, height: value.translation.height / z)
            }
            .onChanged { value in
                let zoom = vm.transform.zoom
                let old = vm.layout[nodeID] ?? .zero
                let center = CGPoint(x: old.x + value.translation.width / zoom,
                                     y: old.y + value.translation.height / zoom)
                let dragged = hypot(value.translation.width, value.translation.height)
                let cursor = vm.transform.canvas(from: value.location)
                let target: MindmapViewModel.DropTarget? =
                    (dragged >= reparentThreshold && nodeID != vm.rootID)
                    ? vm.dropTarget(forDragged: nodeID, at: cursor) : nil
                dragInfo = NodeDragInfo(nodeID: nodeID, center: center, target: target)
            }
            .onEnded { value in
                defer { dragInfo = nil }
                let zoom = vm.transform.zoom
                let old = vm.layout[nodeID] ?? .zero
                // New position preserves the grab offset (move by the drag delta in canvas units).
                let dropPoint = CGPoint(x: old.x + value.translation.width / zoom,
                                        y: old.y + value.translation.height / zoom)
                let dragged = hypot(value.translation.width, value.translation.height)
                let cursor = vm.transform.canvas(from: value.location)
                if dragged >= reparentThreshold, nodeID != vm.rootID, let target = vm.dropTarget(forDragged: nodeID, at: cursor) {
                    vm.reparent(nodeID, to: target.parentID, index: target.index, at: dropPoint)
                } else {
                    vm.move(nodeID, to: dropPoint)
                }
            }
    }
}

/// A paper attached to a node, shown as a small card with its figure so it's recognizable at a
/// glance. Click opens it in the reader; hover reveals the remove button.
struct NodePaperChip: View {
    let paper: Paper
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .overlay(PaperThumbnail(paper: paper))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
            Text(paper.title).font(.caption).bold().lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !paper.authors.isEmpty {
                Text(paper.authors).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
        .help(paper.title)
    }
}
