public struct Figure: Equatable {
    public let url: String
    public let alt: String
    public let caption: String
    public init(url: String, alt: String, caption: String) {
        self.url = url; self.alt = alt; self.caption = caption
    }
}

public enum FigureChooser {
    public struct Result {
        public var teaser: String?
        public var pipeline: String?
        public init(teaser: String?, pipeline: String?) { self.teaser = teaser; self.pipeline = pipeline }
    }

    private static let placeholders = [
        "logo", "favicon", "icon", "static", "browse", "arxiv-logo",
        "orcid", "creativecommons", "cc-by", "cc_by", "header", "footer",
        "banner", "spacer", "email", "/badge", "doi.svg",
    ]
    private static let teaserWords = ["teaser", "overview", "result", "qualitative", "example", "motivation"]
    private static let pipelineWords = [
        "pipeline", "method", "architecture", "framework", "overview of",
        "approach", "network", "model", "system",
    ]

    /// True when a figure URL (or alt text) is a site chrome image — logo, badge, icon —
    /// rather than a real paper figure. Also used to reject `og:image` teasers coming from
    /// capture payloads (e.g. the OpenReview logo on forum pages).
    public static func isPlaceholder(_ urlOrAlt: String) -> Bool {
        let hay = urlOrAlt.lowercased()
        return placeholders.contains { hay.contains($0) }
    }

    public static func choose(from figures: [Figure]) -> Result {
        let valid = figures.filter { !isPlaceholder($0.url + " " + $0.alt) }
        func firstMatch(_ words: [String]) -> String? {
            valid.first { f in
                let hay = (f.alt + " " + f.caption).lowercased()
                return words.contains { hay.contains($0) }
            }?.url
        }
        var r = Result(teaser: firstMatch(teaserWords), pipeline: firstMatch(pipelineWords))
        if r.teaser == nil { r.teaser = valid.first?.url }
        if r.pipeline == r.teaser { r.pipeline = nil }
        return r
    }
}
