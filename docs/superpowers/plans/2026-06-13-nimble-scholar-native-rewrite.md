# Nimble Scholar Native macOS Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Python+WebView Nimble Scholar with a fully native Swift/SwiftUI macOS app whose PDF reader feels like a commercial reader (PDFKit) and whose library is native and switchable across three view modes.

**Architecture:** Two-layer build. A SwiftPM package `NimbleScholarCore` holds all non-UI logic (models, GRDB SQLite store + FTS, arXiv/metadata/figure/PDF services, BibTeX, the loopback capture HTTP server) and is fully unit-tested with `swift test`. An Xcode app target `NimbleScholar` depends on the core package and holds the SwiftUI/PDFKit UI (library window with Three-pane/Gallery/Rows modes, per-paper reader window with thumbnails + PDF + inspector), verified by building and running on a Mac.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit interop, PDFKit, GRDB.swift (SQLite), FlyingFox (embedded HTTP), SwiftSoup (HTML parsing), XCTest. macOS 14+, Apple Silicon.

---

## Environment & Conventions

- **All build/test/run commands run on a Mac** with Xcode 15+ installed. The dev Linux box only authors files.
- The repo is **not yet a git repository**. Task 0 initializes it.
- Core logic is tested with `swift test` from `NimbleScholarCore/`. The app UI is verified by `xcodebuild build` + launching the app (manual checkpoints labeled **VERIFY ON MAC**).
- Commit message convention: `feat:`, `test:`, `chore:`, `fix:`.
- End each commit body with the standard co-author trailer if your workflow requires it (omitted here for brevity).

## File Structure

```
paper_app/                                   # existing repo root (Python app left in place, untouched)
  NimbleScholarCore/                          # SwiftPM package — testable, no UI
    Package.swift
    Sources/NimbleScholarCore/
      Models/Paper.swift
      Models/Tag.swift
      Models/AnnotationIndex.swift
      Models/CapturePayload.swift
      Store/LibraryStore.swift                # GRDB queue, migrations, CRUD, FTS, tags
      Store/TagNormalizer.swift
      Services/ArxivService.swift             # id/url normalization + Atom parse
      Services/MetadataService.swift          # arXiv API + generic <meta> fallback
      Services/FigureChooser.swift            # teaser/pipeline heuristic
      Services/ArxivFigureService.swift       # fetch arxiv HTML + choose
      Services/PDFDownloader.swift
      Services/BibTeXExporter.swift
      Capture/CaptureHandler.swift            # turns a CapturePayload into a saved Paper
      Capture/CaptureServer.swift             # FlyingFox loopback server
    Tests/NimbleScholarCoreTests/
      LibraryStoreTests.swift
      TagNormalizerTests.swift
      ArxivServiceTests.swift
      MetadataServiceTests.swift
      FigureChooserTests.swift
      BibTeXExporterTests.swift
      CaptureHandlerTests.swift
      CaptureServerTests.swift
      Fixtures/                               # sample arXiv Atom XML + HTML
  NimbleScholar/                              # Xcode app target — UI
    NimbleScholarApp.swift
    Library/LibraryViewModel.swift
    Library/SidebarView.swift
    Library/LibraryContentView.swift          # hosts the view-mode switcher
    Library/ThreePaneView.swift
    Library/GalleryView.swift
    Library/RowsView.swift
    Library/PaperDetailView.swift
    Library/PaperEditSheet.swift
    Library/CaptureSheet.swift
    Library/TagColor.swift
    Reader/ReaderWindow.swift
    Reader/PDFKitView.swift                   # NSViewRepresentable wrapping PDFView
    Reader/ReaderViewModel.swift
    Reader/ReaderToolbar.swift
    Reader/ThumbnailSidebar.swift
    Reader/InspectorPanel.swift
    Reader/AnnotationController.swift
    AppEnvironment.swift                       # shared store + services + capture server
    Settings/SettingsView.swift
  NimbleScholar.xcodeproj
```

---

## Phase 0 — Scaffold & toolchain

### Task 0: Initialize repo and SwiftPM core package

**Files:**
- Create: `NimbleScholarCore/Package.swift`
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Placeholder.swift`
- Create: `NimbleScholarCore/Tests/NimbleScholarCoreTests/SmokeTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Initialize git and ignore build artifacts**

Create `.gitignore`:

```gitignore
.DS_Store
.build/
DerivedData/
*.xcuserstate
.superpowers/
xcuserdata/
```

Run on Mac:

```bash
cd paper_app
git init
git add .gitignore
git commit -m "chore: init git, ignore build artifacts"
```

- [ ] **Step 2: Create the SwiftPM package manifest**

Create `NimbleScholarCore/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NimbleScholarCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NimbleScholarCore", targets: ["NimbleScholarCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "NimbleScholarCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FlyingFox", package: "FlyingFox"),
                "SwiftSoup",
            ]
        ),
        .testTarget(
            name: "NimbleScholarCoreTests",
            dependencies: ["NimbleScholarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 3: Add placeholder source so the package compiles**

Create `NimbleScholarCore/Sources/NimbleScholarCore/Placeholder.swift`:

```swift
public enum NimbleScholarCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Write a smoke test**

Create `NimbleScholarCore/Tests/NimbleScholarCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(NimbleScholarCore.version, "0.1.0")
    }
}
```

Also create an empty fixtures dir so the resource copy succeeds:

```bash
mkdir -p NimbleScholarCore/Tests/NimbleScholarCoreTests/Fixtures
touch NimbleScholarCore/Tests/NimbleScholarCoreTests/Fixtures/.keep
```

- [ ] **Step 5: Resolve dependencies and run tests**

Run: `cd NimbleScholarCore && swift test`
Expected: dependencies resolve; `testVersionExists` PASSES.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore
git commit -m "chore: scaffold NimbleScholarCore SwiftPM package with deps"
```

---

## Phase 1 — Models & GRDB store

### Task 1: Paper, Tag, and AnnotationIndex models

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift`
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Tag.swift`
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Models/AnnotationIndex.swift`

- [ ] **Step 1: Define the Paper record**

Create `Models/Paper.swift`:

```swift
import Foundation
import GRDB

public struct Paper: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var title: String
    public var authors: String = ""
    public var year: String = ""
    public var venue: String = ""
    public var doi: String = ""
    public var url: String = ""
    public var pdfURL: String = ""
    public var pdfPath: String = ""
    public var summary: String = ""
    public var teaserURL: String = ""
    public var pipelineURL: String = ""
    public var abstract: String = ""
    public var notes: String = ""
    public var source: String = ""
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "papers"

    enum Columns: String, ColumnExpression {
        case id, title, authors, year, venue, doi, url
        case pdfURL = "pdf_url", pdfPath = "pdf_path", summary
        case teaserURL = "teaser_url", pipelineURL = "pipeline_url"
        case abstract, notes, source
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(id: Int64? = nil, title: String) {
        self.id = id
        self.title = title
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 2: Define Tag and the paper_tags row**

Create `Models/Tag.swift`:

```swift
import GRDB

public struct Tag: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public static let databaseTableName = "tags"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
    public init(id: Int64? = nil, name: String) { self.id = id; self.name = name }
}

public struct PaperTag: Codable, FetchableRecord, PersistableRecord {
    public var paperId: Int64
    public var tagId: Int64
    public static let databaseTableName = "paper_tags"
    enum CodingKeys: String, CodingKey { case paperId = "paper_id", tagId = "tag_id" }
}

/// A tag plus how many papers currently use it (for the sidebar).
public struct TagCount: Codable, Hashable, FetchableRecord {
    public var name: String
    public var count: Int
}
```

- [ ] **Step 3: Define the annotation index record**

Create `Models/AnnotationIndex.swift`:

```swift
import GRDB

public struct AnnotationIndex: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var paperId: Int64
    public var page: Int
    public var kind: String          // "highlight" | "note"
    public var color: String         // hex
    public var snippet: String       // text content for the list/search
    public var x: Double             // normalized 0..1 bounds
    public var y: Double
    public var width: Double
    public var height: Double
    public var createdAt: Int64
    public var updatedAt: Int64

    public static let databaseTableName = "pdf_annotations"

    enum CodingKeys: String, CodingKey {
        case id, page, kind, color, snippet, x, y, width, height
        case paperId = "paper_id", createdAt = "created_at", updatedAt = "updated_at"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

- [ ] **Step 4: Build the package to confirm models compile**

Run: `cd NimbleScholarCore && swift build`
Expected: builds with no errors.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Models
git commit -m "feat: add Paper, Tag, AnnotationIndex GRDB models"
```

### Task 2: LibraryStore schema & migrations

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write a failing test for migrations + empty fetch**

Create `LibraryStoreTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter LibraryStoreTests`
Expected: FAIL — `LibraryStore` not found.

- [ ] **Step 3: Implement LibraryStore with migrator**

Create `Store/LibraryStore.swift`:

```swift
import Foundation
import GRDB

public final class LibraryStore {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// On-disk store at ~/Library/Application Support/Nimble Scholar/paper_app.sqlite3
    public static func makeDefault() throws -> LibraryStore {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nimble Scholar", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("paper_app.sqlite3")
        return try LibraryStore(dbQueue: try DatabaseQueue(path: dbURL.path))
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "papers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                for col in ["authors","year","venue","doi","url","pdf_url","pdf_path",
                            "summary","teaser_url","pipeline_url","abstract","notes","source"] {
                    t.column(col, .text).notNull().defaults(to: "")
                }
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
            }
            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }
            try db.create(table: "paper_tags") { t in
                t.column("paper_id", .integer).notNull()
                    .references("papers", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["paper_id", "tag_id"])
            }
            try db.create(table: "pdf_annotations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("paper_id", .integer).notNull()
                    .references("papers", onDelete: .cascade)
                t.column("page", .integer).notNull()
                t.column("kind", .text).notNull().defaults(to: "highlight")
                t.column("color", .text).notNull().defaults(to: "#ffd966")
                t.column("snippet", .text).notNull().defaults(to: "")
                t.column("x", .double).notNull().defaults(to: 0)
                t.column("y", .double).notNull().defaults(to: 0)
                t.column("width", .double).notNull().defaults(to: 0)
                t.column("height", .double).notNull().defaults(to: 0)
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
            }
        }
        m.registerMigration("v2-fts") { db in
            try db.create(virtualTable: "papers_fts", using: FTS5()) { t in
                t.synchronize(withTable: "papers")
                t.column("title"); t.column("authors"); t.column("abstract")
                t.column("summary"); t.column("venue"); t.column("doi")
            }
        }
        return m
    }

    // Minimal reads used by the first test; expanded in Task 3.
    public func allPapers() throws -> [Paper] {
        try dbQueue.read { try Paper.order(Paper.Columns.updatedAt.desc).fetchAll($0) }
    }

    public func tagCounts() throws -> [TagCount] {
        try dbQueue.read { db in
            try TagCount.fetchAll(db, sql: """
                SELECT t.name AS name, COUNT(pt.paper_id) AS count
                FROM tags t JOIN paper_tags pt ON pt.tag_id = t.id
                GROUP BY t.id ORDER BY t.name
            """)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter LibraryStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift
git commit -m "feat: LibraryStore schema, migrations, FTS5"
```

### Task 3: TagNormalizer + paper/tag CRUD + search

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Store/TagNormalizer.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/TagNormalizerTests.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Modify: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write failing TagNormalizer test**

Create `TagNormalizerTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class TagNormalizerTests: XCTestCase {
    func testNormalizeSplitsLowercasesDedupesCollapses() {
        let result = TagNormalizer.normalize("  LLM, llm; Reading List ,, vla ")
        XCTAssertEqual(result, ["llm", "reading list", "vla"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter TagNormalizerTests`
Expected: FAIL — `TagNormalizer` not found.

- [ ] **Step 3: Implement TagNormalizer**

Create `Store/TagNormalizer.swift`:

```swift
public enum TagNormalizer {
    public static func normalize(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out = [String]()
        for piece in raw.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let collapsed = piece.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
                .lowercased()
            guard !collapsed.isEmpty, !seen.contains(collapsed) else { continue }
            seen.insert(collapsed); out.append(collapsed)
        }
        return out
    }

    public static func normalize(_ list: [String]) -> [String] {
        normalize(list.joined(separator: ","))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter TagNormalizerTests`
Expected: PASS.

- [ ] **Step 5: Write failing CRUD + search + tags test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
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
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testCreateSetTagsSearchAndDelete`
Expected: FAIL — `create`/`setTags`/`searchPapers`/`deletePaper` not found.

- [ ] **Step 7: Implement CRUD, tags, and search on LibraryStore**

Add these methods inside `LibraryStore` (below `tagCounts()`):

```swift
    private func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

    @discardableResult
    public func create(_ paper: Paper) throws -> Paper {
        var p = paper
        let ts = now(); p.createdAt = ts; p.updatedAt = ts
        try dbQueue.write { try p.insert($0) }
        return p
    }

    @discardableResult
    public func update(_ paper: Paper) throws -> Paper {
        var p = paper; p.updatedAt = now()
        try dbQueue.write { try p.update($0) }
        return p
    }

    public func deletePaper(id: Int64) throws {
        _ = try dbQueue.write { try Paper.deleteOne($0, key: id) }
    }

    public func tags(forPaper id: Int64) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT t.name FROM tags t
                JOIN paper_tags pt ON pt.tag_id = t.id
                WHERE pt.paper_id = ? ORDER BY t.name
            """, arguments: [id])
        }
    }

    public func setTags(paperID: Int64, tags rawTags: [String]) throws {
        let names = TagNormalizer.normalize(rawTags)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM paper_tags WHERE paper_id = ?", arguments: [paperID])
            for name in names {
                try db.execute(sql: "INSERT OR IGNORE INTO tags(name) VALUES (?)", arguments: [name])
                let tagID = try Int64.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [name])!
                try db.execute(sql: "INSERT OR IGNORE INTO paper_tags(paper_id, tag_id) VALUES (?, ?)",
                               arguments: [paperID, tagID])
            }
            // prune now-orphaned tags so the sidebar stays clean
            try db.execute(sql: """
                DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM paper_tags)
            """)
        }
    }

    public func searchPapers(query: String?, tag: String?) throws -> [Paper] {
        try dbQueue.read { db in
            var sql = "SELECT papers.* FROM papers"
            var args = [DatabaseValueConvertible]()
            var wheres = [String]()
            if let tag, !tag.isEmpty {
                sql += """
                 JOIN paper_tags pt ON pt.paper_id = papers.id
                 JOIN tags t ON t.id = pt.tag_id
                """
                wheres.append("t.name = ?"); args.append(tag)
            }
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                wheres.append("papers.id IN (SELECT rowid FROM papers_fts WHERE papers_fts MATCH ?)")
                args.append(Self.ftsQuery(query))
            }
            if !wheres.isEmpty { sql += " WHERE " + wheres.joined(separator: " AND ") }
            sql += " ORDER BY papers.updated_at DESC"
            return try Paper.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Turn a raw user query into a prefix FTS query: `transformer mod` -> `transformer* mod*`
    static func ftsQuery(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") + "*" }
            .joined(separator: " ")
    }
```

- [ ] **Step 8: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter LibraryStoreTests`
Expected: both store tests PASS.

- [ ] **Step 9: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: tag normalization, paper/tag CRUD, FTS search"
```

### Task 4: Annotation index round-trip

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Modify: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write failing annotation test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testAnnotationIndexRoundTrip`
Expected: FAIL — methods not found.

- [ ] **Step 3: Implement annotation methods on LibraryStore**

Add inside `LibraryStore`:

```swift
    @discardableResult
    public func upsertAnnotation(_ a: inout AnnotationIndex) throws -> AnnotationIndex {
        let ts = now()
        if a.createdAt == 0 { a.createdAt = ts }
        a.updatedAt = ts
        try dbQueue.write { try a.save($0) }
        return a
    }

    public func annotations(forPaper id: Int64) throws -> [AnnotationIndex] {
        try dbQueue.read { db in
            try AnnotationIndex
                .filter(sql: "paper_id = ?", arguments: [id])
                .order(sql: "page ASC, created_at ASC")
                .fetchAll(db)
        }
    }

    public func deleteAnnotation(id: Int64) throws {
        _ = try dbQueue.write { try AnnotationIndex.deleteOne($0, key: id) }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter LibraryStoreTests`
Expected: all store tests PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: annotation index CRUD on LibraryStore"
```

---

## Phase 2 — arXiv, metadata, figures, PDF, BibTeX

### Task 5: ArxivService — ID extraction and PDF URL normalization

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/ArxivService.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/ArxivServiceTests.swift`

- [ ] **Step 1: Write failing tests** (port the Python normalization behaviors)

Create `ArxivServiceTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class ArxivServiceTests: XCTestCase {
    func testExtractID() {
        XCTAssertEqual(ArxivService.extractID(from: "https://arxiv.org/abs/2606.01234"), "2606.01234")
        XCTAssertEqual(ArxivService.extractID(from: "https://arxiv.org/pdf/2606.01234v2"), "2606.01234v2")
        XCTAssertEqual(ArxivService.extractID(from: "arXiv:2606.01234"), "2606.01234")
        XCTAssertNil(ArxivService.extractID(from: "https://example.com/paper"))
    }

    func testPDFURLFromAbs() {
        XCTAssertEqual(ArxivService.normalizedPDFURL(absOrID: "https://arxiv.org/abs/2606.01234"),
                       "https://arxiv.org/pdf/2606.01234")
        XCTAssertEqual(ArxivService.normalizedPDFURL(absOrID: "2606.01234"),
                       "https://arxiv.org/pdf/2606.01234")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter ArxivServiceTests`
Expected: FAIL — `ArxivService` not found.

- [ ] **Step 3: Implement ArxivService**

Create `Services/ArxivService.swift`:

```swift
import Foundation

public enum ArxivService {
    /// Matches 2606.01234 or 2606.01234v3 anywhere in the string (also after "arXiv:").
    public static func extractID(from text: String) -> String? {
        let pattern = #"(\d{4}\.\d{4,5}(v\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        // Only treat as arXiv if it looks like an arxiv context.
        let lower = text.lowercased()
        if lower.contains("arxiv") || lower.hasPrefix(String(text[r])) || lower == String(text[r]) {
            return String(text[r])
        }
        return text.contains("arxiv") ? String(text[r]) : (lower.contains("/abs/") || lower.contains("/pdf/") ? String(text[r]) : (isBareID(text) ? String(text[r]) : nil))
    }

    private static func isBareID(_ s: String) -> Bool {
        (try? NSRegularExpression(pattern: #"^\s*\d{4}\.\d{4,5}(v\d+)?\s*$"#))?
            .firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    public static func normalizedPDFURL(absOrID: String) -> String? {
        guard let id = extractID(from: absOrID) else { return nil }
        return "https://arxiv.org/pdf/\(id)"
    }

    public static func absURL(forID id: String) -> String { "https://arxiv.org/abs/\(id)" }
    public static func htmlURL(forID id: String) -> String { "https://arxiv.org/html/\(id)" }
    public static func apiURL(forID id: String) -> URL {
        URL(string: "https://export.arxiv.org/api/query?id_list=\(id)")!
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter ArxivServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/ArxivService.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/ArxivServiceTests.swift
git commit -m "feat: arXiv id extraction + pdf url normalization"
```

### Task 6: MetadataService — parse arXiv Atom & generic meta

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/MetadataService.swift`
- Create fixtures: `NimbleScholarCore/Tests/NimbleScholarCoreTests/Fixtures/arxiv_atom.xml`, `Fixtures/generic_meta.html`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MetadataServiceTests.swift`

- [ ] **Step 1: Add fixtures**

Create `Fixtures/arxiv_atom.xml`:

```xml
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Deep Residual Learning for Image Recognition</title>
    <summary>We present a residual learning framework.</summary>
    <author><name>Kaiming He</name></author>
    <author><name>Xiangyu Zhang</name></author>
    <published>2015-12-10T00:00:00Z</published>
  </entry>
</feed>
```

Create `Fixtures/generic_meta.html`:

```html
<html><head>
<meta name="citation_title" content="A Generic Paper Title">
<meta name="citation_author" content="Jane Smith">
<meta name="citation_author" content="Wei Chen">
<meta name="citation_doi" content="10.1000/xyz">
<meta name="description" content="An abstract here.">
</head><body></body></html>
```

- [ ] **Step 2: Write failing tests**

Create `MetadataServiceTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class MetadataServiceTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParseArxivAtom() throws {
        let meta = try MetadataService.parseArxivAtom(try fixture("arxiv_atom.xml"))
        XCTAssertEqual(meta.title, "Deep Residual Learning for Image Recognition")
        XCTAssertEqual(meta.authors, "Kaiming He, Xiangyu Zhang")
        XCTAssertEqual(meta.year, "2015")
        XCTAssertTrue(meta.abstract.contains("residual learning"))
    }

    func testParseGenericMeta() throws {
        let meta = try MetadataService.parseGenericMeta(try fixture("generic_meta.html"))
        XCTAssertEqual(meta.title, "A Generic Paper Title")
        XCTAssertEqual(meta.authors, "Jane Smith, Wei Chen")
        XCTAssertEqual(meta.doi, "10.1000/xyz")
        XCTAssertEqual(meta.abstract, "An abstract here.")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter MetadataServiceTests`
Expected: FAIL — `MetadataService` not found.

- [ ] **Step 4: Implement MetadataService**

Create `Services/MetadataService.swift`:

```swift
import Foundation
import SwiftSoup

public struct PaperMetadata {
    public var title = ""
    public var authors = ""
    public var year = ""
    public var doi = ""
    public var abstract = ""
    public var pdfURL = ""
    public var teaserURL = ""
}

public enum MetadataService {
    /// Parse arXiv API Atom XML with a tiny streaming XML parser.
    public static func parseArxivAtom(_ data: Data) throws -> PaperMetadata {
        final class Delegate: NSObject, XMLParserDelegate {
            var element = ""
            var title = "", summary = "", published = ""
            var authors = [String]()
            var inAuthor = false, authorName = ""
            func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String:String]) {
                element = e
                if e == "author" { inAuthor = true; authorName = "" }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) {
                switch element {
                case "title": title += s
                case "summary": summary += s
                case "published": published += s
                case "name" where inAuthor: authorName += s
                default: break
                }
            }
            func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                if e == "author" { authors.append(authorName.trimmingCharacters(in: .whitespacesAndNewlines)); inAuthor = false }
                element = ""
            }
        }
        let parser = XMLParser(data: data)
        let d = Delegate(); parser.delegate = d; parser.parse()
        var meta = PaperMetadata()
        meta.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.abstract = d.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.authors = d.authors.filter { !$0.isEmpty }.joined(separator: ", ")
        meta.year = String(d.published.prefix(4))
        return meta
    }

    /// Parse generic publisher pages via citation_* and og: meta tags.
    public static func parseGenericMeta(_ data: Data) throws -> PaperMetadata {
        let html = String(decoding: data, as: UTF8.self)
        let doc = try SwiftSoup.parse(html)
        func meta(_ names: [String]) throws -> String {
            for n in names {
                if let el = try doc.select("meta[name=\(n)], meta[property=\(n)]").first() {
                    let c = try el.attr("content")
                    if !c.isEmpty { return c }
                }
            }
            return ""
        }
        var m = PaperMetadata()
        m.title = try meta(["citation_title", "og:title"])
        if m.title.isEmpty { m.title = try doc.title() }
        m.authors = try doc.select("meta[name=citation_author]")
            .map { try $0.attr("content") }.filter { !$0.isEmpty }.joined(separator: ", ")
        m.doi = try meta(["citation_doi"])
        m.abstract = try meta(["description", "og:description"])
        m.pdfURL = try meta(["citation_pdf_url"])
        m.teaserURL = try meta(["og:image", "twitter:image"])
        return m
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter MetadataServiceTests`
Expected: PASS. (If `Bundle.module` resource lookup fails, keep only the `subdirectory: "Fixtures"` form in the helper.)

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: MetadataService arXiv Atom + generic meta parsing"
```

### Task 7: FigureChooser — teaser/pipeline heuristic

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/FigureChooser.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/FigureChooserTests.swift`

- [ ] **Step 1: Write failing test** (ports `choose_arxiv_visual` priorities)

Create `FigureChooserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter FigureChooserTests`
Expected: FAIL — `Figure`/`FigureChooser` not found.

- [ ] **Step 3: Implement FigureChooser**

Create `Services/FigureChooser.swift`:

```swift
public struct Figure: Equatable {
    public let url: String
    public let alt: String
    public let caption: String
    public init(url: String, alt: String, caption: String) {
        self.url = url; self.alt = alt; self.caption = caption
    }
}

public enum FigureChooser {
    public struct Result { public var teaser: String?; public var pipeline: String? }

    private static let placeholders = ["logo", "favicon", "icon", "static", "browse", "arxiv-logo"]
    private static let teaserWords = ["teaser", "overview", "result", "qualitative"]
    private static let pipelineWords = ["pipeline", "method", "architecture", "framework", "overview of"]

    public static func choose(from figures: [Figure]) -> Result {
        let valid = figures.filter { f in
            let hay = (f.url + " " + f.alt).lowercased()
            return !placeholders.contains { hay.contains($0) }
        }
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter FigureChooserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/FigureChooser.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/FigureChooserTests.swift
git commit -m "feat: FigureChooser teaser/pipeline heuristic"
```

### Task 8: BibTeXExporter

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/BibTeXExporter.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/BibTeXExporterTests.swift`

- [ ] **Step 1: Write failing test**

Create `BibTeXExporterTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class BibTeXExporterTests: XCTestCase {
    func testExportsEntryWithKeyAndFields() {
        var p = Paper(id: 1, title: "Attention Is All You Need")
        p.authors = "Vaswani, Ashish"; p.year = "2017"; p.venue = "NeurIPS"
        let bib = BibTeXExporter.export([p])
        XCTAssertTrue(bib.contains("@article{vaswani2017"))
        XCTAssertTrue(bib.contains("title = {Attention Is All You Need}"))
        XCTAssertTrue(bib.contains("year = {2017}"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter BibTeXExporterTests`
Expected: FAIL — `BibTeXExporter` not found.

- [ ] **Step 3: Implement BibTeXExporter**

Create `Services/BibTeXExporter.swift`:

```swift
import Foundation

public enum BibTeXExporter {
    public static func export(_ papers: [Paper]) -> String {
        papers.map(entry).joined(separator: "\n\n") + "\n"
    }

    static func entry(_ p: Paper) -> String {
        var lines = ["@article{\(citeKey(p)),"]
        func field(_ k: String, _ v: String) { if !v.isEmpty { lines.append("  \(k) = {\(v)},") } }
        field("title", p.title)
        field("author", p.authors)
        field("year", p.year)
        field("journal", p.venue)
        field("doi", p.doi)
        field("url", p.url)
        if lines.last?.hasSuffix(",") == true { lines[lines.count - 1].removeLast() }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func citeKey(_ p: Paper) -> String {
        let lastName = p.authors.split(separator: ",").first
            .map { $0.split(separator: " ").first.map(String.init) ?? String($0) } ?? "anon"
        let surname = lastName.lowercased().filter { $0.isLetter }
        return "\(surname.isEmpty ? "anon" : surname)\(p.year)"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter BibTeXExporterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/BibTeXExporter.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/BibTeXExporterTests.swift
git commit -m "feat: BibTeX exporter"
```

### Task 9: ArxivFigureService & PDFDownloader (network wrappers)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/ArxivFigureService.swift`
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/PDFDownloader.swift`

> These wrap `URLSession`; their pure logic (figure choice, URL normalization, PDF magic-byte check) is already unit-tested. We add one offline test for the PDF validator.

- [ ] **Step 1: Write failing PDF-validator test**

Append a new file `NimbleScholarCore/Tests/NimbleScholarCoreTests/PDFDownloaderTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class PDFDownloaderTests: XCTestCase {
    func testLooksLikePDF() {
        XCTAssertTrue(PDFDownloader.looksLikePDF(Data("%PDF-1.7\n...".utf8)))
        XCTAssertFalse(PDFDownloader.looksLikePDF(Data("<html>".utf8)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter PDFDownloaderTests`
Expected: FAIL — `PDFDownloader` not found.

- [ ] **Step 3: Implement PDFDownloader**

Create `Services/PDFDownloader.swift`:

```swift
import Foundation

public struct PDFDownloader {
    public let session: URLSession
    public let cacheDir: URL
    public init(session: URLSession = .shared, cacheDir: URL) {
        self.session = session; self.cacheDir = cacheDir
    }

    public static func looksLikePDF(_ data: Data) -> Bool {
        data.starts(with: Array("%PDF".utf8))
    }

    public static func safeName(for paper: Paper) -> String {
        let base = (ArxivService.extractID(from: paper.url) ?? paper.title)
            .lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(base).prefix(80)) + ".pdf"
    }

    /// Downloads to cacheDir if not present; returns the local file path.
    public func ensureLocalPDF(for paper: Paper, overwrite: Bool = false) async throws -> URL {
        let dest = cacheDir.appendingPathComponent(Self.safeName(for: paper))
        if !overwrite, FileManager.default.fileExists(atPath: dest.path) { return dest }
        let urlString = !paper.pdfURL.isEmpty ? paper.pdfURL
            : (ArxivService.normalizedPDFURL(absOrID: paper.url) ?? paper.url)
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        guard Self.looksLikePDF(data) else { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: dest)
        return dest
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter PDFDownloaderTests`
Expected: PASS.

- [ ] **Step 5: Implement ArxivFigureService**

Create `Services/ArxivFigureService.swift`:

```swift
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
```

- [ ] **Step 6: Build to confirm it compiles**

Run: `cd NimbleScholarCore && swift build`
Expected: builds clean.

- [ ] **Step 7: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: PDFDownloader + ArxivFigureService network wrappers"
```

---

## Phase 3 — Capture pipeline & embedded server

### Task 10: CapturePayload + CaptureHandler

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Models/CapturePayload.swift`
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Capture/CaptureHandler.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/CaptureHandlerTests.swift`

- [ ] **Step 1: Define the capture payload (matches the extension's JSON)**

Create `Models/CapturePayload.swift`:

```swift
public struct CapturePayload: Codable {
    public var url: String = ""
    public var title: String?
    public var authors: String?
    public var doi: String?
    public var pdf_url: String?
    public var teaser_url: String?
    public var abstract: String?
    public var source: String?
    public var tags: String?     // comma/semicolon separated, like today
}
```

- [ ] **Step 2: Write a failing handler test** (offline: inject metadata)

Create `CaptureHandlerTests.swift`:

```swift
import XCTest
import GRDB
@testable import NimbleScholarCore

final class CaptureHandlerTests: XCTestCase {
    func testCaptureCreatesPaperWithTagsAndMetadataMerge() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        // Resolver returns metadata for the URL (stubbed — no network).
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata()
            m.title = "Resolved Title"; m.authors = "A. Author"; m.year = "2026"
            m.abstract = "resolved abstract"
            return m
        }
        var payload = CapturePayload()
        payload.url = "https://arxiv.org/abs/2606.01234"
        payload.tags = "to-read, vla"
        let paper = try await handler.capture(payload)

        XCTAssertEqual(paper.title, "Resolved Title")
        XCTAssertEqual(paper.pdfURL, "https://arxiv.org/pdf/2606.01234")
        XCTAssertEqual(Set(try store.tags(forPaper: paper.id!)), ["to-read", "vla"])
        XCTAssertEqual(try store.allPapers().count, 1)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter CaptureHandlerTests`
Expected: FAIL — `CaptureHandler` not found.

- [ ] **Step 4: Implement CaptureHandler**

Create `Capture/CaptureHandler.swift`:

```swift
import Foundation

public final class CaptureHandler {
    public typealias Resolver = (String) async throws -> PaperMetadata

    let store: LibraryStore
    let resolve: Resolver

    public init(store: LibraryStore, resolve: @escaping Resolver) {
        self.store = store; self.resolve = resolve
    }

    @discardableResult
    public func capture(_ payload: CapturePayload) async throws -> Paper {
        let meta = (try? await resolve(payload.url)) ?? PaperMetadata()
        var p = Paper(title: payload.title?.nonEmpty ?? meta.title.nonEmpty ?? payload.url)
        p.authors = payload.authors?.nonEmpty ?? meta.authors
        p.year = meta.year
        p.doi = payload.doi?.nonEmpty ?? meta.doi
        p.url = payload.url
        p.abstract = payload.abstract?.nonEmpty ?? meta.abstract
        p.source = payload.source ?? ""
        p.teaserURL = payload.teaser_url?.nonEmpty ?? meta.teaserURL
        p.pdfURL = payload.pdf_url?.nonEmpty
            ?? ArxivService.normalizedPDFURL(absOrID: payload.url)
            ?? meta.pdfURL
        let saved = try store.create(p)
        if let tags = payload.tags { try store.setTags(paperID: saved.id!, tags: TagNormalizer.normalize(tags)) }
        return saved
    }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter CaptureHandlerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: CaptureHandler merges payload + resolved metadata into a Paper"
```

### Task 11: CaptureServer (FlyingFox loopback)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Capture/CaptureServer.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/CaptureServerTests.swift`

- [ ] **Step 1: Write a failing end-to-end server test**

Create `CaptureServerTests.swift`:

```swift
import XCTest
import GRDB
import FlyingFox
@testable import NimbleScholarCore

final class CaptureServerTests: XCTestCase {
    func testPostApiCaptureCreatesPaper() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "Served"; return m
        }
        let server = CaptureServer(port: 8799, handler: handler)
        let task = Task { try await server.run() }
        defer { task.cancel() }
        try await server.waitUntilListening()

        var req = URLRequest(url: URL(string: "http://127.0.0.1:8799/api/capture")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = #"{"url":"https://arxiv.org/abs/2606.01234","tags":"x"}"#.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"ok\":true"))
        XCTAssertEqual(try store.allPapers().count, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter CaptureServerTests`
Expected: FAIL — `CaptureServer` not found.

- [ ] **Step 3: Implement CaptureServer**

Create `Capture/CaptureServer.swift`:

```swift
import Foundation
import FlyingFox

public final class CaptureServer {
    let server: HTTPServer
    let handler: CaptureHandler

    public init(port: UInt16 = 8765, handler: CaptureHandler) {
        self.handler = handler
        self.server = HTTPServer(address: .loopback(port: port))
        Task { await registerRoutes() }
    }

    private func registerRoutes() async {
        let h = handler
        await server.appendRoute("OPTIONS *") { _ in
            HTTPResponse(statusCode: .noContent, headers: Self.cors)
        }
        await server.appendRoute("POST /api/capture") { req in
            do {
                let body = try await req.bodyData
                let payload = try JSONDecoder().decode(CapturePayload.self, from: body)
                let paper = try await h.capture(payload)
                let json = try JSONEncoder().encode(["ok": true, "id": paper.id ?? -1] as [String: Int64Convertible])
                return HTTPResponse(statusCode: .ok, headers: Self.json, body: json)
            } catch {
                let json = Data(#"{"ok":false,"error":"capture failed"}"#.utf8)
                return HTTPResponse(statusCode: .badRequest, headers: Self.json, body: json)
            }
        }
    }

    static let cors: [HTTPHeader: String] = [
        .init(rawValue: "Access-Control-Allow-Origin"): "*",
        .init(rawValue: "Access-Control-Allow-Methods"): "GET, POST, PUT, DELETE, OPTIONS",
        .init(rawValue: "Access-Control-Allow-Headers"): "Content-Type",
    ]
    static var json: [HTTPHeader: String] {
        var h = cors; h[.contentType] = "application/json"; return h
    }

    public func run() async throws { try await server.run() }
    public func waitUntilListening() async throws { try await server.waitUntilListening() }
}

/// Tiny helper so we can JSON-encode a mixed bool/int dictionary as numbers.
protocol Int64Convertible: Encodable {}
extension Bool: Int64Convertible {}
extension Int64: Int64Convertible {}
```

> If FlyingFox's current API differs (e.g. `bodyData` vs `bodyString`, header types), adjust to the installed version — the route shape stays the same. The `Int64Convertible` shim is only to emit `{"ok":true,...}`; you may instead encode a small `struct CaptureResponse: Codable { let ok: Bool; let id: Int64 }`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter CaptureServerTests`
Expected: PASS (server boots on 8799, accepts the POST, paper row created).

- [ ] **Step 5: Run the full core suite**

Run: `cd NimbleScholarCore && swift test`
Expected: ALL core tests PASS. This is the green-light that the entire non-UI backend works before touching UI.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore
git commit -m "feat: embedded FlyingFox capture server with /api/capture"
```

---

## Phase 4 — App shell & library window

> From here, work happens in the **Xcode app target**. Verification is **build + run on Mac**, not unit tests.

### Task 12: Create the Xcode app target and wire the core package

**Files:**
- Create: `NimbleScholar.xcodeproj` (via Xcode GUI)
- Create: `NimbleScholar/NimbleScholarApp.swift`
- Create: `NimbleScholar/AppEnvironment.swift`

- [ ] **Step 1: Create the app project**

In Xcode: File ▸ New ▸ Project ▸ macOS ▸ App. Product name `NimbleScholar`, interface SwiftUI, language Swift, location = repo root (so it sits beside `NimbleScholarCore/`). Set deployment target macOS 14.0.

- [ ] **Step 2: Add the local package dependency**

In Xcode: File ▸ Add Package Dependencies ▸ Add Local… ▸ select `NimbleScholarCore/`. Add the `NimbleScholarCore` library to the `NimbleScholar` target.

- [ ] **Step 3: Add the shared app environment**

Create `NimbleScholar/AppEnvironment.swift`:

```swift
import Foundation
import NimbleScholarCore

@MainActor
final class AppEnvironment: ObservableObject {
    let store: LibraryStore
    let figures = ArxivFigureService()
    let downloader: PDFDownloader
    var captureServer: CaptureServer?

    init() {
        // Crash-fast on first run is acceptable; surface errors in UI later.
        self.store = try! LibraryStore.makeDefault()
        let cache = (try! FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            .appendingPathComponent("Nimble Scholar/storage/pdfs", isDirectory: true)
        self.downloader = PDFDownloader(cacheDir: cache)
        startCaptureServer()
    }

    private func startCaptureServer() {
        let handler = CaptureHandler(store: store) { url in
            // arXiv first, then generic meta fallback
            if let id = ArxivService.extractID(from: url) {
                let (data, _) = try await URLSession.shared.data(from: ArxivService.apiURL(forID: id))
                return try MetadataService.parseArxivAtom(data)
            }
            let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
            return try MetadataService.parseGenericMeta(data)
        }
        let server = CaptureServer(port: 8765, handler: handler)
        self.captureServer = server
        Task { try? await server.run() }
    }
}
```

- [ ] **Step 4: Wire the app entry point**

Replace `NimbleScholar/NimbleScholarApp.swift`:

```swift
import SwiftUI
import NimbleScholarCore

@main
struct NimbleScholarApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup("Nimble Scholar") {
            LibraryContentView().environmentObject(env)
        }
        .windowToolbarStyle(.unified)

        WindowGroup("Reader", id: "reader", for: Int64.self) { $paperID in
            ReaderWindow(paperID: paperID).environmentObject(env)
        }

        Settings { SettingsView().environmentObject(env) }
    }
}
```

> `LibraryContentView`, `ReaderWindow`, and `SettingsView` are created in later tasks. To make this compile now, add temporary empty stubs (`struct LibraryContentView: View { var body: some View { Text("Library") } }`, etc.) and delete them as the real views land.

- [ ] **Step 5: VERIFY ON MAC**

Run: `xcodebuild -scheme NimbleScholar -destination 'platform=macOS' build`
Expected: builds. Launch the app — an empty "Library" window appears. Confirm `~/Library/Application Support/Nimble Scholar/paper_app.sqlite3` is created.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholar NimbleScholar.xcodeproj
git commit -m "feat: Xcode app target, core package wiring, capture server boot"
```

### Task 13: LibraryViewModel + sidebar + view-mode switcher

**Files:**
- Create: `NimbleScholar/Library/LibraryViewModel.swift`
- Create: `NimbleScholar/Library/TagColor.swift`
- Create: `NimbleScholar/Library/SidebarView.swift`
- Create: `NimbleScholar/Library/LibraryContentView.swift` (replaces stub)

- [ ] **Step 1: Implement the view model**

Create `NimbleScholar/Library/LibraryViewModel.swift`:

```swift
import SwiftUI
import NimbleScholarCore

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var papers: [Paper] = []
    @Published var tagCounts: [TagCount] = []
    @Published var query = "" { didSet { reload() } }
    @Published var selectedTag: String? = nil { didSet { reload() } }
    @Published var selection: Paper.ID? = nil

    private let store: LibraryStore
    init(store: LibraryStore) { self.store = store; reload() }

    func reload() {
        papers = (try? store.searchPapers(query: query, tag: selectedTag)) ?? []
        tagCounts = (try? store.tagCounts()) ?? []
    }

    func tags(for paper: Paper) -> [String] {
        guard let id = paper.id else { return [] }
        return (try? store.tags(forPaper: id)) ?? []
    }
    func addTag(_ tag: String, to paper: Paper) {
        guard let id = paper.id else { return }
        let current = (try? store.tags(forPaper: id)) ?? []
        try? store.setTags(paperID: id, tags: current + [tag]); reload()
    }
    func removeTag(_ tag: String, from paper: Paper) {
        guard let id = paper.id else { return }
        let current = ((try? store.tags(forPaper: id)) ?? []).filter { $0 != tag }
        try? store.setTags(paperID: id, tags: current); reload()
    }
    func saveSummary(_ text: String, for paper: Paper) {
        var p = paper; p.summary = text; _ = try? store.update(p); reload()
    }
    func delete(_ paper: Paper) {
        if let id = paper.id { try? store.deletePaper(id: id); reload() }
    }
    func save(_ paper: Paper) { _ = try? (paper.id == nil ? store.create(paper) : store.update(paper)); reload() }
}
```

- [ ] **Step 2: Implement deterministic tag colors** (port today's hue scheme)

Create `NimbleScholar/Library/TagColor.swift`:

```swift
import SwiftUI

enum TagColor {
    static func color(for name: String) -> Color {
        var hash = 5381
        for b in name.utf8 { hash = ((hash << 5) &+ hash) &+ Int(b) }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
}
```

- [ ] **Step 3: Implement the sidebar**

Create `NimbleScholar/Library/SidebarView.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct SidebarView: View {
    @EnvironmentObject var vm: LibraryViewModel
    var body: some View {
        List(selection: $vm.selectedTag) {
            Section {
                Label("All papers", systemImage: "tray.full").tag(String?.none)
            }
            Section("Tags") {
                ForEach(vm.tagCounts, id: \.name) { tc in
                    HStack {
                        Circle().fill(TagColor.color(for: tc.name)).frame(width: 8, height: 8)
                        Text(tc.name); Spacer()
                        Text("\(tc.count)").foregroundStyle(.secondary)
                    }.tag(String?.some(tc.name))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
```

- [ ] **Step 4: Implement the content view with the switcher**

Create `NimbleScholar/Library/LibraryContentView.swift` (delete the earlier stub):

```swift
import SwiftUI
import NimbleScholarCore

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case threePane, gallery, rows
    var id: String { rawValue }
    var label: String { ["threePane":"Three-pane","gallery":"Gallery","rows":"Rows"][rawValue]! }
    var symbol: String { ["threePane":"sidebar.right","gallery":"square.grid.2x2","rows":"list.bullet"][rawValue]! }
}

struct LibraryContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm: LibraryViewModel
    @AppStorage("libraryViewMode") private var mode: LibraryViewMode = .threePane
    @State private var editing: Paper? = nil
    @State private var capturing = false

    init() { _vm = StateObject(wrappedValue: LibraryViewModel(store: AppEnvironment.shared.store)) }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Group {
                switch mode {
                case .threePane: ThreePaneView()
                case .gallery: GalleryView()
                case .rows: RowsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(LibraryViewMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }.pickerStyle(.segmented)
                }
                ToolbarItem { Button { capturing = true } label: { Label("Capture", systemImage: "link.badge.plus") } }
                ToolbarItem { Button { editing = Paper(title: "") } label: { Label("Add", systemImage: "plus") } }
            }
            .searchable(text: $vm.query, prompt: "Search papers, authors, DOI, tags")
        }
        .environmentObject(vm)
        .sheet(item: $editing) { PaperEditSheet(paper: $0).environmentObject(vm) }
        .sheet(isPresented: $capturing) { CaptureSheet().environmentObject(env).environmentObject(vm) }
    }
}
```

> Add a shared accessor so the view model can reach the store at init. In `AppEnvironment.swift`, add `static let shared = AppEnvironment()` and use that single instance in `NimbleScholarApp` (`@StateObject private var env = AppEnvironment.shared` won't work directly; instead make `AppEnvironment.shared` the source and inject it). Simplest: change `@StateObject private var env = AppEnvironment()` to `private let env = AppEnvironment.shared` and pass `env` in. Keep one instance app-wide so the capture server and UI share the same store.

- [ ] **Step 5: VERIFY ON MAC**

Add temporary stubs for `ThreePaneView`, `GalleryView`, `RowsView`, `PaperEditSheet`, `CaptureSheet` returning `Text(...)` so it builds. Run the app. Confirm: sidebar shows "All papers", the segmented switcher appears and flips the center text, search field present.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholar/Library NimbleScholar/AppEnvironment.swift
git commit -m "feat: library view model, sidebar, view-mode switcher"
```

### Task 14: The three library view modes + detail + sheets

**Files:**
- Create: `NimbleScholar/Library/PaperDetailView.swift`
- Create: `NimbleScholar/Library/ThreePaneView.swift`
- Create: `NimbleScholar/Library/RowsView.swift`
- Create: `NimbleScholar/Library/GalleryView.swift`
- Create: `NimbleScholar/Library/PaperEditSheet.swift`
- Create: `NimbleScholar/Library/CaptureSheet.swift`

- [ ] **Step 1: Detail view** (shared by Three-pane and Gallery)

Create `PaperDetailView.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct PaperDetailView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    let paper: Paper
    @State private var newTag = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let img = URL(string: paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL),
                   !(paper.teaserURL.isEmpty && paper.pipelineURL.isEmpty) {
                    AsyncImage(url: img) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.1) }
                        .frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(paper.title).font(.title2).bold()
                Text([paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                HStack {
                    Button { if let id = paper.id { openWindow(id: "reader", value: id) } } label: {
                        Label("Read", systemImage: "book")
                    }.buttonStyle(.borderedProminent)
                    Button("Browser") { if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) { NSWorkspace.shared.open(u) } }
                }
                FlowTags(tags: vm.tags(for: paper),
                         onRemove: { vm.removeTag($0, from: paper) })
                HStack {
                    TextField("+ tag", text: $newTag).onSubmit {
                        if !newTag.isEmpty { vm.addTag(newTag, to: paper); newTag = "" }
                    }
                }
                if !paper.abstract.isEmpty {
                    Text(paper.abstract).font(.callout).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FlowTags: View {
    let tags: [String]; let onRemove: (String) -> Void
    var body: some View {
        HStack { ForEach(tags, id: \.self) { tag in
            HStack(spacing: 4) {
                Circle().fill(TagColor.color(for: tag)).frame(width: 6, height: 6)
                Text(tag).font(.caption)
                Button { onRemove(tag) } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                    .buttonStyle(.plain)
            }.padding(.horizontal, 8).padding(.vertical, 3)
             .background(Capsule().fill(.quaternary))
        } }
    }
}
```

- [ ] **Step 2: Three-pane view**

Create `ThreePaneView.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel
    var body: some View {
        NavigationSplitView {
            List(vm.papers, selection: $vm.selection) { paper in
                VStack(alignment: .leading) {
                    Text(paper.title).lineLimit(2).font(.headline)
                    Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.tag(paper.id)
            }.frame(minWidth: 260)
        } detail: {
            if let id = vm.selection, let paper = vm.papers.first(where: { $0.id == id }) {
                PaperDetailView(paper: paper)
            } else { Text("Select a paper").foregroundStyle(.secondary) }
        }
    }
}
```

- [ ] **Step 3: Rows view**

Create `RowsView.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct RowsView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.papers) { paper in
                    HStack(alignment: .top, spacing: 14) {
                        if let u = URL(string: paper.teaserURL), !paper.teaserURL.isEmpty {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }
                                .frame(width: 160, height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(paper.title).font(.headline)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary)
                            if !paper.summary.isEmpty { Text(paper.summary).font(.callout) }
                            FlowTags(tags: vm.tags(for: paper), onRemove: { vm.removeTag($0, from: paper) })
                        }
                        Spacer()
                        Button("Read") { if let id = paper.id { openWindow(id: "reader", value: id) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
                }
            }.padding(20)
        }
    }
}
```

- [ ] **Step 4: Gallery view**

Create `GalleryView.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct GalleryView: View {
    @EnvironmentObject var vm: LibraryViewModel
    let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.papers) { paper in
                    VStack(alignment: .leading, spacing: 6) {
                        AsyncImage(url: URL(string: paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL)) {
                            $0.resizable().scaledToFill()
                        } placeholder: { Color.gray.opacity(0.1) }
                        .frame(height: 130).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(paper.title).font(.subheadline).bold().lineLimit(2)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
                    .onTapGesture { vm.selection = paper.id }
                }
            }.padding(20)
        }
    }
}
```

- [ ] **Step 5: Edit sheet**

Create `PaperEditSheet.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct PaperEditSheet: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State var paper: Paper
    init(paper: Paper) { _paper = State(initialValue: paper) }

    var body: some View {
        VStack {
            Form {
                TextField("Title", text: $paper.title)
                TextField("Authors", text: $paper.authors)
                TextField("Year", text: $paper.year)
                TextField("Venue", text: $paper.venue)
                TextField("DOI / arXiv ID", text: $paper.doi)
                TextField("URL", text: $paper.url)
                TextField("PDF URL", text: $paper.pdfURL)
                TextField("Summary", text: $paper.summary)
                TextField("Abstract", text: $paper.abstract, axis: .vertical).lineLimit(4...)
            }.formStyle(.grouped)
            HStack {
                if paper.id != nil { Button("Delete", role: .destructive) { vm.delete(paper); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { vm.save(paper); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 560, height: 560)
    }
}
```

- [ ] **Step 6: Capture sheet**

Create `CaptureSheet.swift`:

```swift
import SwiftUI
import NimbleScholarCore

struct CaptureSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""; @State private var tags = ""; @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Capture URL").font(.headline)
            TextField("https://arxiv.org/abs/…", text: $url)
            TextField("Tags (comma separated)", text: $tags)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(busy ? "Saving…" : "Capture") { capture() }
                    .keyboardShortcut(.defaultAction).disabled(busy || url.isEmpty)
            }
        }.padding(20).frame(width: 460)
    }

    private func capture() {
        busy = true
        Task {
            var payload = CapturePayload(); payload.url = url; payload.tags = tags
            let handler = CaptureHandler(store: env.store) { u in
                if let id = ArxivService.extractID(from: u) {
                    let (d, _) = try await URLSession.shared.data(from: ArxivService.apiURL(forID: id))
                    return try MetadataService.parseArxivAtom(d)
                }
                let (d, _) = try await URLSession.shared.data(from: URL(string: u)!)
                return try MetadataService.parseGenericMeta(d)
            }
            _ = try? await handler.capture(payload)
            await MainActor.run { vm.reload(); busy = false; dismiss() }
        }
    }
}
```

- [ ] **Step 7: VERIFY ON MAC**

Build & run. Capture an arXiv URL → a paper appears. Switch among Three-pane / Gallery / Rows — each renders the same library. Add/remove a tag (sidebar count updates), edit a paper, delete a paper. Quit and relaunch → the view mode is remembered.

- [ ] **Step 8: Commit**

```bash
git add NimbleScholar/Library
git commit -m "feat: three library view modes, detail, edit + capture sheets"
```

---

## Phase 5 — Reader window

### Task 15: PDFKitView + ReaderViewModel + ReaderWindow shell

**Files:**
- Create: `NimbleScholar/Reader/PDFKitView.swift`
- Create: `NimbleScholar/Reader/ReaderViewModel.swift`
- Create: `NimbleScholar/Reader/ReaderWindow.swift` (replaces stub)

- [ ] **Step 1: Wrap PDFView**

Create `PDFKitView.swift`:

```swift
import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayMode
    let onReady: (PDFView) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = displayMode
        v.displayDirection = .vertical
        v.usePageViewController(false)
        onReady(v)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
        v.displayMode = displayMode
    }
}
```

- [ ] **Step 2: Reader view model**

Create `ReaderViewModel.swift`:

```swift
import SwiftUI
import PDFKit
import NimbleScholarCore

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var status = "Loading…"
    @Published var annotations: [AnnotationIndex] = []
    let paper: Paper
    let store: LibraryStore
    let downloader: PDFDownloader
    var localURL: URL?

    init(paper: Paper, store: LibraryStore, downloader: PDFDownloader) {
        self.paper = paper; self.store = store; self.downloader = downloader
    }

    func load() async {
        do {
            let url = try await downloader.ensureLocalPDF(for: paper)
            self.localURL = url
            self.document = PDFDocument(url: url)
            self.status = document == nil ? "Could not open PDF" : "Ready"
            if let id = paper.id { self.annotations = (try? store.annotations(forPaper: id)) ?? [] }
        } catch {
            self.status = "PDF unavailable — use Browser"
        }
    }
}
```

- [ ] **Step 3: Reader window shell with layout A**

Create `ReaderWindow.swift` (delete the stub):

```swift
import SwiftUI
import PDFKit
import NimbleScholarCore

struct ReaderWindow: View {
    @EnvironmentObject var env: AppEnvironment
    let paperID: Int64?
    @StateObject private var vm: ReaderViewModel
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var showThumbs = true
    @State private var showInspector = true
    @State private var pdfView: PDFView?

    init(paperID: Int64?) {
        self.paperID = paperID
        let env = AppEnvironment.shared
        let paper = (try? env.store.searchPapers(query: nil, tag: nil))?.first { $0.id == paperID }
            ?? Paper(title: "")
        _vm = StateObject(wrappedValue: ReaderViewModel(paper: paper, store: env.store, downloader: env.downloader))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showThumbs, let pv = pdfView { ThumbnailSidebar(pdfView: pv).frame(width: 140) }
            Group {
                if let doc = vm.document {
                    PDFKitView(document: doc, displayMode: $displayMode) { self.pdfView = $0 }
                } else { ContentUnavailableView(vm.status, systemImage: "doc.richtext") }
            }.frame(minWidth: 420)
        }
        .toolbar { ReaderToolbar(pdfView: $pdfView, displayMode: $displayMode,
                                 showThumbs: $showThumbs, showInspector: $showInspector,
                                 vm: vm) }
        .inspector(isPresented: $showInspector) {
            if let pv = pdfView { InspectorPanel(pdfView: pv, vm: vm) } else { Text("—") }
        }
        .navigationTitle(vm.paper.title)
        .task { await vm.load() }
    }
}
```

- [ ] **Step 4: VERIFY ON MAC**

Add temporary stubs for `ThumbnailSidebar`, `ReaderToolbar`, `InspectorPanel`. Build & run, click **Read** on a paper → a reader window opens, the PDF loads and scrolls continuously with native pinch-zoom.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Reader
git commit -m "feat: reader window shell with PDFView, continuous scroll"
```

### Task 16: Thumbnails, outline + annotations inspector, toolbar

**Files:**
- Create: `NimbleScholar/Reader/ThumbnailSidebar.swift`
- Create: `NimbleScholar/Reader/InspectorPanel.swift`
- Create: `NimbleScholar/Reader/ReaderToolbar.swift`

- [ ] **Step 1: Thumbnails via PDFThumbnailView**

Create `ThumbnailSidebar.swift`:

```swift
import SwiftUI
import PDFKit

struct ThumbnailSidebar: NSViewRepresentable {
    let pdfView: PDFView
    func makeNSView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.pdfView = pdfView
        t.thumbnailSize = NSSize(width: 110, height: 150)
        t.backgroundColor = .clear
        return t
    }
    func updateNSView(_ nsView: PDFThumbnailView, context: Context) { nsView.pdfView = pdfView }
}
```

- [ ] **Step 2: Inspector with Outline + Annotations tabs**

Create `InspectorPanel.swift`:

```swift
import SwiftUI
import PDFKit
import NimbleScholarCore

struct InspectorPanel: View {
    let pdfView: PDFView
    @ObservedObject var vm: ReaderViewModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Outline").tag(0); Text("Annotations").tag(1)
            }.pickerStyle(.segmented).padding(8)
            Divider()
            if tab == 0 { outline } else { annotations }
        }
    }

    private var outline: some View {
        List {
            if let root = pdfView.document?.outlineRoot, root.numberOfChildren > 0 {
                ForEach(0..<root.numberOfChildren, id: \.self) { i in
                    if let child = root.child(at: i) {
                        Button(child.label ?? "—") {
                            if let dest = child.destination { pdfView.go(to: dest) }
                        }.buttonStyle(.plain)
                    }
                }
            } else { Text("No outline").foregroundStyle(.secondary) }
        }
    }

    private var annotations: some View {
        List {
            if vm.annotations.isEmpty { Text("No annotations").foregroundStyle(.secondary) }
            ForEach(vm.annotations) { a in
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: a.color)).frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(a.snippet.isEmpty ? a.kind : a.snippet).lineLimit(2).font(.caption)
                        Text("Page \(a.page)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let page = pdfView.document?.page(at: a.page - 1) { pdfView.go(to: page) }
                }
                .swipeActions { Button("Delete", role: .destructive) {
                    if let id = a.id { try? vm.store.deleteAnnotation(id: id) }
                    if let pid = vm.paper.id { vm.annotations = (try? vm.store.annotations(forPaper: pid)) ?? [] }
                } }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.dropFirst(hex.hasPrefix("#") ? 1 : 0)
        var v: UInt64 = 0; Scanner(string: String(s)).scanHexInt64(&v)
        self = Color(red: Double((v >> 16) & 0xff)/255, green: Double((v >> 8) & 0xff)/255, blue: Double(v & 0xff)/255)
    }
}
```

- [ ] **Step 3: Toolbar (search, page nav, zoom/fit, display mode, panels, annotate)**

Create `ReaderToolbar.swift`:

```swift
import SwiftUI
import PDFKit
import NimbleScholarCore

struct ReaderToolbar: ToolbarContent {
    @Binding var pdfView: PDFView?
    @Binding var displayMode: PDFDisplayMode
    @Binding var showThumbs: Bool
    @Binding var showInspector: Bool
    @ObservedObject var vm: ReaderViewModel
    @State private var search = ""

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showThumbs.toggle() } label: { Image(systemName: "sidebar.left") }
        }
        ToolbarItemGroup {
            TextField("Search", text: $search)
                .frame(width: 160)
                .onSubmit { if let pv = pdfView, let sel = pv.document?.findString(search, withOptions: .caseInsensitive).first { pv.setCurrentSelection(sel, animate: true); pv.go(to: sel) } }
            Button { pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit") { if let pv = pdfView { pv.autoScales = true; pv.scaleFactor = pv.scaleFactorForSizeToFit } }
            Picker("", selection: $displayMode) {
                Image(systemName: "doc").tag(PDFDisplayMode.singlePage)
                Image(systemName: "doc.on.doc").tag(PDFDisplayMode.singlePageContinuous)
                Image(systemName: "book.pages").tag(PDFDisplayMode.twoUpContinuous)
            }.pickerStyle(.segmented).frame(width: 120)
            Button { highlightSelection() } label: { Image(systemName: "highlighter") }
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
        }
    }

    private func highlightSelection() {
        guard let pv = pdfView, let sel = pv.currentSelection, let page = sel.pages.first,
              let pageIndex = pv.document?.index(for: page) else { return }
        // Text-aware: one highlight annotation per line rectangle.
        for line in sel.selectionsByLine() {
            let bounds = line.bounds(for: page)
            let a = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            a.color = NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
            page.addAnnotation(a)
        }
        pv.document?.write(to: vm.localURL!)   // persist into the file
        // Index it for the list/search.
        let pageRect = page.bounds(for: .mediaBox)
        let b = sel.bounds(for: page)
        var idx = AnnotationIndex(id: nil, paperId: vm.paper.id ?? -1, page: pageIndex + 1,
            kind: "highlight", color: "#ffd966", snippet: sel.string ?? "",
            x: Double(b.minX / pageRect.width), y: Double(b.minY / pageRect.height),
            width: Double(b.width / pageRect.width), height: Double(b.height / pageRect.height),
            createdAt: 0, updatedAt: 0)
        _ = try? vm.store.upsertAnnotation(&idx)
        if let pid = vm.paper.id { vm.annotations = (try? vm.store.annotations(forPaper: pid)) ?? [] }
        pv.clearSelection()
    }
}
```

- [ ] **Step 4: VERIFY ON MAC**

Build & run, open a paper. Verify: ⌘F-style search box finds and jumps to text; zoom +/− and Fit work; display-mode segmented control switches single/continuous/two-up; thumbnails toggle; **select text → highlighter button → a yellow highlight hugs the lines and appears in the Annotations tab**; reopen the same PDF in Preview → the highlight is present (proves it was written into the file). Delete an annotation from the inspector.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Reader
git commit -m "feat: thumbnails, outline/annotations inspector, reader toolbar with text-aware highlights"
```

### Task 17: Note annotations (inline editable)

**Files:**
- Modify: `NimbleScholar/Reader/ReaderToolbar.swift`
- Create: `NimbleScholar/Reader/AnnotationController.swift`

- [ ] **Step 1: Extract annotation persistence into a controller**

Create `AnnotationController.swift`:

```swift
import PDFKit
import AppKit
import NimbleScholarCore

@MainActor
struct AnnotationController {
    let vm: ReaderViewModel

    func addNote(text: String, at point: CGPoint, on page: PDFPage, pdfView: PDFView) {
        guard let pageIndex = pdfView.document?.index(for: page) else { return }
        let rect = CGRect(x: point.x, y: point.y, width: 22, height: 22)
        let note = PDFAnnotation(bounds: rect, forType: .text, withProperties: nil)
        note.contents = text
        note.color = NSColor(red: 0.49, green: 0.77, blue: 1, alpha: 1)
        page.addAnnotation(note)
        persist(pdfView: pdfView)
        let pageRect = page.bounds(for: .mediaBox)
        var idx = AnnotationIndex(id: nil, paperId: vm.paper.id ?? -1, page: pageIndex + 1,
            kind: "note", color: "#7cc4ff", snippet: text,
            x: Double(rect.minX / pageRect.width), y: Double(rect.minY / pageRect.height),
            width: Double(rect.width / pageRect.width), height: Double(rect.height / pageRect.height),
            createdAt: 0, updatedAt: 0)
        _ = try? vm.store.upsertAnnotation(&idx)
        reload()
    }

    func persist(pdfView: PDFView) { if let u = vm.localURL { pdfView.document?.write(to: u) } }
    func reload() { if let pid = vm.paper.id { vm.annotations = (try? vm.store.annotations(forPaper: pid)) ?? [] } }
}
```

- [ ] **Step 2: Add a Note toolbar button that prompts inline**

In `ReaderToolbar.swift`, add after the highlighter button inside `ToolbarItemGroup`:

```swift
            Button { addNote() } label: { Image(systemName: "note.text.badge.plus") }
```

And add this method to `ReaderToolbar`:

```swift
    @State private var noteText = ""
    private func addNote() {
        guard let pv = pdfView, let page = pv.currentPage else { return }
        let alert = NSAlert(); alert.messageText = "New note"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        let center = pv.convert(pv.bounds.center, to: page)
        AnnotationController(vm: vm).addNote(text: field.stringValue, at: center, on: page, pdfView: pv)
    }
```

Add the helper:

```swift
extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
```

- [ ] **Step 3: VERIFY ON MAC**

Build & run. Add a note → it appears as a note icon on the page, shows in the Annotations tab, persists in the file (visible in Preview), and survives reopening the reader.

- [ ] **Step 4: Commit**

```bash
git add NimbleScholar/Reader
git commit -m "feat: note annotations written into the PDF + indexed"
```

---

## Phase 6 — Settings, polish, docs

### Task 18: Settings (view mode, night reading, capture port)

**Files:**
- Create: `NimbleScholar/Settings/SettingsView.swift` (replaces stub)
- Modify: `NimbleScholar/Reader/PDFKitView.swift` (apply night invert)

- [ ] **Step 1: Settings view**

Create `Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("nightReading") private var nightReading = false
    @AppStorage("capturePort") private var capturePort = 8765
    var body: some View {
        Form {
            Toggle("Night reading (invert PDF colors)", isOn: $nightReading)
            TextField("Capture server port", value: $capturePort, format: .number)
            Text("Restart required after changing the port.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 380).padding()
    }
}
```

- [ ] **Step 2: Apply night-reading invert in PDFKitView**

In `PDFKitView.swift`, read the setting and toggle a Core Image invert on the view's layer:

```swift
    @AppStorage("nightReading") private var nightReading = false
```

and in `updateNSView`, set:

```swift
        v.wantsLayer = true
        v.layer?.filters = nightReading
            ? [CIFilter(name: "CIColorInvert")!]
            : []
```

- [ ] **Step 3: VERIFY ON MAC**

Open Settings (⌘,), toggle Night reading → an open reader inverts page colors. (Page nav/zoom still work.)

- [ ] **Step 4: Commit**

```bash
git add NimbleScholar/Settings NimbleScholar/Reader/PDFKitView.swift
git commit -m "feat: settings with night reading + capture port"
```

### Task 19: BibTeX export menu command

**Files:**
- Modify: `NimbleScholar/NimbleScholarApp.swift`

- [ ] **Step 1: Add an Export BibTeX command**

In `NimbleScholarApp.swift`, add a `.commands { }` modifier to the library `WindowGroup`:

```swift
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export BibTeX…") { exportBibTeX(env: AppEnvironment.shared) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
```

And add a free function in the same file:

```swift
import NimbleScholarCore
import AppKit

@MainActor func exportBibTeX(env: AppEnvironment) {
    let papers = (try? env.store.searchPapers(query: nil, tag: nil)) ?? []
    let panel = NSSavePanel(); panel.nameFieldStringValue = "papers.bib"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? BibTeXExporter.export(papers).data(using: .utf8)?.write(to: url)
}
```

- [ ] **Step 2: VERIFY ON MAC**

Run, ⇧⌘E → save panel → writes a `.bib` with entries for your papers.

- [ ] **Step 3: Commit**

```bash
git add NimbleScholar/NimbleScholarApp.swift
git commit -m "feat: Export BibTeX menu command"
```

### Task 20: End-to-end verification & README

**Files:**
- Create: `NimbleScholar/README-native.md`

- [ ] **Step 1: Full regression on Mac**

Run `cd NimbleScholarCore && swift test` (all green), then build & run the app and walk the whole flow:
- Capture from the **existing Chrome/Edge extension** (it POSTs to `127.0.0.1:8765`) → paper appears live in the library.
- Search, tag filter, all three view modes, edit, delete.
- Open reader: search, zoom, fit, display modes, thumbnails, outline, highlight, note; annotations persist in the file (verify in Preview) and in the inspector list.
- Export BibTeX. Toggle night reading.

- [ ] **Step 2: Write the native README**

Create `NimbleScholar/README-native.md` documenting: architecture (core package + app), how to build (`xcodebuild`/Xcode), where data lives (`~/Library/Application Support/Nimble Scholar/`), the capture server port and how the extension targets it, and the annotation model (written into PDFs + SQLite index).

- [ ] **Step 3: Commit**

```bash
git add NimbleScholar/README-native.md
git commit -m "docs: native app README and end-to-end verification notes"
```

---

## Self-Review Notes (coverage vs spec)

- §1 Architecture & stack → Tasks 0, 12 (SwiftUI app + core package + GRDB/FlyingFox/SwiftSoup).
- §2 Module structure → file structure above; created across Tasks 1–19.
- §3 Library window (3 modes, switcher, sidebar, search, sort) → Tasks 13–14. *Sort menu is minimal (search/tag only in `searchPapers`); add a `sort` parameter if you want the three sort orders — noted as a small follow-up.*
- §4 Reader (layout A: thumbnails + PDF + inspector, search, zoom/fit, display modes, annotations into PDF) → Tasks 15–17.
- §5 Capture & arXiv (loopback server, arXiv API + meta, figure heuristic, PDF download, BibTeX) → Tasks 5–11, 19.
- §6 Data & migration (fresh GRDB store; no migration) → Tasks 2–4, 12.
- §7 Look & feel (native materials, night reading) → Tasks 13–18.
- §8 Out of scope respected (no old-data migration, no Safari ext, no iOS).

**Known small gaps to flag during execution:** (a) sort modes are not yet wired into `searchPapers` — add an enum + `ORDER BY` branch; (b) `AppEnvironment.shared` singleton wiring (Task 12 Step 4 / Task 13 / Task 15) must be consistent — pick the singleton and use it everywhere; (c) FlyingFox API names may differ by version (Task 11 note).
```
