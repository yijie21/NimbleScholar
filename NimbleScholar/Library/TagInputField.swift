import SwiftUI
import NimbleScholarCore

/// Add-a-tag control with reuse of existing tags. Three quick paths to assign a
/// previously-used tag instead of retyping it:
///   • a "tag" menu listing every existing tag not yet on the paper (click to add)
///   • live autocomplete chips that filter as you type (click to add)
///   • free text + Enter to create a new tag (comma-separated for several at once)
struct TagInputField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    var fieldWidth: CGFloat = 200

    @State private var newTag = ""
    @FocusState private var focused: Bool

    private func commit(_ raw: String) {
        let parts = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for t in parts { vm.addTag(t, to: paper) }
        newTag = ""
    }

    var body: some View {
        let typed = vm.tagSuggestions(for: paper, matching: newTag)
        let all = vm.tagSuggestions(for: paper)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("+ tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: fieldWidth)
                    .focused($focused)
                    .onSubmit { if !newTag.isEmpty { commit(newTag) } }
                    .onChange(of: focused) { _, nowFocused in
                        if !nowFocused, !newTag.isEmpty { commit(newTag) }
                    }
                if !all.isEmpty {
                    Menu {
                        ForEach(all, id: \.self) { t in
                            Button { vm.addTag(t, to: paper) } label: { Label(t, systemImage: "tag") }
                        }
                    } label: {
                        Image(systemName: "tag")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add an existing tag")
                }
            }
            if focused, !newTag.isEmpty, !typed.isEmpty {
                HStack(spacing: 6) {
                    ForEach(typed.prefix(6), id: \.self) { t in
                        Button { vm.addTag(t, to: paper); newTag = "" } label: {
                            HStack(spacing: 4) {
                                Circle().fill(TagColor.color(for: t)).frame(width: 6, height: 6)
                                Text(t).font(.caption)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        .help("Add “\(t)”")
                    }
                }
            }
        }
    }
}
