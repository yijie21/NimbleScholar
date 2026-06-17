import SwiftUI
import NimbleScholarCore

/// The 4th library view mode: a narrow paper shelf beside the map bar + canvas.
struct MindmapView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @StateObject private var vm = MindmapViewModel()

    var body: some View {
        HStack(spacing: 0) {
            PaperShelf()
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .frame(width: 250)
            Divider()
            VStack(spacing: 0) {
                MapBar().environmentObject(vm)
                Divider()
                if vm.activeMapID == nil {
                    MindmapEmptyState().environmentObject(vm)
                } else {
                    MindmapCanvas()
                        .environmentObject(vm)
                        .environmentObject(libraryVM)
                }
            }
        }
    }
}

/// Shown when no map exists/selected — one button to create the first map.
struct MindmapEmptyState: View {
    @EnvironmentObject var vm: MindmapViewModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No mindmap yet").font(.headline)
            Text("Create a map for a research idea, then drag papers onto its nodes.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { vm.createMap(name: "Untitled idea") } label: {
                Label("New mindmap", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
