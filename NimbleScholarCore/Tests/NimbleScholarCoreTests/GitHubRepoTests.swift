import XCTest
@testable import NimbleScholarCore

final class GitHubRepoTests: XCTestCase {
    func testOwnerRepoWithScheme() {
        let r = GitHubRepo.ownerRepo(from: "https://github.com/facebookresearch/detectron2")
        XCTAssertEqual(r?.owner, "facebookresearch")
        XCTAssertEqual(r?.repo, "detectron2")
    }
    func testOwnerRepoStripsGitAndExtraPath() {
        XCTAssertEqual(GitHubRepo.ownerRepo(from: "github.com/a/b.git")?.repo, "b")
        XCTAssertEqual(GitHubRepo.ownerRepo(from: "https://github.com/a/b/tree/main")?.repo, "b")
    }
    func testOwnerRepoRejectsNonRepo() {
        XCTAssertNil(GitHubRepo.ownerRepo(from: "https://example.com/a/b"))
        XCTAssertNil(GitHubRepo.ownerRepo(from: "https://github.com/onlyowner"))
    }
    func testReleasedWhenRealFilesPresent() {
        XCTAssertTrue(GitHubRepo.isReleased(rootEntryNames: ["README.md", "train.py", "src"]))
    }
    func testNotReleasedForDocsOnlyOrEmpty() {
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: ["README.md", "LICENSE", ".gitignore"]))
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: ["README.md"]))
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: []))
    }
}
