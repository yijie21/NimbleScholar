import SwiftUI

/// Shown in Rows/Gallery when the current scope/search has no papers.
struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No papers", systemImage: "books.vertical")
        } description: {
            Text("Capture a paper from the toolbar, drag a PDF in, or use the browser extension.")
        }
    }
}
