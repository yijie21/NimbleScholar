import SwiftUI
import NimbleScholarCore

struct SidebarView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        List(selection: Binding(get: { vm.scope }, set: { vm.scope = $0 ?? .all })) {
            Section {
                Label("All papers", systemImage: "tray.full").tag(LibraryScope.all)
                Label("Important", systemImage: "star.fill").tag(LibraryScope.important)
                Label("Unread", systemImage: "circle.fill").tag(LibraryScope.unread)
                Label("Recently added", systemImage: "clock").tag(LibraryScope.recent)
                Label("Untagged", systemImage: "tag.slash").tag(LibraryScope.untagged)
            }
            Section("Tags") {
                TagSidebarRows(tagCounts: vm.tagCounts,
                               scope: { LibraryScope.tag($0) },
                               onRename: { renameText = $0; renaming = $0 },
                               onDelete: { vm.deleteTag($0) })
            }
        }
        .listStyle(.sidebar)
        .renameTagAlert(renaming: $renaming, text: $renameText) { old, new in vm.renameTag(old, to: new) }
    }
}
