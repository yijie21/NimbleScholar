import SwiftUI
import NimbleScholarCore

/// The Links section's main content: a grid of link cards, with search, an Add Link button, and
/// drag-a-URL-to-save. Its own sheets for adding and editing.
struct LinksView: View {
    @EnvironmentObject var vm: LinksViewModel
    @State private var adding = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        Group {
            if vm.links.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(vm.links) { link in
                            LinkCard(link: link).environmentObject(vm)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(vm.scopeTitle)
        .searchable(text: $vm.query, prompt: "Search links")
        .dropDestination(for: URL.self) { urls, _ in
            for u in urls { vm.addLink(url: u.absoluteString) }
            return !urls.isEmpty
        }
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Label("Add Link", systemImage: "plus") }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .help("Add a webpage or GitHub link")
            }
        }
        .sheet(isPresented: $adding) { AddLinkSheet().environmentObject(vm) }
        .sheet(item: $vm.editingLink) { LinkEditSheet(link: $0).environmentObject(vm) }
        .task { vm.reload() }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "link").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No saved links yet").font(.headline)
            Text("Save a webpage or GitHub link as a card — paste a URL, drag one in, or use the browser extension. Tag them to keep an organized knowledge base, separate from your papers.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button { adding = true } label: { Label("Add Link", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
