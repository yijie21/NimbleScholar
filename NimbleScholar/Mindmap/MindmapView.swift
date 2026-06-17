import SwiftUI
import NimbleScholarCore

/// The 4th library view mode. Real layout (shelf + canvas) arrives in later tasks.
struct MindmapView: View {
    var body: some View {
        VStack {
            Image(systemName: "brain").font(.largeTitle).foregroundStyle(.secondary)
            Text("Mindmap").font(.headline)
            Text("Coming together…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
