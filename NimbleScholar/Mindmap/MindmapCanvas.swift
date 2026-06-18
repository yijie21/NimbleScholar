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
    @State private var didFitMapID: Int64?
    @FocusState private var focus: MindmapFocus?

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
            .focused($focus, equals: .canvas)
            .focusEffectDisabled()
            .onAppear { focus = .canvas }
            // Drive keyboard focus from the edit state: entering edit focuses that node's field;
            // leaving edit returns focus to the canvas (so arrow keys / Tab work again).
            .onChange(of: vm.editing) { _, editing in
                if let e = editing {
                    focus = (e.field == .heading) ? .heading(e.nodeID) : .content(e.nodeID)
                } else {
                    focus = .canvas
                }
            }
            .onChange(of: vm.activeMapID, initial: true) { _, _ in didFitMapID = nil; fitIfNeeded(geo.size) }
            .onChange(of: vm.layout) { _, _ in fitIfNeeded(geo.size) }
            .overlay(alignment: .bottomTrailing) { zoomControls(viewport: geo.size) }
            .background(keyShortcuts)
            .simultaneousGesture(magnifyGesture)
            .onKeyPress(.tab) { guard vm.editing == nil else { return .ignored }; vm.addChildToSelected(); return .handled }
            .onKeyPress(.return) { if vm.editing == nil { vm.addSiblingToSelected(); return .handled }; return .ignored }
            .onKeyPress(.deleteForward) { guard vm.editing == nil else { return .ignored }; vm.deleteSelectedSubtree(); return .handled }
            .onKeyPress(KeyEquivalent("\u{7f}")) { guard vm.editing == nil else { return .ignored }; vm.deleteSelectedSubtree(); return .handled }   // Backspace
            .onKeyPress(.space) { guard vm.editing == nil else { return .ignored }; if let s = vm.selectedNodeID { vm.toggleCollapse(s) }; return .handled }
            .onKeyPress(.upArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.up); return .handled }
            .onKeyPress(.downArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.down); return .handled }
            .onKeyPress(.leftArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.left); return .handled }
            .onKeyPress(.rightArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.right); return .handled }
        }
    }

    /// Frame the tree once per map open (when its layout is ready), so a map doesn't open
    /// stuck in the top-left corner. Guarded so it never fights the user's pan/zoom afterward.
    private func fitIfNeeded(_ size: CGSize) {
        guard size.width > 0, let mapID = vm.activeMapID, !vm.layout.isEmpty, didFitMapID != mapID else { return }
        didFitMapID = mapID
        vm.fit(in: size)
    }

    // MARK: Background (pan)

    private var background: some View {
        Color(nsColor: .textBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { vm.commitActiveEdit(); focus = .canvas }   // click empty space: save edit, take focus
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
            // Capture main-actor state into locals (a nested func wouldn't inherit @MainActor).
            // The dragged node uses its live center so its edges follow the drag.
            let drag = dragInfo
            let layout = vm.layout
            let zoom = vm.transform.zoom
            for n in vm.tree.nodes {
                guard let nid = n.id, let pid = n.parentID else { continue }
                let cc = (drag?.nodeID == nid) ? drag?.center : layout[nid]
                let pc = (drag?.nodeID == pid) ? drag?.center : layout[pid]
                guard let cc, let pc else { continue }
                let p1 = vm.transform.screen(from: pc)   // parent
                let p2 = vm.transform.screen(from: cc)   // child
                // Orthogonal "elbow": horizontal out of the parent → vertical at the mid-x →
                // horizontal into the child, with rounded (filleted) corners at the two bends.
                let midX = (p1.x + p2.x) / 2
                let dirX: CGFloat = p2.x >= p1.x ? 1 : -1
                let dirY: CGFloat = p2.y >= p1.y ? 1 : -1
                let r = max(0, min(12 * zoom, abs(midX - p1.x), abs(p2.y - p1.y) / 2))
                var path = Path()
                path.move(to: p1)
                path.addLine(to: CGPoint(x: midX - dirX * r, y: p1.y))
                path.addQuadCurve(to: CGPoint(x: midX, y: p1.y + dirY * r), control: CGPoint(x: midX, y: p1.y))
                path.addLine(to: CGPoint(x: midX, y: p2.y - dirY * r))
                path.addQuadCurve(to: CGPoint(x: midX + dirX * r, y: p2.y), control: CGPoint(x: midX, y: p2.y))
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(.secondary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5 * zoom, lineCap: .round, lineJoin: .round))
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
            let editField: NodeField? = vm.editing.flatMap { $0.nodeID == nid ? $0.field : nil }
            NodeView(node: n,
                     size: vm.sizes[nid] ?? CGSize(width: 200, height: 40),
                     selected: vm.selectedNodeID == nid,
                     editingField: editField,
                     paperIDs: vm.tree.paperIDsByNode[nid] ?? [],
                     canCollapse: vm.canCollapse(nid),
                     dragInfo: $dragInfo,
                     coordSpace: coordSpace,
                     focus: $focus)
                .equatable()
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .scaleEffect(vm.transform.zoom)   // true zoom: the node + its content scale, not just spacing
                .position(vm.transform.screen(from: vm.layout[nid] ?? .zero))
        }
    }

    // MARK: Interactive overlay — drop indicator

    @ViewBuilder private var dropIndicator: some View {
        if let info = dragInfo, let target = info.target,
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
