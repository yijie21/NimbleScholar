import SwiftUI
import PDFKit
import NimbleScholarCore

struct InspectorPanel: View {
    let pdfView: PDFView
    @ObservedObject var vm: ReaderViewModel
    @StateObject private var chatVM: ChatViewModel
    @State private var tab = 0

    init(pdfView: PDFView, vm: ReaderViewModel) {
        self.pdfView = pdfView
        self._vm = ObservedObject(wrappedValue: vm)
        self._chatVM = StateObject(wrappedValue: ChatViewModel(paper: vm.paper))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Annotations").tag(0)
                Text("Chat").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            if tab == 0 { annotationList } else { ChatView(vm: chatVM) }
        }
        .onAppear { chatVM.pdfView = pdfView }
    }

    private var annotationList: some View {
        List {
            if vm.annotations.isEmpty {
                Text("No annotations").foregroundStyle(.secondary)
            }
            ForEach(vm.annotations) { a in
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: a.color)).frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(a.snippet.isEmpty ? a.kind : a.snippet).lineLimit(2).font(.caption)
                        Text("Page \(a.page)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let page = pdfView.document?.page(at: a.page - 1) { pdfView.go(to: page) }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        AnnotationController(vm: vm).deleteIndexed(a, pdfView: pdfView)
                    }
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.dropFirst(hex.hasPrefix("#") ? 1 : 0)
        var v: UInt64 = 0
        Scanner(string: String(s)).scanHexInt64(&v)
        self = Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}
