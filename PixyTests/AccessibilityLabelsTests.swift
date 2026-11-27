import XCTest
@testable import PixyDbg

final class AccessibilityLabelsTests: XCTestCase {
    // 类型词必须取自已有的本地化字符串（与 setWindowTitle 统计文案同一批 key），不写死任何语言。
    private let folderWord = NSLocalizedString("Folder", comment: "")
    private let imageWord = NSLocalizedString("Image", comment: "")
    private let videoWord = NSLocalizedString("Video", comment: "")
    private let otherWord = NSLocalizedString("Other", comment: "")
    private let tagWord = NSLocalizedString("Tag", comment: "")

    // MARK: - 类型词

    func testTypeWordsComeFromExistingLocalizedStrings() {
        XCTAssertEqual(AccessibilityLabels.typeWord(.folder), folderWord)
        XCTAssertEqual(AccessibilityLabels.typeWord(.image), imageWord)
        XCTAssertEqual(AccessibilityLabels.typeWord(.video), videoWord)
        XCTAssertEqual(AccessibilityLabels.typeWord(.other), otherWord)
    }

    func testTypeWordsAreNonEmptyAndDistinct() {
        let words = [folderWord, imageWord, videoWord, otherWord]
        XCTAssertTrue(words.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(words).count, 4)
    }

    // MARK: - 缩略图：四类 + 空名

    func testThumbnailLabelForEachKind() {
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "Trips", kind: .folder), "Trips, \(folderWord)")
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "IMG_0001.jpg", kind: .image), "IMG_0001.jpg, \(imageWord)")
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "clip.mp4", kind: .video), "clip.mp4, \(videoWord)")
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "notes.txt", kind: .other), "notes.txt, \(otherWord)")
    }

    func testEmptyNameYieldsTypeWordOnly() {
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "", kind: .folder), folderWord)
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "", kind: .image), imageWord)
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "", kind: .video), videoWord)
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "", kind: .other), otherWord)
    }

    func testBlankNameYieldsTypeWordOnly() {
        XCTAssertEqual(AccessibilityLabels.thumbnail(name: "   \n\t", kind: .image), imageWord)
    }

    // MARK: - 超长名、特殊字符

    func testVeryLongNameIsNotTruncated() {
        let name = String(repeating: "长a", count: 150) + ".jpg"   // 304 个字符
        XCTAssertEqual(name.count, 304)
        let label = AccessibilityLabels.thumbnail(name: name, kind: .image)
        XCTAssertEqual(label, "\(name), \(imageWord)")
        XCTAssertTrue(label.hasPrefix(name))
    }

    func testSpecialCharactersArePreservedVerbatim() {
        let names = [
            "#hash.png",
            "100%.png",
            "%E4%B8%AD.png",          // 字面的百分号编码文本不能被再次解码或编码
            "emoji 🎞️ ✨.png",
            "with space .png",
            "中文名字.jpg",
            "a,b.png",                // 名字里自带逗号：原样保留，不去重不转义
            "  leading and trailing  .png",
        ]
        for name in names {
            XCTAssertEqual(AccessibilityLabels.thumbnail(name: name, kind: .image), "\(name), \(imageWord)", name)
        }
    }

    func testSameInputGivesSameOutput() {
        let first = AccessibilityLabels.thumbnail(name: "x #1.jpg", kind: .video)
        for _ in 0..<20 {
            XCTAssertEqual(AccessibilityLabels.thumbnail(name: "x #1.jpg", kind: .video), first)
        }
    }

    // MARK: - FileModel 字段 → 类型

    func testKindMapping() {
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: true, type: .folder), .folder)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: true, type: .notSet), .folder)   // 目录优先于 type
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .folder), .folder)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .image), .image)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .video), .video)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .other), .other)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .notSet), .other)
        XCTAssertEqual(AccessibilityLabels.kind(isDirectory: false, type: .all), .other)
    }

    // MARK: - 大图

    func testLargeImageLabelMatchesThumbnailFormat() {
        XCTAssertEqual(AccessibilityLabels.largeImage(name: "IMG_0001.jpg", kind: .image),
                       AccessibilityLabels.thumbnail(name: "IMG_0001.jpg", kind: .image))
        XCTAssertEqual(AccessibilityLabels.largeImage(name: "clip.mp4", kind: .video), "clip.mp4, \(videoWord)")
        XCTAssertEqual(AccessibilityLabels.largeImage(name: "", kind: .image), imageWord)
    }

    // MARK: - 侧栏

    func testSidebarEntriesUseTheirNameWithoutTypeWord() {
        let roles: [SidebarNodeRole] = [.group, .directory, .volume, .file, .special]
        for role in roles {
            XCTAssertEqual(AccessibilityLabels.sidebar(name: "Documents", role: role), "Documents", "\(role)")
        }
    }

    func testSidebarTagEntryAddsTagWord() {
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "Red", role: .tag), "Red, \(tagWord)")
    }

    /// 「所有标签…」入口的角色也是 .tag，但名称本身已经说明是标签，不应再读成「所有标签…, 标签」；颜色标签仍要带「标签」。
    /// 调用方（CustomOutlineViewManager）按 fullPath 恰为 `file:///VirtualFinderTagsFolder/` 判断：不能用 entryID（颜色标签也带 "tags"），也不能用 fileURL（标签节点恒为 nil）。
    func testSidebarAllTagsEntryIsNotSuffixedWithTagWord() {
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "All Tags…", role: .tag, isAllTagsEntry: true), "All Tags…")
        XCTAssertNil(AccessibilityLabels.sidebar(name: "  ", role: .tag, isAllTagsEntry: true))
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "Red", role: .tag, isAllTagsEntry: false), "Red, \(tagWord)")
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "Red", role: .tag), "Red, \(tagWord)")
    }

    func testSidebarSeparatorAndRootAreNotExposed() {
        XCTAssertNil(AccessibilityLabels.sidebar(name: "", role: .separator))
        XCTAssertNil(AccessibilityLabels.sidebar(name: "anything", role: .separator))
        XCTAssertNil(AccessibilityLabels.sidebar(name: "root", role: .root))
    }

    func testSidebarBlankNameHasNoLabelExceptTagWord() {
        XCTAssertNil(AccessibilityLabels.sidebar(name: "", role: .directory))
        XCTAssertNil(AccessibilityLabels.sidebar(name: "  ", role: .volume))
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "", role: .tag), tagWord)
    }

    func testSidebarKeepsSpecialCharactersVerbatim() {
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "100% #1 🎞️", role: .directory), "100% #1 🎞️")
        XCTAssertEqual(AccessibilityLabels.sidebar(name: "OneDrive - 个人", role: .volume), "OneDrive - 个人")
    }
}
