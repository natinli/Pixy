import XCTest
@testable import PixyDbg

final class DeleteConfirmPolicyTests: XCTestCase {
    private func needsPrompt(show: Bool, skip: Bool, shift: Bool, external: Bool, permission: Bool) -> Bool {
        DeleteConfirmPolicy.needsPrompt(isShowPrompt: show, skipSetting: skip, isShiftPressed: shift,
                                        isExternalVolume: external, hasPermission: permission)
    }

    /// 设置关闭时，行为必须与引入该设置前的表达式完全一致：isShowPrompt || !hasPermission || isExternalVolume（Shift 不参与）。
    func testSettingOffMatchesLegacyBehaviourForEveryCombination() {
        for show in [true, false] { for shift in [true, false] { for external in [true, false] { for permission in [true, false] {
            let legacy = show || !permission || external
            XCTAssertEqual(needsPrompt(show: show, skip: false, shift: shift, external: external, permission: permission), legacy,
                           "show=\(show) shift=\(shift) external=\(external) permission=\(permission)")
        }}}}
    }

    func testSettingOnSkipsOnlyThePlainTrashPrompt() {
        XCTAssertFalse(needsPrompt(show: true, skip: true, shift: false, external: false, permission: true))
    }

    func testSettingOnStillAsksForPermanentDelete() {
        XCTAssertTrue(needsPrompt(show: true, skip: true, shift: true, external: false, permission: true))
    }

    func testSettingOnStillAsksOnExternalVolumes() {
        XCTAssertTrue(needsPrompt(show: true, skip: true, shift: false, external: true, permission: true))
    }

    func testSettingOnStillAsksWithoutAutomationPermission() {
        XCTAssertTrue(needsPrompt(show: true, skip: true, shift: false, external: false, permission: false))
    }
}
