import SwiftUI
import PDFKit
import AppKit

/// In-document search for the PDF reader (⌘F): a floating card centered at the top of the
/// page. Finds every occurrence of the query (partial matches by default, whole-word via
/// the checkbox), highlights them all, shows "n of m", and steps through matches with
/// Return / ⌘G (next) and ⇧⌘G (previous). Esc closes it and clears the highlights.
struct FindBar: View {
    let pdfView: PDFView?
    @Binding var isPresented: Bool
    /// Bumped by the ⌘F button while the bar is already open → refocus the field.
    let focusRequest: Int

    @State private var query = ""
    @State private var matches: [PDFSelection] = []
    @State private var current = 0
    @FocusState private var focused: Bool
    /// Match whole words only (persisted across sessions).
    @AppStorage("findWholeWord") private var wholeWord = false

    /// Highlighting thousands of one-letter hits makes PDFKit crawl; cap what we mark.
    private static let maxMatches = 500

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in document", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { advance(by: 1) }
                .onExitCommand { close() }
            if !query.isEmpty {
                Text(counterText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
            Toggle("Whole word", isOn: $wholeWord)
                .toggleStyle(.checkbox)
                .font(.callout)
                .fixedSize()
                .help("Match whole words only")
            Button { advance(by: -1) } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(matches.count < 2)
                .help("Previous match (⇧⌘G)")
            Button { advance(by: 1) } label: { Image(systemName: "chevron.down") }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(matches.count < 2)
                .help("Next match (⌘G)")
            Button("Done") { close() }
                .help("Close (Esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: wholeWord) { _, _ in runSearch() }
        .onDisappear { clearHighlights() }
    }

    private var counterText: String {
        matches.isEmpty ? "Not found" : "\(current + 1) of \(matches.count)"
    }

    private func runSearch() {
        guard let pv = pdfView, let doc = pv.document, !query.isEmpty else {
            matches = []
            current = 0
            clearHighlights()
            return
        }
        var found = doc.findString(query, withOptions: .caseInsensitive)
        if wholeWord { found = found.filter(Self.isWholeWord) }
        if found.count > Self.maxMatches { found = Array(found.prefix(Self.maxMatches)) }
        matches = found
        current = 0
        if found.isEmpty {
            clearHighlights()
        } else {
            show(index: 0, in: pv)
        }
    }

    /// PDFKit has no whole-word search option, so filter after the fact: peek one character
    /// beyond each end of the match — a letter or digit there means it's inside a word.
    static func isWholeWord(_ sel: PDFSelection) -> Bool {
        let matched = sel.string ?? ""
        if let s = sel.copy() as? PDFSelection {
            s.extend(atStart: 1)
            let str = s.string ?? ""
            if str.count > matched.count, let first = str.first,
               first.isLetter || first.isNumber { return false }
        }
        if let s = sel.copy() as? PDFSelection {
            s.extend(atEnd: 1)
            let str = s.string ?? ""
            if str.count > matched.count, let last = str.last,
               last.isLetter || last.isNumber { return false }
        }
        return true
    }

    /// Mark every match yellow, the current one orange, and scroll it into view.
    private func show(index: Int, in pv: PDFView) {
        guard matches.indices.contains(index) else { return }
        for (i, sel) in matches.enumerated() {
            sel.color = i == index
                ? NSColor.systemOrange.withAlphaComponent(0.8)
                : NSColor.systemYellow.withAlphaComponent(0.5)
        }
        pv.highlightedSelections = matches
        pv.setCurrentSelection(matches[index], animate: true)
        pv.go(to: matches[index])
    }

    private func advance(by delta: Int) {
        guard let pv = pdfView, !matches.isEmpty else { return }
        let n = matches.count
        current = ((current + delta) % n + n) % n
        show(index: current, in: pv)
    }

    private func close() {
        isPresented = false   // .onDisappear clears the highlights
    }

    private func clearHighlights() {
        pdfView?.highlightedSelections = nil
        pdfView?.clearSelection()
    }
}
