import SwiftUI
import NimbleScholarCore

/// The "Tags" rows shared by the paper and link sidebars: a colored dot, the name, the count, and a
/// rename/delete context menu. Generic over the sidebar's scope type so each `.tag(...)` drives that
/// sidebar's List selection.
struct TagSidebarRows<Scope: Hashable>: View {
    let tagCounts: [TagCount]
    let scope: (String) -> Scope
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    /// When set, the tag's context menu offers a Markdown export of its papers. The links
    /// sidebar leaves this nil (there's nothing paper-shaped to export there).
    var onExport: ((String) -> Void)? = nil

    var body: some View {
        ForEach(tagCounts, id: \.name) { tc in
            HStack {
                Circle().fill(TagColor.color(for: tc.name)).frame(width: 8, height: 8)
                Text(tc.name)
                Spacer()
                Text("\(tc.count)").foregroundStyle(.secondary)
            }
            .tag(scope(tc.name))
            .contextMenu {
                Button("Rename…") { onRename(tc.name) }
                if let onExport {
                    Button("Export to Markdown…") { onExport(tc.name) }
                }
                Button("Delete Tag", role: .destructive) { onDelete(tc.name) }
            }
        }
    }
}

/// The shared "Rename tag" alert used by both sidebars.
struct RenameTagAlert: ViewModifier {
    @Binding var renaming: String?
    @Binding var text: String
    let onRename: (_ old: String, _ new: String) -> Void

    func body(content: Content) -> some View {
        content.alert("Rename tag",
                      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $text)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let old = renaming { onRename(old, text) }
                renaming = nil
            }
        }
    }
}

extension View {
    func renameTagAlert(renaming: Binding<String?>, text: Binding<String>,
                        onRename: @escaping (String, String) -> Void) -> some View {
        modifier(RenameTagAlert(renaming: renaming, text: text, onRename: onRename))
    }
}
