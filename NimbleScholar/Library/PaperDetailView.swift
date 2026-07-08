import SwiftUI
import AppKit
import NimbleScholarCore

struct PaperDetailView: View {
    @EnvironmentObject var vm: LibraryViewModel
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
                if let cue = lastReadCue {
                    Label(cue, systemImage: "bookmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DetailSummaryField(paper: paper)
                HStack {
                    Button { vm.openReader(paper) } label: { Label("Read", systemImage: "book") }
                    .buttonStyle(.borderedProminent)
                    Button {
                        vm.markRead(paper)
                        if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
                            NSWorkspace.shared.open(u)
                        }
                    } label: { Label("Browser", systemImage: "safari") }
                    Spacer()
                    Button("Edit") { vm.editingPaper = paper }
                    Button("Delete", role: .destructive) { vm.requestDelete([paper]) }
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

    /// "Last read: p. X of Y" from the reader's saved position (0 = never opened / page 1).
    private var lastReadCue: String? {
        guard let id = paper.id else { return nil }
        let page = UserDefaults.standard.integer(forKey: "readingPage.\(id)")
        guard page > 0 else { return nil }
        let count = UserDefaults.standard.integer(forKey: "readingPageCount.\(id)")
        return count > 0 ? "Last read: p. \(page + 1) of \(count)" : "Last read: p. \(page + 1)"
    }
}

/// Editable one-sentence summary in the detail panel. Reloads its text when the selected
/// paper changes; saves on Return or when focus leaves the field. Commits are pinned to
/// `editing` — the paper the draft was typed for — so a selection change can never write
/// the old draft onto the newly selected paper (blur and paper-swap ordering is not
/// guaranteed by SwiftUI).
private struct DetailSummaryField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var text = ""
    @State private var editing: Paper?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary").font(.caption).foregroundStyle(.secondary)
            TextField("One-sentence summary…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, nowFocused in if !nowFocused { commit() } }
        }
        .onAppear { editing = paper; text = paper.summary }
        .onChange(of: paper.id) { _, _ in
            commit()   // save any draft to the paper it was typed for
            editing = paper
            text = paper.summary
        }
    }

    private func commit() {
        guard var target = editing, text != target.summary else { return }
        vm.saveSummary(text, for: target)
        // Keep the guard accurate so a follow-up blur/switch can't double-save.
        target.summary = text
        editing = target
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
