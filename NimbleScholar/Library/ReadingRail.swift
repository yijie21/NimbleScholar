import SwiftUI
import NimbleScholarCore

/// A slim icon rail shown in place of the sidebar while reading. Clicking a scope sets
/// `vm.scope`, whose didSet exits the reader and shows that scope.
struct ReadingRail: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                scopeButton(.all, "tray.full", "All papers")
                scopeButton(.important, "star.fill", "Important", tint: .yellow)
                scopeButton(.unread, "circle.fill", "Unread")
                scopeButton(.recent, "clock", "Recently added")
                scopeButton(.untagged, "tag.slash", "Untagged")
                if !vm.tagCounts.isEmpty {
                    Divider().padding(.horizontal, 12).padding(.vertical, 4)
                    ForEach(vm.tagCounts, id: \.name) { tc in
                        Button { vm.scope = .tag(tc.name) } label: {
                            Circle().fill(TagColor.color(for: tc.name))
                                .frame(width: 12, height: 12)
                                .frame(width: 40, height: 30)
                                .background(isTag(tc.name) ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help(tc.name)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 56)
        .background(.bar)
    }

    @ViewBuilder
    private func scopeButton(_ scope: LibraryScope, _ icon: String, _ name: String, tint: Color? = nil) -> some View {
        Button { vm.scope = scope } label: {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 40, height: 30)
                .background(vm.scope == scope ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func isTag(_ name: String) -> Bool {
        if case .tag(let t) = vm.scope { return t == name }
        return false
    }
}
