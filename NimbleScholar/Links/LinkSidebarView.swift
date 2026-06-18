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
                TagSidebarRows(tagCounts: vm.tagCounts,
                               scope: { LinkScope.tag($0) },
                               onRename: { renameText = $0; renaming = $0 },
                               onDelete: { vm.deleteTag($0) })
            }
        }
        .listStyle(.sidebar)
        .renameTagAlert(renaming: $renaming, text: $renameText) { old, new in vm.renameTag(old, to: new) }
    }
}
