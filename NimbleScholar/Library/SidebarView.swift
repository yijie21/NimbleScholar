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
                ForEach(vm.tagCounts, id: \.name) { tc in
                    HStack {
                        Circle().fill(TagColor.color(for: tc.name)).frame(width: 8, height: 8)
                        Text(tc.name)
                        Spacer()
                        Text("\(tc.count)").foregroundStyle(.secondary)
                    }
                    .tag(LibraryScope.tag(tc.name))
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
