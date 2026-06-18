import SwiftUI
import NimbleScholarCore

/// Sidebar for the Links section: the smart filters and the link-only tag list (independent from
/// the papers' tags).
struct LinkSidebarView: View {
    @EnvironmentObject var vm: LinksViewModel
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        List(selection: Binding(get: { vm.scope }, set: { vm.scope = $0 ?? .all })) {
            Section {
                Label("All links", systemImage: "link").tag(LinkScope.all)
                Label("Untagged", systemImage: "tag.slash").tag(LinkScope.untagged)
            }
            Section("Tags") {
                ForEach(vm.tagCounts, id: \.name) { tc in
                    HStack {
                        Circle().fill(TagColor.color(for: tc.name)).frame(width: 8, height: 8)
                        Text(tc.name)
                        Spacer()
                        Text("\(tc.count)").foregroundStyle(.secondary)
                    }
                    .tag(LinkScope.tag(tc.name))
                    .contextMenu {
                        Button("Rename…") { renameText = tc.name; renaming = tc.name }
                        Button("Delete Tag", role: .destructive) { vm.deleteTag(tc.name) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("Rename tag", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let old = renaming { vm.renameTag(old, to: renameText) }
                renaming = nil
            }
        }
    }
}
