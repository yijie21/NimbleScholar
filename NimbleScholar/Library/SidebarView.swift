import SwiftUI
import NimbleScholarCore

struct SidebarView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        List(selection: $vm.selectedTag) {
            Section {
                Label("All papers", systemImage: "tray.full").tag(String?.none)
            }
            Section("Tags") {
                ForEach(vm.tagCounts, id: \.name) { tc in
                    HStack {
                        Circle().fill(TagColor.color(for: tc.name)).frame(width: 8, height: 8)
                        Text(tc.name)
                        Spacer()
                        Text("\(tc.count)").foregroundStyle(.secondary)
                    }
                    .tag(String?.some(tc.name))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
