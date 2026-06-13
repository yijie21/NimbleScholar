import SwiftUI
import NimbleScholarCore

/// Temporary launch-confirmation screen. Deleted once LibraryContentView lands.
struct BootCheckView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var paperCount = 0
    @State private var lastTest = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill").font(.largeTitle)
            Text("Nimble Scholar").font(.title2).bold()
            Text("Core package linked ✓").foregroundStyle(.secondary)
            Text("Capture server: http://127.0.0.1:8765").foregroundStyle(.secondary)
            Text("Papers in library: \(paperCount)")
            Button("Refresh count") { refresh() }
            if !lastTest.isEmpty { Text(lastTest).font(.caption).foregroundStyle(.secondary) }
            Text("UI lands next.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(width: 380, height: 280)
        .padding()
        .onAppear { refresh() }
    }

    private func refresh() {
        paperCount = (try? env.store.allPapers().count) ?? -1
    }
}
