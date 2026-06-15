import SwiftUI
import AppKit
import NimbleScholarCore

struct PaperDetailView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    let paper: Paper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaperThumbnail(paper: paper, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 340)
                    .background(.quaternary.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(alignment: .top, spacing: 8) {
                    Text(paper.title).font(.title2).bold()
                    ImportanceStar(paper: paper).font(.title3)
                }
                Text([paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                DetailSummaryField(paper: paper)
                HStack {
                    Button {
                        if let id = paper.id { openWindow(id: "reader", value: id) }
                    } label: { Label("Read", systemImage: "book") }
                    .buttonStyle(.borderedProminent)
                    Button("Browser") {
                        if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
                            NSWorkspace.shared.open(u)
                        }
                    }
                    Spacer()
                    Button("Edit") { vm.editingPaper = paper }
                    Button("Delete", role: .destructive) { vm.delete(paper) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !paper.projectURL.isEmpty || hasReadyCode {
                        HStack(spacing: 8) {
                            if !paper.projectURL.isEmpty {
                                Button { openLink(paper.projectURL) } label: {
                                    Label("Project", systemImage: "globe")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                            if hasReadyCode {
                                Button { openLink(paper.codeURL) } label: {
                                    Label {
                                        Text("Code")
                                    } icon: {
                                        Image("GitHubMark").renderingMode(.template)
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    if isWatchingCode {
                        Label("Watching for code release", systemImage: "hourglass")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if paper.projectURL.isEmpty && paper.codeURL.isEmpty {
                        Button("Add links…") { vm.editingPaper = paper }
                            .buttonStyle(.borderless).controlSize(.small)
                            .font(.caption)
                    }
                }
                FlowTags(tags: vm.tags(for: paper), onRemove: { vm.removeTag($0, from: paper) })
                TagInputField(paper: paper)
                if !paper.abstract.isEmpty {
                    Text(paper.abstract).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openLink(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    private var hasReadyCode: Bool { !paper.codeURL.isEmpty && paper.codeReady }
    /// No confirmed code yet, but there's a source we keep re-checking.
    private var isWatchingCode: Bool {
        !hasReadyCode && (!paper.url.isEmpty || !paper.projectURL.isEmpty || !paper.codeURL.isEmpty)
    }
}

/// Editable one-sentence summary in the detail panel. Reloads its text when the selected
/// paper changes; saves when you press Return (or commit a newline-wrapped line).
private struct DetailSummaryField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary").font(.caption).foregroundStyle(.secondary)
            TextField("One-sentence summary…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { vm.saveSummary(text, for: paper) }
        }
        .onAppear { text = paper.summary }
        .onChange(of: paper.id) { _, _ in text = paper.summary }
    }
}

struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void
    var body: some View {
        HStack {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Circle().fill(TagColor.color(for: tag)).frame(width: 6, height: 6)
                    Text(tag).font(.caption)
                    Button { onRemove(tag) } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
            }
        }
    }
}
