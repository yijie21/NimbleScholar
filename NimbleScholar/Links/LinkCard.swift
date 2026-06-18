import SwiftUI
import AppKit
import NimbleScholarCore

/// One saved link as a card: figure, title, host, and its tags. Click opens the URL in the browser;
/// right-click to edit/copy/delete.
struct LinkCard: View, Equatable {
    @EnvironmentObject var vm: LinksViewModel
    let link: SavedLink
    let tags: [String]

    static func == (l: LinkCard, r: LinkCard) -> Bool {
        l.link == r.link && l.tags == r.tags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .overlay(LinkThumbnail(link: link))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if link.isGitHub {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.55)))
                            .padding(6)
                    }
                }

            Text(link.title.isEmpty ? link.url : link.title)
                .font(.callout).bold().lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: link.isGitHub ? "chevron.left.forwardslash.chevron.right" : "globe")
                Text(link.host).lineLimit(1)
            }
            .font(.caption2).foregroundStyle(.secondary)

            LinkCardTags(link: link)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { vm.open(link) }
        .help(link.url)
        .contextMenu {
            Button { vm.open(link) } label: { Label("Open in Browser", systemImage: "safari") }
            Button { vm.editingLink = link } label: { Label("Edit…", systemImage: "pencil") }
            Menu {
                ForEach(vm.tagCounts.map(\.name), id: \.self) { t in
                    let on = tags.contains(t)
                    Button { on ? vm.removeTag(t, from: link) : vm.addTag(t, to: link) } label: {
                        Label(t, systemImage: on ? "checkmark" : "tag")
                    }
                }
                if !vm.tagCounts.isEmpty { Divider() }
                Button { vm.editingLink = link } label: { Label("New Tag…", systemImage: "plus") }
            } label: { Label("Tags", systemImage: "tag") }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url, forType: .string)
            } label: { Label("Copy URL", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { vm.delete(link) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
