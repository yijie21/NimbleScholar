import SwiftUI
import NimbleScholarCore

struct PaperEditSheet: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State var paper: Paper
    @State private var original: Paper
    @State private var confirmDiscard = false

    init(paper: Paper) {
        _paper = State(initialValue: paper)
        _original = State(initialValue: paper)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $paper.title)
                TextField("Authors", text: $paper.authors)
                TextField("Year", text: $paper.year)
                TextField("Venue", text: $paper.venue)
                TextField("DOI / arXiv ID", text: $paper.doi)
                TextField("URL", text: $paper.url)
                TextField("PDF URL", text: $paper.pdfURL)
                HStack {
                    Button("Attach PDF…") {
                        if let url = PDFPicker.pick(allowsMultiple: false,
                                                    message: "Choose a PDF for this paper").first {
                            paper.pdfPath = vm.cachePDF(url)   // copy into cache now; persisted on Save
                        }
                    }
                    if !paper.pdfPath.isEmpty {
                        Text((paper.pdfPath as NSString).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button { paper.pdfPath = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Detach PDF")
                    } else {
                        Text("No local PDF").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                TextField("Project URL", text: $paper.projectURL)
                TextField("Code URL (GitHub)", text: $paper.codeURL)
                TextField("Summary", text: $paper.summary)
                TextField("Abstract", text: $paper.abstract, axis: .vertical).lineLimit(4...)
            }
            .formStyle(.grouped)
            HStack {
                if paper.id != nil {
                    Button("Delete", role: .destructive) { vm.requestDelete([paper]); dismiss() }
                }
                Spacer()
                Button("Cancel") {
                    if paper != original { confirmDiscard = true } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    paper.codeReady = !paper.codeURL.isEmpty
                    vm.save(paper)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 580)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }
}
