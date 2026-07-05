import Foundation
import PDFKit

/// Pulls a paper's title out of its PDF when no online source could provide one — e.g.
/// OpenReview papers whose site/API sit behind a browser check the app can't pass.
///
/// Two strategies, in order:
///   1. The PDF's embedded Title attribute (when it isn't LaTeX/Word junk like "main.dvi").
///   2. The headline heuristic: a paper's title is set in the largest type on page 1, above
///      the authors and abstract. Find the tallest run of consecutive lines in the upper
///      part of the page and join them.
enum PDFTitleExtractor {
    static func title(fromPDFAt path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { return nil }
        if let t = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           isPlausible(t) {
            return normalize(t)
        }
        return headlineTitle(doc)
    }

    /// Reject junk Title attributes: empty, single tokens, filenames, tool defaults.
    static func isPlausible(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 8, s.contains(" ") else { return false }
        let lower = s.lowercased()
        let junk = ["untitled", ".dvi", ".tex", ".pdf", ".doc", ".docx", ".qxd", ".indd",
                    "microsoft word", "powerpoint", "adobe", "arxiv:"]
        return !junk.contains { lower.contains($0) }
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Front-matter lines that are never the title, even when set large.
    private static let skipRegex = try? NSRegularExpression(
        pattern: #"^(published as|under review|accepted|to appear|anonymous|preprint|arxiv|proceedings|workshop( |$)|conference( |$)|journal( |$)|supplementary|appendix)"#,
        options: [.caseInsensitive])

    private static func shouldSkip(_ s: String) -> Bool {
        guard let re = skipRegex else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The tallest run of consecutive lines in the upper part of page 1.
    private static func headlineTitle(_ doc: PDFDocument) -> String? {
        guard let page = doc.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.height > 0, let all = page.selection(for: pageRect) else { return nil }

        // Lines top-to-bottom (PDF user space is y-up: larger y = higher on the page),
        // restricted to the upper 55% — titles never sit below that.
        let lines = all.selectionsByLine()
            .map { (bounds: $0.bounds(for: page),
                    text: ($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty && $0.bounds.height > 4 && $0.bounds.width > 10 }
            .filter { $0.bounds.midY > pageRect.minY + 0.45 * pageRect.height }
            .sorted { $0.bounds.maxY > $1.bounds.maxY }
        guard lines.count >= 2 else { return nil }

        // Title lines are noticeably taller than the page's median (≈ body) line height.
        // (Closure, not key path: key paths can't refer to tuple elements.)
        let heights = lines.map { $0.bounds.height }.sorted()
        let median = heights[heights.count / 2]
        let threshold = max(median * 1.25, 10)

        var picked: [String] = []
        var lastBottom: CGFloat = 0     // minY of the previously accepted line
        for ln in lines {
            let isBig = ln.bounds.height >= threshold
            if picked.isEmpty {
                if isBig, !shouldSkip(ln.text) {
                    picked.append(ln.text); lastBottom = ln.bounds.minY
                }
                continue
            }
            // Extend the run only through consecutive big lines with title-ish line gaps.
            if isBig, lastBottom - ln.bounds.maxY < ln.bounds.height {
                picked.append(ln.text); lastBottom = ln.bounds.minY
            } else {
                break
            }
        }
        let joined = normalize(picked.joined(separator: " "))
        // 3+ words and a sane length ⇒ plausible paper title.
        guard joined.split(separator: " ").count >= 3, (12...300).contains(joined.count) else { return nil }
        return joined
    }
}
