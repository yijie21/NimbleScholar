import CoreGraphics

/// Pure node-size estimate for tree layout (real text measurement is a later refinement).
/// Fixed width; height grows with estimated wrapped text lines + attached-paper chips.
public enum MindmapNodeSizing {
    public static let width: CGFloat = 200
    private static let charsPerLine = 22
    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 18
    private static let chipHeight: CGFloat = 22

    public static func size(text: String, chipCount: Int) -> CGSize {
        let lines = max(1, Int((Double(text.count) / Double(charsPerLine)).rounded(.up)))
        let textHeight = CGFloat(lines) * lineHeight + verticalPadding
        let chipsHeight = CGFloat(max(0, chipCount)) * chipHeight
        return CGSize(width: width, height: textHeight + chipsHeight)
    }
}
