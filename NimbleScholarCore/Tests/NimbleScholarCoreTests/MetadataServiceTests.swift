import XCTest
@testable import NimbleScholarCore

final class MetadataServiceTests: XCTestCase {
    func fixture(_ filename: String) throws -> Data {
        let parts = filename.split(separator: ".")
        let ext = String(parts.last!)
        let base = parts.dropLast().joined(separator: ".")
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
            "Missing fixture \(filename)"
        )
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
