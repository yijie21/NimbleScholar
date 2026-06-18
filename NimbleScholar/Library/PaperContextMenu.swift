import SwiftUI
import AppKit
import NimbleScholarCore

/// Right-click menu shared by every paper presentation (list rows, gallery cards, rows).
struct PaperContextMenu: ViewModifier {
    let paper: Paper
    @EnvironmentObject var vm: LibraryViewModel

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { vm.openReader(paper) } label: {
                Label("Read", systemImage: "book")
            }
            Button { vm.editingPaper = paper } label: { Label("Edit…", systemImage: "pencil") }
            Button {
                if let url = PDFPicker.pick(allowsMultiple: false,
                                            message: "Choose a PDF to attach to “\(paper.title)”").first {
                    vm.attachPDF(at: url, to: paper)
                }
            } label: { Label("Attach PDF…", systemImage: "paperclip") }
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
