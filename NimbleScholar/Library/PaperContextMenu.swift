import SwiftUI
import AppKit
import NimbleScholarCore

/// Right-click menu shared by every paper presentation (list rows, gallery cards, rows).
struct PaperContextMenu: ViewModifier {
    let paper: Paper
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { if let id = paper.id { openWindow(id: "reader", value: id) } } label: {
                Label("Read", systemImage: "book")
            }
            Button { vm.editingPaper = paper } label: { Label("Edit…", systemImage: "pencil") }
            Button { vm.refetchMetadata(paper) } label: { Label("Re-fetch Metadata", systemImage: "arrow.clockwise") }
            Button { vm.toggleToRead(paper) } label: {
                Label(vm.isUnread(paper) ? "Mark as Read" : "Mark as Unread",
                      systemImage: vm.isUnread(paper) ? "checkmark.circle" : "circle")
            }
            Button { vm.toggleImportant(paper) } label: {
                Label(paper.isImportant ? "Unmark Important" : "Mark as Important",
                      systemImage: paper.isImportant ? "star.slash" : "star")
            }
            Divider()
            Button {
                vm.markRead(paper)
                let s = paper.pdfURL.isEmpty ? paper.url : paper.pdfURL
                if let u = URL(string: s) { NSWorkspace.shared.open(u) }
            } label: { Label("Open in Browser", systemImage: "safari") }
            Button { vm.openPDFExternally(paper) } label: { Label("Open PDF in Default App", systemImage: "doc.richtext") }
            Button { vm.revealPDF(paper) } label: { Label("Reveal Cached PDF in Finder", systemImage: "folder") }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(BibTeXExporter.export([paper]), forType: .string)
            } label: { Label("Copy BibTeX", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { vm.delete(paper) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

extension View {
    func paperContextMenu(_ paper: Paper) -> some View { modifier(PaperContextMenu(paper: paper)) }
}
