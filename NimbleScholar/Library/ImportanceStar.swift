import SwiftUI
import NimbleScholarCore

/// A star toggle for a paper's importance. Gold filled when important, subtle outline
/// otherwise. `onImage` adds a material backing so it stays legible over a thumbnail.
struct ImportanceStar: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    var onImage = false

    var body: some View {
        Button { vm.toggleImportant(paper) } label: {
            Image(systemName: paper.isImportant ? "star.fill" : "star")
                .foregroundStyle(paper.isImportant ? Color.yellow : Color.secondary)
                .padding(onImage ? 5 : 0)
                .background { if onImage { Circle().fill(.thinMaterial) } }
        }
        .buttonStyle(.plain)
        .help(paper.isImportant ? "Unmark important" : "Mark important")
    }
}
