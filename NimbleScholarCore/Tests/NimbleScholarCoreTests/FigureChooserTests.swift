import XCTest
@testable import NimbleScholarCore

final class FigureChooserTests: XCTestCase {
    func testPrefersTeaserThenPipelineFiltersPlaceholders() {
        let figs = [
            Figure(url: "https://x/arxiv-logo.png", alt: "logo", caption: ""),
            Figure(url: "https://x/fig3.png", alt: "", caption: "Figure 3: The overall pipeline of our method"),
            Figure(url: "https://x/fig1.png", alt: "teaser", caption: "Figure 1: Teaser showing results"),
        ]
        let chosen = FigureChooser.choose(from: figs)
        XCTAssertEqual(chosen.teaser, "https://x/fig1.png")
        XCTAssertEqual(chosen.pipeline, "https://x/fig3.png")
    }

    func testReturnsEmptyWhenOnlyPlaceholders() {
        let figs = [Figure(url: "https://x/favicon.ico", alt: "", caption: "")]
        let chosen = FigureChooser.choose(from: figs)
        XCTAssertNil(chosen.teaser)
        XCTAssertNil(chosen.pipeline)
    }
}
