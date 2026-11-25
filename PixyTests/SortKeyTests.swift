import XCTest
@testable import PixyDbg

final class SortKeyTests: XCTestCase {
    private func key(_ path: String, size: Int = 0, isDir: Bool = false, type: SortType,
                     create: Date = Date(timeIntervalSince1970: 0), folderFirst: Bool = false) -> SortKeyFile {
        SortKeyFile("file:///tmp/\(path)", createDate: create, size: size, isDir: isDir,
                    sortType: type, isSortFolderFirst: folderFirst, isSortUseFullPath: true, randomSeed: 0)
    }

    func testSizeAscendingAndDescending() {
        let small = key("a.png", size: 10, type: .sizeA), big = key("b.png", size: 99, type: .sizeA)
        XCTAssertTrue(small < big)
        XCTAssertFalse(big < small)
        let smallZ = key("a.png", size: 10, type: .sizeZ), bigZ = key("b.png", size: 99, type: .sizeZ)
        XCTAssertTrue(bigZ < smallZ)
    }

    func testEqualSizesFallBackToPathOrder() {
        let a = key("a.png", size: 5, type: .sizeA), b = key("b.png", size: 5, type: .sizeA)
        XCTAssertTrue(a < b)
        XCTAssertFalse(b < a)
    }

    func testFoldersComeFirstWhenSortingBySizeEvenIfLarger() {
        let folder = key("dir", size: 0, isDir: true, type: .sizeZ)
        let file = key("a.png", size: 1_000, type: .sizeZ)
        XCTAssertTrue(folder < file)   // sizeZ 本应大的在前，但文件夹按大小排序时仍优先
        XCTAssertFalse(file < folder)
    }

    func testFolderFirstFlagControlsFoldersForPathSort() {
        let folder = key("zdir", isDir: true, type: .pathA, folderFirst: true)
        let file = key("a.png", type: .pathA, folderFirst: true)
        XCTAssertTrue(folder < file)
        let folderOff = key("zdir", isDir: true, type: .pathA, folderFirst: false)
        let fileOff = key("a.png", type: .pathA, folderFirst: false)
        XCTAssertTrue(fileOff < folderOff)   // 关闭「文件夹优先」后按路径：a.png < zdir
    }

    func testCreateDateAscendingAndDescending() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(key("a.png", type: .createDateA, create: old) < key("b.png", type: .createDateA, create: new))
        XCTAssertTrue(key("a.png", type: .createDateZ, create: new) < key("b.png", type: .createDateZ, create: old))
    }

    func testDifferentSortTypesAreTreatedAsEqual() {
        // 排序类型不一致属于异常情况，约定为「不小于」，避免有序 Map 被破坏
        let a = key("a.png", size: 1, type: .sizeA), b = key("b.png", size: 2, type: .sizeZ)
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
    }
}
