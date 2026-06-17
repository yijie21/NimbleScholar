import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// Transient drag state shared with the canvas overlay (the dragged node + its current
/// canvas-space point), so the canvas can draw a drop indicator while the node moves locally.
struct NodeDragInfo: Equatable { var nodeID: Int64; var canvasPoint: CGPoint }

/// One tree node card: selectable, inline-editable, collapsible, drag-to-reparent, with attached
/// paper chips. Equatable so moving/selecting one node doesn't re-render its siblings.
struct NodeView: View, Equatable {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    let node: MindmapNode
    let size: CGSize
    let selected: Bool
    let editing: Bool
    let paperIDs: [Int64]
    let hasChildren: Bool
    @Binding var dragInfo: NodeDragInfo?
    let coordSpace: String

    @GestureState private var dragOffset: CGSize = .zero
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var dropTargeted = false

    private var nodeID: Int64 { node.id ?? -1 }

    static func == (l: NodeView, r: NodeView) -> Bool {
        l.node == r.node && l.size == r.size && l.selected == r.selected
            && l.editing == r.editing && l.paperIDs == r.paperIDs && l.hasChildren == r.hasChildren
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
                if hasChildren {
                    Button { vm.toggleCollapse(nodeID) } label: {
                        Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                if editing {
                    TextField("Idea", text: $draft)
                        .textFieldStyle(.plain).font(.callout.bold())
                        .focused($fieldFocused)
                        .onSubmit { vm.commitEdit(draft) }
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: fieldFocused) { _, focused in if !focused { vm.commitEdit(draft) } }
                        .onAppear { draft = node.text; fieldFocused = true }
                } else {
                    Text(node.text.isEmpty ? "Untitled" : node.text)
                        .font(.callout.bold())
                        .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
                }
            }
            ForEach(attachedPapers) { p in
                NodePaperChip(paper: p,
                              onOpen: { libraryVM.openReader(p) },
                              onRemove: { if let pid = p.id { vm.detach(pid, from: nodeID) } })
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
        .gesture(reparentGesture)
        .onTapGesture(count: 2) { vm.beginEdit(nodeID) }
        .onTapGesture { vm.select(nodeID) }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let pid = Int64(s) else { return false }
            vm.attach(pid, to: nodeID); return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Add Child") { vm.addChild(to: nodeID) }
            if nodeID != vm.rootID { Button("Add Sibling") { vm.addSibling(of: nodeID) } }
            Button("Rename") { vm.beginEdit(nodeID) }
            if hasChildren {
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

    /// Drag the node body to re-parent. Moves locally (no model write) and reports its canvas
    /// point to the overlay; commits the reparent only on release.
    private var reparentGesture: some Gesture {
        DragGesture(coordinateSpace: .named(coordSpace))
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onChanged { value in
                guard let rootID = vm.rootID, nodeID != rootID else { return }
                dragInfo = NodeDragInfo(nodeID: nodeID, canvasPoint: vm.transform.canvas(from: value.location))
            }
            .onEnded { value in
                defer { dragInfo = nil }
                guard let rootID = vm.rootID, nodeID != rootID else { return }
                let p = vm.transform.canvas(from: value.location)
                if let target = vm.dropTarget(forDragged: nodeID, at: p) {
                    vm.reparent(nodeID, to: target.parentID, index: target.index)
                }
            }
    }
}

/// A compact paper attached to a node. Click opens it in the reader; hover reveals remove.
struct NodePaperChip: View {
    let paper: Paper
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
            Text(paper.title).font(.caption2).lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.12)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
        .help(paper.title)
    }
}
