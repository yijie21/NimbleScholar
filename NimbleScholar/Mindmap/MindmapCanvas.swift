import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// The tree canvas: a committed layer (parent→child connectors in one Canvas pass + viewport-
/// culled NodeViews placed by TreeLayout) and an interactive overlay (drop indicator). Pan =
/// drag background; zoom = pinch / +- ; Fit frames the tree. Keyboard ops act on the selection.
struct MindmapCanvas: View {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    @State private var panBase: CGSize?
    @State private var zoomBase: CGFloat?
    @State private var dragInfo: NodeDragInfo?
    @FocusState private var focused: Bool

    private let coordSpace = "mindmapTreeCanvas"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                connectors
                nodes(in: geo.size)
                dropIndicator
            }
            .coordinateSpace(name: coordSpace)
            .clipped()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onChange(of: vm.editingNodeID) { _, editing in if editing == nil { focused = true } }
            .overlay(alignment: .bottomTrailing) { zoomControls(viewport: geo.size) }
            .background(keyShortcuts)
            .simultaneousGesture(magnifyGesture)
            .onKeyPress(.tab) { vm.addChildToSelected(); return .handled }
            .onKeyPress(.return) { if vm.editingNodeID == nil { vm.addSiblingToSelected(); return .handled }; return .ignored }
            .onKeyPress(.deleteForward) { vm.deleteSelectedSubtree(); return .handled }
            .onKeyPress(KeyEquivalent("\u{7f}")) { vm.deleteSelectedSubtree(); return .handled }   // Backspace
            .onKeyPress(.space) { if let s = vm.selectedNodeID { vm.toggleCollapse(s) }; return .handled }
            .onKeyPress(.upArrow) { vm.navigate(.up); return .handled }
            .onKeyPress(.downArrow) { vm.navigate(.down); return .handled }
            .onKeyPress(.leftArrow) { vm.navigate(.left); return .handled }
            .onKeyPress(.rightArrow) { vm.navigate(.right); return .handled }
        }
    }

    // MARK: Background (pan)

    private var background: some View {
        Color(nsColor: .textBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .gesture(panGesture)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if panBase == nil { panBase = vm.transform.pan }
                var t = vm.transform
                t.pan = CGSize(width: (panBase?.width ?? 0) + value.translation.width,
                               height: (panBase?.height ?? 0) + value.translation.height)
                vm.transform = t
            }
            .onEnded { _ in panBase = nil; vm.updateTransform(vm.transform) }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomBase == nil { zoomBase = vm.transform.zoom }
                var t = vm.transform
                t.zoom = CanvasTransform.clampZoom((zoomBase ?? 1) * value.magnification)
                vm.transform = t
            }
            .onEnded { _ in zoomBase = nil; vm.updateTransform(vm.transform) }
    }

    // MARK: Committed layer — connectors + nodes

    private var connectors: some View {
        Canvas { ctx, _ in
            for n in vm.tree.nodes {
                guard let nid = n.id, let pid = n.parentID,
                      let cc = vm.layout[nid], let pc = vm.layout[pid] else { continue }
                let p1 = vm.transform.screen(from: pc)
                let p2 = vm.transform.screen(from: cc)
                var path = Path()
                path.move(to: p1)
                let midX = (p1.x + p2.x) / 2
                path.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
                ctx.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func nodes(in size: CGSize) -> some View {
        let viewport = CGRect(origin: .zero, size: size)
        let visible = vm.tree.nodes.filter { n in
            guard let nid = n.id, let c = vm.layout[nid], let sz = vm.sizes[nid] else { return false }
            let rect = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
            return vm.transform.isVisible(canvasRect: rect, in: viewport)
        }
        return ForEach(visible) { n in
            let nid = n.id ?? -1
            NodeView(node: n,
                     size: vm.sizes[nid] ?? CGSize(width: 200, height: 40),
                     selected: vm.selectedNodeID == nid,
                     editing: vm.editingNodeID == nid,
                     paperIDs: vm.tree.paperIDsByNode[nid] ?? [],
                     hasChildren: !vm.tree.children(of: nid).isEmpty,
                     dragInfo: $dragInfo,
                     coordSpace: coordSpace)
                .equatable()
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .position(vm.transform.screen(from: vm.layout[nid] ?? .zero))
        }
    }

    // MARK: Interactive overlay — drop indicator

    @ViewBuilder private var dropIndicator: some View {
        if let info = dragInfo, let target = vm.dropTarget(forDragged: info.nodeID, at: info.canvasPoint),
           let c = vm.layout[target.parentID], let sz = vm.sizes[target.parentID] {
            let screen = vm.transform.screen(from: c)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                .frame(width: sz.width * vm.transform.zoom, height: sz.height * vm.transform.zoom)
                .position(screen)
                .allowsHitTesting(false)
        }
    }

    // MARK: Zoom controls + hidden command shortcuts

    private func zoomControls(viewport: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoomBy(1.2) } label: { Image(systemName: "plus") }
            Button { zoomBy(1 / 1.2) } label: { Image(systemName: "minus") }
            Button { vm.fit(in: viewport) } label: { Image(systemName: "scope") }
        }
        .buttonStyle(.bordered).padding(10)
    }

    private func zoomBy(_ factor: CGFloat) {
        var t = vm.transform
        t.zoom = CanvasTransform.clampZoom(t.zoom * factor)
        vm.updateTransform(t)
    }

    /// Hidden buttons carry the ⌘-modified shortcuts that `.onKeyPress` can't express cleanly.
    /// (Sibling reorder lives in the node context menu to avoid colliding with plain-arrow nav.)
    private var keyShortcuts: some View {
        Group {
            Button("") { vm.undo() }.keyboardShortcut("z", modifiers: [.command]).hidden()
            Button("") { vm.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).hidden()
        }
    }
}
