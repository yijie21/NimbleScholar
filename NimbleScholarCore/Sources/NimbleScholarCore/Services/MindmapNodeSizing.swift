import CoreGraphics

/// Pure node-size estimate for the tree layout (real text measurement is a later refinement).
/// Fixed width. Collapsed → heading height only; expanded → heading + content lines + chips.
public enum MindmapNodeSizing {
    public static let width: CGFloat = 300
    private static let charsPerLine = 16
    private static let lineHeight: CGFloat = 32
    private static let verticalPadding: CGFloat = 24
    private static let chipHeight: CGFloat = 130   // each attached paper renders as a figure card

    private static func lines(_ s: String) -> Int {
        max(1, Int((Double(s.count) / Double(charsPerLine)).rounded(.up)))
    }

    public static func size(heading: String, content: String, chipCount: Int, collapsed: Bool) -> CGSize {
        var height = CGFloat(lines(heading)) * lineHeight + verticalPadding
        if !collapsed {
            if !content.isEmpty { height += CGFloat(lines(content)) * lineHeight + 4 }
            height += CGFloat(max(0, chipCount)) * chipHeight
        }
        return CGSize(width: width, height: height)
    }
}
