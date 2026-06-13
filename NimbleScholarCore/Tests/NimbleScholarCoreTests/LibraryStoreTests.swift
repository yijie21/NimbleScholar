import XCTest
import GRDB
@testable import NimbleScholarCore

final class LibraryStoreTests: XCTestCase {
    func makeStore() throws -> LibraryStore {
        try LibraryStore(dbQueue: DatabaseQueue())   // in-memory
    }

    func testMigrationsCreateEmptyLibrary() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.allPapers().count, 0)
        XCTAssertEqual(try store.tagCounts().count, 0)
    }

    func testCreateSetTagsSearchAndDelete() throws {
        let store = try makeStore()
        var p = Paper(title: "Attention Is All You Need")
        p.authors = "Vaswani"; p.abstract = "transformer architecture"
        let saved = try store.create(p)
        XCTAssertNotNil(saved.id)

        try store.setTags(paperID: saved.id!, tags: ["LLM", "llm", "Transformers"])
        let counts = try store.tagCounts()
        XCTAssertEqual(Set(counts.map(\.name)), ["llm", "transformers"])

        XCTAssertEqual(try store.searchPapers(query: "transformer", tag: nil).count, 1)
        XCTAssertEqual(try store.searchPapers(query: "transformer", tag: "llm").count, 1)
        XCTAssertEqual(try store.searchPapers(query: "diffusion", tag: nil).count, 0)

        try store.deletePaper(id: saved.id!)
        XCTAssertEqual(try store.allPapers().count, 0)
        XCTAssertEqual(try store.tagCounts().count, 0)   // unused tags drop out
    }

    func testAnnotationIndexRoundTrip() throws {
        let store = try makeStore()
        let paper = try store.create(Paper(title: "P"))
        var a = AnnotationIndex(id: nil, paperId: paper.id!, page: 2, kind: "highlight",
                                color: "#ffd966", snippet: "key claim",
                                x: 0.1, y: 0.2, width: 0.3, height: 0.02,
                                createdAt: 0, updatedAt: 0)
        let saved = try store.upsertAnnotation(&a)
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(try store.annotations(forPaper: paper.id!).count, 1)
        try store.deleteAnnotation(id: saved.id!)
        XCTAssertEqual(try store.annotations(forPaper: paper.id!).count, 0)
    }
}
