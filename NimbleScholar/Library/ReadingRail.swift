import SwiftUI
import NimbleScholarCore

/// A compact scope/tag rail shown in place of the sidebar while reading. Clicking a scope
/// or tag re-filters the paper list (which stays open) without leaving the reader. Tags
/// show their dot AND name — bare dots proved unreadable (which color is which tag?).
struct ReadingRail: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                scopeRow(.all, "tray.full", "All papers")
                scopeRow(.important, "star.fill", "Important", tint: .yellow)
                scopeRow(.unread, "circle.fill", "Unread")
                scopeRow(.recent, "clock", "Recently added")
                scopeRow(.untagged, "tag.slash", "Untagged")
                if !vm.tagCounts.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(vm.tagCounts, id: \.name) { tc in
                        tagRow(tc)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 160)
        .background(.bar)
    }

    @ViewBuilder
    private func scopeRow(_ scope: LibraryScope, _ icon: String, _ name: String, tint: Color? = nil) -> some View {
        Button { vm.scope = scope } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint ?? .primary)
                    .frame(width: 16)
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(vm.scope == scope ? Color.accentColor.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tagRow(_ tc: TagCount) -> some View {
        Button { vm.scope = .tag(tc.name) } label: {
            HStack(spacing: 6) {
                Circle().fill(TagColor.color(for: tc.name))
                    .frame(width: 8, height: 8)
                    .frame(width: 16)   // aligns dots with the scope icons above
                Text(tc.name).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(tc.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTag(tc.name) ? Color.accentColor.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(tc.name)
    }

    private func isTag(_ name: String) -> Bool {
        if case .tag(let t) = vm.scope { return t == name }
        return false
    }
}
