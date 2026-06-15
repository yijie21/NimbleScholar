import Foundation
import NimbleScholarCore

enum RepoStatus: Equatable { case released, notReleased, rateLimited, error }

/// Checks a GitHub repo's release state via the contents API.
/// Unauthenticated (60 req/hr); `.rateLimited` lets the caller stop and resume later.
enum GitHubRepoChecker {
    static func check(_ codeURL: String, session: URLSession) async -> RepoStatus {
        guard let (owner, repo) = GitHubRepo.ownerRepo(from: codeURL),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents") else {
            return .error
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NimbleScholar", forHTTPHeaderField: "User-Agent")  // GitHub rejects no-UA
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return .error }
        switch http.statusCode {
        case 404: return .notReleased                  // empty repo or missing
        case 403: return .rateLimited
        case 200:
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .error
            }
            let names = arr.compactMap { $0["name"] as? String }
            return GitHubRepo.isReleased(rootEntryNames: names) ? .released : .notReleased
        default:
            return .error
        }
    }
}
