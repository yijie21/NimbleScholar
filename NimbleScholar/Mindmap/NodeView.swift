import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// One node card: editable text + attached paper chips. Drag the body to move it
/// (debounced persist); drag the trailing handle to another node to connect; drop a
/// paper to attach; right-click to edit/delete.
struct NodeView: View {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    let node: MindmapNode
    @Binding var connectFrom: Int64?
    @Binding var connectCursor: CGPoint?
    let coordSpace: String

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var dragBase: CGPoint?
    @State private var hovering = false
    @State private var dropTargeted = false

    private var nodeID: Int64 { node.id ?? -1 }

    private var attachedPapers: [Paper] {
        let ids = vm.graph.paperIDsByNode[nodeID] ?? []
        let byID = Dictionary(uniqueKeysWithValues: libraryVM.papers.compactMap { p in p.id.map { ($0, p) } })
        return ids.map { id in
            byID[id] ?? ((try? AppEnvironment.shared.store.paper(id: id)) ?? nil) ?? Paper(title: "Paper #\(id)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing {
                TextField("Idea", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.callout.bold())
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .onAppear { draft = node.text; focused = true }
            } else {
                Text(node.text.isEmpty ? "Untitled" : node.text)
                    .font(.callout.bold())
                    .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
            }
            if !attachedPapers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(attachedPapers) { p in
                        NodePaperChip(
                            paper: p,
                            onOpen: { libraryVM.openReader(p) },
                            onRemove: { if let pid = p.id { vm.detach(pid, from: nodeID) } }
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropTargeted ? Color.accentColor : .black.opacity(0.12),
                              lineWidth: dropTargeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .overlay(alignment: .trailing) { connectHandle }
        .onHover { hovering = $0 }
        .gesture(moveGesture)
        .onTapGesture(count: 2) { startEditing() }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let pid = Int64(s) else { return false }
            vm.attach(pid, to: nodeID)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Edit Text") { startEditing() }
            Button("Delete Node", role: .destructive) { vm.deleteNode(nodeID) }
        }
    }

    private func startEditing() { draft = node.text; editing = true }

    private func commit() {
        guard editing else { return }
        editing = false
        vm.setNodeText(nodeID, draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Drag the card body to move the node. Translation is screen-space; divide by zoom
    /// to convert to canvas units.
    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragBase == nil { dragBase = CGPoint(x: node.x, y: node.y) }
                let base = dragBase ?? CGPoint(x: node.x, y: node.y)
                vm.moveNode(nodeID, to: CGPoint(
                    x: base.x + value.translation.width / vm.transform.zoom,
                    y: base.y + value.translation.height / vm.transform.zoom))
            }
            .onEnded { _ in dragBase = nil; vm.flushMoves() }
    }

    /// Trailing dot: drag from here to another node to connect them.
    private var connectHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .opacity(hovering || connectFrom == nodeID ? 1 : 0.25)
            .offset(x: 6)
            .gesture(
                DragGesture(coordinateSpace: .named(coordSpace))
                    .onChanged { value in
                        connectFrom = nodeID
                        connectCursor = value.location
                    }
                    .onEnded { value in
                        defer { connectFrom = nil; connectCursor = nil }
                        if let target = vm.nodeID(at: value.location, transform: vm.transform),
                           target != nodeID {
                            vm.connect(nodeID, target)
                        }
                    }
            )
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
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.12)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
        .help(paper.title)
    }
}
