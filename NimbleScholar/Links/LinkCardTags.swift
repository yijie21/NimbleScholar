import SwiftUI
import NimbleScholarCore

/// Inline tag editor shown on each link card: removable tag chips plus a "+ tag" field, so tags can
/// be assigned directly on the card (like the paper detail page) without opening a sheet. Changes
/// apply immediately through the view model.
struct LinkCardTags: View {
    @EnvironmentObject var vm: LinksViewModel
    let link: SavedLink
    @State private var newTag = ""

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(vm.tags(for: link), id: \.self) { t in
                HStack(spacing: 3) {
                    Circle().fill(TagColor.color(for: t)).frame(width: 5, height: 5)
                    Text(t).font(.caption2)
                    Button { vm.removeTag(t, from: link) } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
            }
            HStack(spacing: 2) {
                Image(systemName: "plus").font(.system(size: 8)).foregroundStyle(.secondary)
                TextField("tag", text: $newTag)
                    .textFieldStyle(.plain).font(.caption2).frame(width: 46)
                    .onSubmit { commit() }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().strokeBorder(.quaternary, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .onTapGesture { }   // swallow taps here so editing tags doesn't open the link
    }

    private func commit() {
        for part in newTag.split(separator: ",") {
            let n = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { vm.addTag(n, to: link) }   // immediate + normalized by the store
        }
        newTag = ""
    }
}

/// A simple wrapping layout (chips flow onto new lines as width runs out).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth == .infinity ? max(0, x - spacing) : maxWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
