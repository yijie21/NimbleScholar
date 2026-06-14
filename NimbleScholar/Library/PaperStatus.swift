import SwiftUI
import AppKit
import NimbleScholarCore

/// Per-paper readiness, derived purely from the record + cache on disk.
extension Paper {
    /// A local PDF has been downloaded (so the paper opens instantly and renders a thumbnail).
    var hasLocalPDF: Bool { !pdfPath.isEmpty && FileManager.default.fileExists(atPath: pdfPath) }
    /// A figure (teaser/pipeline) is available for the card.
    var hasFigure: Bool { !teaserURL.isEmpty || !pipelineURL.isEmpty }
    /// "Ready" = the PDF is cached locally; that gives both a thumbnail and instant opening.
    /// A figure is a bonus we still try to fetch, but a paper without one (e.g. CVF) can still be ready.
    var isReady: Bool { hasLocalPDF }
}

/// Small corner badge for a library card showing the paper's download state:
/// a spinner while its figure/PDF are being fetched, a green check once ready,
/// or a tappable orange arrow to (re)try a paper that hasn't loaded yet.
struct PaperStatusBadge: View {
    @EnvironmentObject var vm: LibraryViewModel
    @ObservedObject private var activity = ActivityCenter.shared
    let paper: Paper

    var body: some View {
        content
            .font(.caption)
            .padding(5)
            .background(.thinMaterial, in: Circle())
            .padding(6)
    }

    @ViewBuilder private var content: some View {
        if let label = activity.itemLabel(paper.id) {
            ProgressView().controlSize(.small).help(label)
        } else if paper.isReady {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help(paper.hasFigure ? "Ready" : "Ready (PDF cached, no figure)")
        } else {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
                .help("Not downloaded yet — click to retry")
                .onTapGesture { vm.retry(paper) }
        }
    }
}

/// Inline (text + glyph) status for list rows where a corner badge doesn't fit.
struct PaperStatusInline: View {
    @EnvironmentObject var vm: LibraryViewModel
    @ObservedObject private var activity = ActivityCenter.shared
    let paper: Paper

    var body: some View {
        if let label = activity.itemLabel(paper.id) {
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text(label) }
                .font(.caption).foregroundStyle(.secondary)
        } else if paper.isReady {
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                .help(paper.hasFigure ? "Ready" : "Ready (PDF cached, no figure)")
        } else {
            Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(.orange)
                .help("Not downloaded yet — click to retry")
                .onTapGesture { vm.retry(paper) }
        }
    }
}
