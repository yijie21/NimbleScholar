import XCTest
import GRDB
@testable import NimbleScholarCore

final class LinkStoreTests: XCTestCase {
    func makeStore() throws -> LibraryStore {
        try LibraryStore(dbQueue: DatabaseQueue())   // in-memory; runs the migrator (incl. v12-links)
    }

    func testCreateUpdateDeleteLink() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.allLinks().count, 0)

        var link = SavedLink(url: "https://github.com/groue/GRDB.swift")
        link.title = "GRDB"
        link.source = "github"
        let saved = try store.createLink(link)
        XCTAssertNotNil(saved.id)
        XCTAssertGreaterThan(saved.createdAt, 0)

        XCTAssertEqual(try store.allLinks().map(\.title), ["GRDB"])

        var edited = saved
        edited.title = "GRDB.swift"
        _ = try store.updateLink(edited)
        XCTAssertEqual(try store.link(id: saved.id!)?.title, "GRDB.swift")

        try store.deleteLink(id: saved.id!)
        XCTAssertEqual(try store.allLinks().count, 0)
    }

    func testDedupeByURL() throws {
        let store = try makeStore()
        let url = "https://example.com/post"
        _ = try store.createLink(SavedLink(url: url))
        XCTAssertNotNil(try store.existingLink(forURL: url))
        XCTAssertNil(try store.existingLink(forURL: "https://example.com/other"))
    }

    func testLinkTagsAreIndependentFromPaperTags() throws {
        let store = try makeStore()

        // A paper tagged "shared" must NOT show up among link tags, and vice-versa.
        let paper = try store.create(Paper(title: "A paper"))
        try store.setTags(paperID: paper.id!, tags: ["shared", "paper-only"])

        let link = try store.createLink(SavedLink(url: "https://example.com"))
        try store.setLinkTags(linkID: link.id!, tags: ["shared", "link-only"])

        XCTAssertEqual(try store.tags(forLink: link.id!), ["link-only", "shared"])
        XCTAssertEqual(Set(try store.linkTagCounts().map(\.name)), ["link-only", "shared"])
        // The paper vocabulary is untouched by link tagging.
        XCTAssertEqual(Set(try store.tagCounts().map(\.name)), ["paper-only", "shared"])
        // "link-only" never leaks into paper tags.
        XCTAssertFalse(try store.tagCounts().map(\.name).contains("link-only"))
    }

    func testSearchAndUntaggedAndCounts() throws {
        let store = try makeStore()
        let a = try store.createLink({ var l = SavedLink(url: "https://github.com/apple/swift"); l.title = "Swift"; return l }())
        let b = try store.createLink({ var l = SavedLink(url: "https://example.com/blog"); l.title = "Blog post"; return l }())
        try store.setLinkTags(linkID: a.id!, tags: ["lang"])

        XCTAssertEqual(try store.searchLinks(query: "swift", tag: nil).map(\.id), [a.id])
        XCTAssertEqual(try store.searchLinks(query: nil, tag: "lang").map(\.id), [a.id])
        XCTAssertEqual(try store.untaggedLinks(query: nil).map(\.id), [b.id])
        XCTAssertEqual(try store.linkTagCounts().first(where: { $0.name == "lang" })?.count, 1)

        // Renaming a link tag doesn't touch papers.
        try store.renameLinkTag("lang", to: "language")
        XCTAssertEqual(try store.tags(forLink: a.id!), ["language"])
        try store.deleteLinkTag("language")
        XCTAssertEqual(try store.tags(forLink: a.id!), [])
    }
}
