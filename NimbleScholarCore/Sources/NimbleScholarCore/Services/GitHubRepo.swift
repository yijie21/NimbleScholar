import Foundation

/// Pure helpers for reasoning about a GitHub repo URL and its release state.
public enum GitHubRepo {
    /// Parse "…github.com/<owner>/<repo>…" → (owner, repo). nil if there's no owner/repo.
    public static func ownerRepo(from url: String) -> (owner: String, repo: String)? {
        guard let range = url.range(of: "github.com/", options: .caseInsensitive) else { return nil }
        let comps = url[range.upperBound...]
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard comps.count >= 2 else { return nil }
        var repo = comps[1]
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        return (comps[0], repo)
    }

    private static let docStems: Set<String> = [
        "readme", "license", "licence", "contributing", "code_of_conduct",
        "citation", "changelog", "authors", "notice",
    ]
    private static let docExact: Set<String> = [".gitignore", ".gitattributes", ".github"]

    /// Given the names of a repo's root entries, is there real content beyond docs/meta files?
    /// An empty list (empty repo) or docs-only list is treated as not released.
    public static func isReleased(rootEntryNames names: [String]) -> Bool {
        for name in names {
            let lower = name.lowercased()
            if docExact.contains(lower) { continue }
            let stem = lower.split(separator: ".").first.map(String.init) ?? lower
            if docStems.contains(stem) { continue }
            return true
        }
        return false
    }
}
