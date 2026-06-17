import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// The infinite canvas. Nodes are positioned via the view model's CanvasTransform;
/// edges are drawn in a single Canvas pass; nodes are viewport-culled. Pan = drag the
/// background; zoom = pinch or the +/- controls; double-tap empty space = new node;
/// drop a paper on empty space = new node pre-attached.
struct MindmapCanvas: View {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    @State private var panBase: CGSize?
    @State private var zoomBase: CGFloat?
    @State private var connectFrom: Int64?
    @State private var connectCursor: CGPoint?

    private let coordSpace = "mindmapCanvas"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                edgeLayer
                edgeDeleteHandles
                nodes(in: geo.size)
            }
            .coordinateSpace(name: coordSpace)
            .clipped()
            .overlay(alignment: .bottomTrailing) { zoomControls }
            .simultaneousGesture(magnifyGesture)
            .dropDestination(for: String.self) { items, location in
                guard let s = items.first, let pid = Int64(s) else { return false }
                vm.addNode(at: vm.transform.canvas(from: location), attaching: pid)
                return true
            }
        }
    }

    // MARK: Background (pan + create node)

    private var background: some View {
        Color(nsColor: .textBackgroundColor)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { e in vm.addNode(at: vm.transform.canvas(from: e.location)) }
            )
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

    // MARK: Edges

    private var edgeLayer: some View {
        Canvas { ctx, _ in
            let byID = nodeByID
            for edge in vm.graph.edges {
                guard let a = byID[edge.fromNodeID], let b = byID[edge.toNodeID] else { continue }
                var path = Path()
                path.move(to: vm.transform.screen(from: CGPoint(x: a.x, y: a.y)))
                path.addLine(to: vm.transform.screen(from: CGPoint(x: b.x, y: b.y)))
                ctx.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
            }
            if let from = connectFrom, let a = byID[from], let cursor = connectCursor {
                var path = Path()
                path.move(to: vm.transform.screen(from: CGPoint(x: a.x, y: a.y)))
                path.addLine(to: cursor)
                ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            }
        }
        .allowsHitTesting(false)
    }

    /// A small delete button at each edge midpoint (revealed on hover).
    private var edgeDeleteHandles: some View {
        let byID = nodeByID
        return ForEach(vm.graph.edges) { edge in
            if let a = byID[edge.fromNodeID], let b = byID[edge.toNodeID], let id = edge.id {
                let p1 = vm.transform.screen(from: CGPoint(x: a.x, y: a.y))
                let p2 = vm.transform.screen(from: CGPoint(x: b.x, y: b.y))
                EdgeDeleteHandle { vm.deleteEdge(id) }
                    .position(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            }
        }
    }

    // MARK: Nodes (culled)

    private func nodes(in size: CGSize) -> some View {
        let viewport = CGRect(origin: .zero, size: size)
        let visible = vm.graph.nodes.filter { n in
            // node footprint estimated in canvas units (constant screen size / zoom)
            let w = 220 / max(vm.transform.zoom, 0.01)
            let h = 160 / max(vm.transform.zoom, 0.01)
            let rect = CGRect(x: n.x - w/2, y: n.y - h/2, width: w, height: h)
            return vm.transform.isVisible(canvasRect: rect, in: viewport)
        }
        return ForEach(visible) { node in
            NodeView(node: node, connectFrom: $connectFrom, connectCursor: $connectCursor,
                     coordSpace: coordSpace)
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .position(vm.transform.screen(from: CGPoint(x: node.x, y: node.y)))
        }
    }

    private var nodeByID: [Int64: MindmapNode] {
        Dictionary(uniqueKeysWithValues: vm.graph.nodes.compactMap { n in n.id.map { ($0, n) } })
    }

    // MARK: Zoom controls

    private var zoomControls: some View {
        VStack(spacing: 4) {
            Button { zoomBy(1.2) } label: { Image(systemName: "plus") }
            Button { zoomBy(1 / 1.2) } label: { Image(systemName: "minus") }
            Button { resetView() } label: { Image(systemName: "scope") }
        }
        .buttonStyle(.bordered)
        .padding(10)
    }

    private func zoomBy(_ factor: CGFloat) {
        var t = vm.transform
        t.zoom = CanvasTransform.clampZoom(t.zoom * factor)
        vm.updateTransform(t)
    }

    private func resetView() {
        vm.updateTransform(CanvasTransform(zoom: 1, pan: .zero))
    }
}

/// Hover-revealed delete control sitting on an edge midpoint.
private struct EdgeDeleteHandle: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.body)
                .foregroundStyle(hovering ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.25)
        .onHover { hovering = $0 }
        .help("Delete connection")
    }
}
