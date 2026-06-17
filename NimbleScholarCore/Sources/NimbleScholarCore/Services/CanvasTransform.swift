import CoreGraphics

/// Pure canvas↔screen coordinate math for the mindmap canvas. `screen = canvas * zoom + pan`.
/// Kept in Core (no UI) so pan/zoom/cull logic is unit-tested.
public struct CanvasTransform: Equatable {
    public var zoom: CGFloat
    public var pan: CGSize

    public init(zoom: CGFloat = 1, pan: CGSize = .zero) {
        self.zoom = zoom
        self.pan = pan
    }

    public static let minZoom: CGFloat = 0.25
    public static let maxZoom: CGFloat = 2.5

    public static func clampZoom(_ z: CGFloat) -> CGFloat {
        min(maxZoom, max(minZoom, z))
    }

    /// Canvas point → screen point.
    public func screen(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(x: canvasPoint.x * zoom + pan.width,
                y: canvasPoint.y * zoom + pan.height)
    }

    /// Screen point → canvas point (inverse of `screen(from:)`).
    public func canvas(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: (screenPoint.x - pan.width) / zoom,
                y: (screenPoint.y - pan.height) / zoom)
    }

    /// Is a canvas-space rect within the screen-space `viewport` (expanded by `margin`)?
    public func isVisible(canvasRect: CGRect, in viewport: CGRect, margin: CGFloat = 200) -> Bool {
        let origin = screen(from: canvasRect.origin)
        let screenRect = CGRect(x: origin.x, y: origin.y,
                                width: canvasRect.width * zoom,
                                height: canvasRect.height * zoom)
        return screenRect.insetBy(dx: -margin, dy: -margin).intersects(viewport)
    }
}
