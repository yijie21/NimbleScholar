import CoreGraphics

/// Pure tidy left-to-right logical-tree layout (Reingold–Tilford style): depth → x, and each
/// parent is vertically centered on its children's span. Collapsed nodes exclude their subtree.
/// Returns each visible node's CENTER point in canvas coordinates.
public struct TreeLayout {
    public struct Config {
        public var levelGapX: CGFloat
        public var siblingGapY: CGFloat
        public init(levelGapX: CGFloat = 60, siblingGapY: CGFloat = 16) {
            self.levelGapX = levelGapX; self.siblingGapY = siblingGapY
        }
    }

    public static func positions(
        rootID: Int64,
        childrenByParent: [Int64: [Int64]],
        collapsed: Set<Int64>,
        sizeOf: [Int64: CGSize],
        config: Config = .init()
    ) -> [Int64: CGPoint] {
        let columnWidth = (sizeOf.values.map { $0.width }.max() ?? 200)
        let columnStep = columnWidth + config.levelGapX

        var positions: [Int64: CGPoint] = [:]
        var cursorY: CGFloat = 0

        func assign(_ id: Int64, depth: Int) {
            let h = sizeOf[id]?.height ?? 40
            let centerX = CGFloat(depth) * columnStep + columnWidth / 2
            let kids = collapsed.contains(id) ? [] : (childrenByParent[id] ?? [])
            if kids.isEmpty {
                let centerY = cursorY + h / 2
                positions[id] = CGPoint(x: centerX, y: centerY)
                cursorY += h + config.siblingGapY
            } else {
                for kid in kids { assign(kid, depth: depth + 1) }
                let firstY = positions[kids.first!]?.y ?? cursorY
                let lastY = positions[kids.last!]?.y ?? cursorY
                positions[id] = CGPoint(x: centerX, y: (firstY + lastY) / 2)
            }
        }
        assign(rootID, depth: 0)
        return positions
    }
}
