import XCTest
@testable import PixyDbg

final class TreeViewModelURLTests: XCTestCase {
    func testNormalizedURLAcceptsPlainPathsAndFileURLs() {
        XCTAssertEqual(TreeViewModel.normalizedURL("/a/b/../c")?.path, "/a/c")
        XCTAssertEqual(TreeViewModel.normalizedURL("file:///a/b/")?.path, "/a/b")
    }

    func testNormalizedURLRejectsEmptyAndNonFileURLs() {
        XCTAssertNil(TreeViewModel.normalizedURL(""))
        XCTAssertNil(TreeViewModel.normalizedURL("https://example.com/a"))
        XCTAssertNil(TreeViewModel.normalizedURL("not a url"))
    }

    func testVirtualTagURLOnlyMatchesTheTopLevelVirtualFolder() {
        XCTAssertTrue(TreeViewModel.isVirtualTagURL(URL(fileURLWithPath: "/VirtualFinderTagsFolder")))
        XCTAssertTrue(TreeViewModel.isVirtualTagURL(URL(fileURLWithPath: "/VirtualFinderTagsFolder/红色")))
        XCTAssertFalse(TreeViewModel.isVirtualTagURL(URL(fileURLWithPath: "/Users/a/VirtualFinderTagsFolder")))
        XCTAssertFalse(TreeViewModel.isVirtualTagURL(URL(fileURLWithPath: "/VirtualFinderTagsFolderX")))
    }

    func testContainsComparesPathComponentsNotStringPrefixes() {
        func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
        XCTAssertTrue(TreeViewModel.contains(url("/a/b"), url("/a/b/c")))
        XCTAssertTrue(TreeViewModel.contains(url("/a/b"), url("/a/b")))
        XCTAssertTrue(TreeViewModel.contains(url("/"), url("/x")))
        XCTAssertFalse(TreeViewModel.contains(url("/a/b"), url("/a/bc")))
        XCTAssertFalse(TreeViewModel.contains(url("/a/b/c"), url("/a/b")))
    }
}
