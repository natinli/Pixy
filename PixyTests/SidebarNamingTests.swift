import XCTest
@testable import PixyDbg

final class SidebarNamingTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeFolders(_ names: [String], files: [String] = []) throws {
        for name in names {
            try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for name in files {
            FileManager.default.createFile(atPath: tempRoot.appendingPathComponent(name).path, contents: Data())
        }
    }

    // MARK: spacedComputerName

    func testSpacedComputerNameAddsSpacesOnlyNextToASCII() {
        XCTAssertEqual(SidebarNaming.spacedComputerName("natinli的Mac mini"), "natinli 的 Mac mini")
        XCTAssertEqual(SidebarNaming.spacedComputerName("小明的MacBook"), "小明的 MacBook")
        XCTAssertEqual(SidebarNaming.spacedComputerName("1的2的3"), "1 的 2 的 3")
    }

    func testSpacedComputerNameLeavesOtherNamesAlone() {
        XCTAssertEqual(SidebarNaming.spacedComputerName("我的电脑"), "我的电脑")
        XCTAssertEqual(SidebarNaming.spacedComputerName("Bob's Mac"), "Bob's Mac")
        XCTAssertEqual(SidebarNaming.spacedComputerName(""), "")
    }

    // MARK: oneDriveEntries

    func testOneDriveEntriesMissingDirectoryIsEmpty() {
        XCTAssertTrue(SidebarNaming.oneDriveEntries(in: tempRoot.appendingPathComponent("nope")).isEmpty)
    }

    func testSingleOneDriveIsNamedOneDriveWhateverTheSuffix() throws {
        for suffix in ["个人", "Personal", "Persönlich"] {
            try? FileManager.default.removeItem(at: tempRoot)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try makeFolders(["OneDrive-\(suffix)", "GoogleDrive-x", "OneDriveFake"], files: ["OneDrive-file"])
            let entries = SidebarNaming.oneDriveEntries(in: tempRoot)
            XCTAssertEqual(entries.map(\.displayName), ["OneDrive"], "suffix \(suffix)")
            XCTAssertEqual(entries.first?.url.lastPathComponent, "OneDrive-\(suffix)")
        }
    }

    func testSeveralOneDrivesGetSuffixedNames() throws {
        try makeFolders(["OneDrive-Personal", "OneDrive", "OneDrive-Contoso"])
        let entries = SidebarNaming.oneDriveEntries(in: tempRoot)
        XCTAssertEqual(entries.map(\.displayName), ["OneDrive", "OneDrive - Contoso", "OneDrive - Personal"])
    }

    // MARK: volumeRank

    func testVolumeRankPutsOneDriveAfterDisks() {
        let oneDrive = URL(fileURLWithPath: "/Volumes/Home/Library/CloudStorage/OneDrive-Personal")
        let disk = URL(fileURLWithPath: "/Volumes/Minimalist")
        let paths: Set<String> = [oneDrive.standardizedFileURL.path]
        XCTAssertEqual(SidebarNaming.volumeRank(disk, oneDrivePaths: paths), 0)
        XCTAssertEqual(SidebarNaming.volumeRank(oneDrive, oneDrivePaths: paths), 1)
        // 不再特判任何具体卷名
        XCTAssertEqual(SidebarNaming.volumeRank(URL(fileURLWithPath: "/Volumes/minimalist"), oneDrivePaths: paths), 0)
    }
}
