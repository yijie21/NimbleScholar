import Foundation
import SwiftSoup

public struct ArxivFigureService {
    public let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func figures(forID id: String) async throws -> FigureChooser.Result {
        let url = URL(string: ArxivService.htmlURL(forID: id))!
        let (data, _) = try await session.data(from: url)
        return Self.parse(html: String(decoding: data, as: UTF8.self), baseID: id)
    }

    static func parse(html: String, baseID: String) -> FigureChooser.Result {
        guard let doc = try? SwiftSoup.parse(html) else { return .init(teaser: nil, pipeline: nil) }
        let figs: [Figure] = (try? doc.select("figure").array().compactMap { fig -> Figure? in
            guard let img = try? fig.select("img").first() else { return nil }
            let src = (try? img.attr("src")) ?? ""
            let alt = (try? img.attr("alt")) ?? ""
            let cap = (try? fig.select("figcaption").text()) ?? ""
            let abs = src.hasPrefix("http") ? src : "https://arxiv.org/html/\(baseID)/\(src)"
            return Figure(url: abs, alt: alt, caption: cap)
        }) ?? []
        return FigureChooser.choose(from: figs)
    }
}
