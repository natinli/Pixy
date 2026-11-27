import XCTest
@testable import PixyDbg

// MARK: - 合成布局与最小「滚动视图」模型

/// 合成布局：`columns` 列、每列宽 `colWidth`，项按行从左到右、从上到下排。
/// 一行的高度取行内最高项，行与行之间隔 `rowGap`，项在行内顶部对齐。只产出 frame，不依赖 AppKit。
/// Synthetic grid: items fill rows left to right; a row is as tall as its tallest item. Frames only, no AppKit.
struct SyntheticLayout {
    let columns: Int
    private(set) var frames: [CGRect]

    /// 每项同高。Every item has the same height.
    init(columns: Int, cellHeight: CGFloat, rowGap: CGFloat = 0, count: Int, colWidth: CGFloat = 100) {
        self.init(columns: columns, heights: Array(repeating: cellHeight, count: count), rowGap: rowGap, colWidth: colWidth)
    }

    /// 每项各自的高度。Per-item heights.
    init(columns: Int, heights: [CGFloat], rowGap: CGFloat = 0, colWidth: CGFloat = 100) {
        self.columns = columns
        var frames: [CGRect] = []
        var rowTop: CGFloat = 0
        var index = 0
        while index < heights.count {
            let row = heights[index..<min(index + columns, heights.count)]
            for (offset, height) in row.enumerated() {
                frames.append(CGRect(x: CGFloat(offset) * colWidth, y: rowTop, width: colWidth, height: height))
            }
            rowTop += (row.max() ?? 0) + rowGap
            index += columns
        }
        self.frames = frames
    }

    /// 直接给定 frame（用来摆瀑布流那种参差的布局和零高度项）。Explicit frames.
    init(frames: [CGRect], columns: Int = 1) {
        self.columns = columns
        self.frames = frames
    }

    var count: Int { frames.count }
    var contentHeight: CGFloat { frames.map { $0.maxY }.max() ?? 0 }

    /// 项不存在（含越界、负数）返回 nil，与 NSCollectionViewLayout 取不到属性一致。
    func frame(of index: Int) -> CGRect? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    /// 与 rect 相交的项（布局的 layoutAttributesForElements(in:) 做的事）。
    func indices(in rect: CGRect) -> [Int] {
        frames.indices.filter { frames[$0].intersects(rect) }
    }

    /// 总宽 `totalWidth`、`columns` 列的方格布局：缩放时每格边长随列数变化。Square-cell grid filling a fixed width.
    static func squareGrid(columns: Int, count: Int, totalWidth: CGFloat = 600) -> SyntheticLayout {
        let side = totalWidth / CGFloat(columns)
        return SyntheticLayout(columns: columns, cellHeight: side, count: count, colWidth: side)
    }
}

/// 最小的滚动视图：可视区 = [top, top + height)，选锚、换布局、恢复三步都走 ScrollAnchorMath，
/// 流程与 LayoutManagement.swift 里 captureScrollAnchor → 重新布局 → restoreScrollAnchorIfReady 一致。
/// Minimal scroll view driving ScrollAnchorMath through capture → relayout → restore, like LayoutManagement.swift does.
struct SyntheticViewport {
    var layout: SyntheticLayout
    var top: CGFloat
    var height: CGFloat
    var selected: [Int] = []
    /// 对应 PublicVar.lastZoomAnchorFile：上一次恢复到的锚点。
    var sticky: Int?

    struct Anchor {
        let index: Int
        let offsetInViewport: CGFloat
        let viewportHeight: CGFloat
    }

    var visibleRect: CGRect { CGRect(x: 0, y: top, width: 100_000, height: height) }

    /// 项 index 顶边相对可视区顶边的距离。
    func offsetOnScreen(of index: Int) -> CGFloat? {
        layout.frame(of: index).map { $0.minY - top }
    }

    func isVisible(_ index: Int) -> Bool {
        layout.frame(of: index).map { $0.intersects(visibleRect) } ?? false
    }

    func capture(useSticky: Bool = true) -> Anchor? {
        let rect = visibleRect
        guard let picked = ScrollAnchorMath.pickAnchor(
            selected: selected.sorted(),
            sticky: useSticky ? sticky : nil,
            visibleRect: rect,
            frameOf: { layout.frame(of: $0) },
            visibleCandidates: { layout.indices(in: rect) }) else { return nil }
        return Anchor(index: picked.index, offsetInViewport: picked.frame.minY - rect.minY, viewportHeight: height)
    }

    /// 捕获 → 换布局（可同时换可视区高度）→ 在新布局里恢复。返回捕获到的锚点。
    @discardableResult
    mutating func relayout(_ newLayout: SyntheticLayout, newHeight: CGFloat? = nil, useSticky: Bool = true) -> Anchor? {
        let anchor = capture(useSticky: useSticky)
        layout = newLayout
        if let newHeight { height = newHeight }
        if let anchor, let frame = layout.frame(of: anchor.index) {
            top = ScrollAnchorMath.targetScrollTop(
                anchorMinY: frame.minY, anchorHeight: frame.height,
                offsetInViewport: anchor.offsetInViewport,
                oldViewportHeight: anchor.viewportHeight, newViewportHeight: height,
                contentHeight: layout.contentHeight, insetTop: 0)
            sticky = anchor.index
        } else {
            sticky = nil
        }
        return anchor
    }
}

// MARK: - pickAnchor

final class ScrollAnchorMathTests: XCTestCase {

    /// 5 列、每项 100x100、无间隙：第 r 行的 y = 100 * r，行 r 的项是 5r ... 5r+4。
    private let grid5 = SyntheticLayout(columns: 5, cellHeight: 100, count: 500)

    private func pick(_ layout: SyntheticLayout, top: CGFloat, height: CGFloat = 400,
                      selected: [Int] = [], sticky: Int? = nil) -> (index: Int, frame: CGRect)? {
        let rect = CGRect(x: 0, y: top, width: 100_000, height: height)
        return ScrollAnchorMath.pickAnchor(selected: selected, sticky: sticky, visibleRect: rect,
                                           frameOf: { layout.frame(of: $0) },
                                           visibleCandidates: { layout.indices(in: rect) })
    }

    // MARK: 选中项优先

    func testSelectedItemWinsOverStickyAndTopItem() {
        // 可视区 [1000, 1400) 是第 10~13 行；选中 57（第 11 行）、sticky 63，顶部项本应是 50
        let picked = pick(grid5, top: 1000, selected: [57], sticky: 63)
        XCTAssertEqual(picked?.index, 57)
        XCTAssertEqual(picked?.frame.minY, 1100)
    }

    func testFirstVisibleSelectedItemIsChosen() {
        // 传入的选中项按升序；3 在可视区上方，55 是第一个可见的
        XCTAssertEqual(pick(grid5, top: 1000, selected: [3, 55, 61])?.index, 55)
    }

    func testSelectedItemsOutsideViewportAreIgnored() {
        // 选中项在可视区上方 / 下方都不算，退回顶部项
        XCTAssertEqual(pick(grid5, top: 1000, selected: [3, 200])?.index, 50)
    }

    // MARK: 无选中时的顶部项

    func testWithoutSelectionTopRowFirstItemIsChosen() {
        let picked = pick(grid5, top: 1000)
        XCTAssertEqual(picked?.index, 50)
        XCTAssertEqual(picked?.frame.minY, 1000)
    }

    func testTopRowMoreThanHalfVisibleIsChosen() {
        // 第 10 行 [1000, 1100) 露出 70%
        XCTAssertEqual(pick(grid5, top: 1030)?.index, 50)
    }

    func testTopRowLessThanHalfVisibleGivesWayToNextRow() {
        // 第 10 行只露出 40%：锚到几乎被顶边裁掉的那一行没有意义，取第 11 行行首
        XCTAssertEqual(pick(grid5, top: 1060)?.index, 55)
    }

    func testTopRowExactlyHalfVisibleCounts() {
        // 中点正好在可视区顶边，条件是「不低于」，所以算
        XCTAssertEqual(pick(grid5, top: 1050)?.index, 50)
        XCTAssertEqual(pick(grid5, top: 1050.5)?.index, 55)
    }

    func testTopItemTieBreaksToLowestIndexRegardlessOfCandidateOrder() {
        let rect = CGRect(x: 0, y: 1000, width: 100_000, height: 400)
        let reversed = Array(grid5.indices(in: rect).reversed())
        let picked = ScrollAnchorMath.pickAnchor(selected: [], sticky: nil, visibleRect: rect,
                                                 frameOf: { grid5.frame(of: $0) }, visibleCandidates: { reversed })
        XCTAssertEqual(picked?.index, 50)
    }

    func testTopItemIsSmallestMinYNotLowestIndex() {
        // 瀑布流式的参差布局：9 号的顶边比 2 号更靠上，应当取 9
        let layout = SyntheticLayout(frames: (0..<10).map { index in
            switch index {
            case 9: return CGRect(x: 0, y: 480, width: 100, height: 100)
            case 2: return CGRect(x: 100, y: 510, width: 100, height: 100)
            default: return CGRect(x: 1000 + CGFloat(index) * 100, y: 5000, width: 100, height: 100)
            }
        })
        XCTAssertEqual(pick(layout, top: 450, height: 400)?.index, 9)
    }

    func testMostlyScrolledOffItemIsOnlyTheFallback() {
        // 唯一相交的项只露出 20%（中点在可视区顶边之上）：没有「至少一半」的项时退回它
        let layout = SyntheticLayout(frames: [CGRect(x: 0, y: 900, width: 100, height: 100)])
        XCTAssertEqual(pick(layout, top: 980, height: 400)?.index, 0)
    }

    // MARK: 在顶部不锚定

    func testAtTopDoesNotAnchorEvenWithSelectionAndSticky() {
        XCTAssertNil(pick(grid5, top: 0, selected: [2], sticky: 3))
        XCTAssertNil(pick(grid5, top: 0.5, selected: [2], sticky: 3))
        XCTAssertNil(pick(grid5, top: -20, selected: [2], sticky: 3))   // 回弹
    }

    func testJustBelowTopThresholdAnchors() {
        XCTAssertEqual(pick(grid5, top: 0.6)?.index, 0)
        XCTAssertEqual(pick(grid5, top: 0.6, selected: [2])?.index, 2)
    }

    // MARK: sticky（上一次缩放恢复到的锚点）

    func testStickyStillVisibleBeatsTopItem() {
        let picked = pick(grid5, top: 1000, sticky: 67)
        XCTAssertEqual(picked?.index, 67)
        XCTAssertEqual(picked?.frame.minY, 1300)
    }

    func testStickyNoLongerVisibleFallsBackToTopItem() {
        XCTAssertEqual(pick(grid5, top: 1000, sticky: 10)?.index, 50)
        XCTAssertEqual(pick(grid5, top: 1000, sticky: 400)?.index, 50)
        XCTAssertEqual(pick(grid5, top: 1000, sticky: 9999)?.index, 50)   // 不存在
    }

    func testStickyWithZeroHeightFrameIsIgnored() {
        var frames = grid5.frames
        frames[67] = CGRect(x: 200, y: 1300, width: 100, height: 0)
        XCTAssertEqual(pick(SyntheticLayout(frames: frames), top: 1000, sticky: 67)?.index, 50)
    }

    // MARK: 边界

    func testEmptyLayoutReturnsNil() {
        let empty = SyntheticLayout(columns: 5, cellHeight: 100, count: 0)
        XCTAssertNil(pick(empty, top: 1000, selected: [0], sticky: 0))
    }

    func testAllZeroHeightFramesReturnNil() {
        let flat = SyntheticLayout(columns: 5, cellHeight: 0, count: 500)
        XCTAssertNil(pick(flat, top: 1000, selected: [3], sticky: 3))
    }

    func testSingleItemLayout() {
        let single = SyntheticLayout(columns: 5, cellHeight: 100, count: 1)
        XCTAssertNil(pick(single, top: 0))                    // 在顶部
        XCTAssertEqual(pick(single, top: 20)?.index, 0)       // 露出 80%
        XCTAssertEqual(pick(single, top: 60)?.index, 0)       // 只露出 40%，但它是唯一相交的项，走「退回」分支
        XCTAssertNil(pick(single, top: 100))                  // 下边与可视区上边重合，不相交
    }

    func testZeroHeightSelectedItemIsSkipped() {
        var frames = grid5.frames
        frames[56] = CGRect(x: 100, y: 1100, width: 100, height: 0)
        XCTAssertEqual(pick(SyntheticLayout(frames: frames), top: 1000, selected: [56, 57])?.index, 57)
    }

    func testOutOfRangeSelectedIndexesAreSkipped() {
        XCTAssertEqual(pick(grid5, top: 1000, selected: [-1, 9999, 57])?.index, 57)
        XCTAssertEqual(pick(grid5, top: 1000, selected: [-1, 9999])?.index, 50)
    }

    func testFramesOnlyTouchingTheVisibleEdgesAreNotVisible() {
        // 第 9 行 [900, 1000) 的下边与可视区上边重合、第 14 行 [1400, 1500) 的上边与可视区下边重合：都不相交
        XCTAssertEqual(pick(grid5, top: 1000, selected: [45, 70])?.index, 50)
        XCTAssertEqual(pick(grid5, top: 1000, sticky: 70)?.index, 50)
    }

    func testCandidatesAreFilteredByIntersectionByThePureFunction() {
        // 调用方传来的候选里混进了不相交的项（甚至越界的）也不会被选中
        let rect = CGRect(x: 0, y: 1000, width: 100_000, height: 400)
        let everything = Array(grid5.frames.indices) + [-3, 9999]
        let picked = ScrollAnchorMath.pickAnchor(selected: [], sticky: nil, visibleRect: rect,
                                                 frameOf: { grid5.frame(of: $0) }, visibleCandidates: { everything })
        XCTAssertEqual(picked?.index, 50)
    }

    func testVisibleCandidatesAreNotQueriedWhenSelectionOrStickyHits() {
        // 与原实现一致：命中选中项 / sticky 时不去问布局可视区里有哪些项
        let rect = CGRect(x: 0, y: 1000, width: 100_000, height: 400)
        var queried = 0
        _ = ScrollAnchorMath.pickAnchor(selected: [57], sticky: nil, visibleRect: rect,
                                        frameOf: { grid5.frame(of: $0) }, visibleCandidates: { queried += 1; return [] })
        _ = ScrollAnchorMath.pickAnchor(selected: [], sticky: 63, visibleRect: rect,
                                        frameOf: { grid5.frame(of: $0) }, visibleCandidates: { queried += 1; return [] })
        _ = ScrollAnchorMath.pickAnchor(selected: [], sticky: nil, visibleRect: rect,
                                        frameOf: { grid5.frame(of: $0) }, visibleCandidates: { queried += 1; return [] })
        XCTAssertEqual(queried, 1)
    }

    // MARK: - targetScrollTop

    private func top(anchorMinY: CGFloat = 2000, anchorHeight: CGFloat = 100, offset: CGFloat = 150,
                     old: CGFloat = 600, new: CGFloat = 600, content: CGFloat = 10_000, inset: CGFloat = 0) -> CGFloat {
        ScrollAnchorMath.targetScrollTop(anchorMinY: anchorMinY, anchorHeight: anchorHeight, offsetInViewport: offset,
                                         oldViewportHeight: old, newViewportHeight: new,
                                         contentHeight: content, insetTop: inset)
    }

    func testKeepsOffsetWhenViewportHeightIsUnchanged() {
        XCTAssertEqual(top(), 1850, accuracy: 0.0001)
    }

    func testOffsetScalesWithViewportHeight() {
        XCTAssertEqual(top(offset: 100, old: 400, new: 800), 1800, accuracy: 0.0001)   // 偏移翻倍
        XCTAssertEqual(top(offset: 200, old: 800, new: 400), 1900, accuracy: 0.0001)   // 偏移减半
    }

    func testViewportHeightChangeWithinHalfPointDoesNotScale() {
        XCTAssertEqual(top(offset: 100, old: 600, new: 600.4), 1900, accuracy: 0.0001)
        XCTAssertEqual(top(offset: 100, old: 600, new: 599.6), 1900, accuracy: 0.0001)
        XCTAssertEqual(top(offset: 100, old: 600, new: 600.6), 2000 - 100.1, accuracy: 0.0001)
    }

    func testNoScalingWhenEitherViewportHeightIsZero() {
        XCTAssertEqual(top(offset: 100, old: 0, new: 600), 1900, accuracy: 0.0001)
        // 新可视区高度为 0：偏移被夹到 0
        XCTAssertEqual(top(offset: 100, old: 600, new: 0), 2000, accuracy: 0.0001)
    }

    func testOffsetIsClampedToViewportMinusAnchorHeight() {
        XCTAssertEqual(top(anchorHeight: 100, offset: 700, old: 600, new: 600), 2000 - 500, accuracy: 0.0001)
    }

    func testAnchorTallerThanViewportGetsZeroOffset() {
        XCTAssertEqual(top(anchorHeight: 800, offset: 50, old: 600, new: 600), 2000, accuracy: 0.0001)
    }

    func testNegativeOffsetIsClampedToZero() {
        // 锚点项顶边在可视区之上（只露出一部分）：恢复后会把它的顶边放到可视区顶边
        XCTAssertEqual(top(offset: -30), 2000, accuracy: 0.0001)
    }

    func testResultIsClampedToZeroAtTheTop() {
        XCTAssertEqual(top(anchorMinY: 40, offset: 100), 0, accuracy: 0.0001)
    }

    func testResultIsClampedToMaxTopWhenAnchorIsBeyondContent() {
        // 锚点 frame 落在内容之外（过期布局）：夹到 内容高度 - 可视区高度
        XCTAssertEqual(top(anchorMinY: 9900, offset: 0, content: 10_000), 9400, accuracy: 0.0001)
        XCTAssertEqual(top(anchorMinY: 50_000, offset: 0, content: 10_000), 9400, accuracy: 0.0001)
    }

    func testContentShorterThanViewportScrollsToTop() {
        XCTAssertEqual(top(anchorMinY: 200, offset: 0, content: 300), 0, accuracy: 0.0001)
    }

    func testInsetTopIsSubtractedFromTheResult() {
        XCTAssertEqual(top(inset: 64), 1850 - 64, accuracy: 0.0001)
        XCTAssertEqual(top(anchorMinY: 200, offset: 0, content: 300, inset: 64), -64, accuracy: 0.0001)   // 夹到 0 之后再减
    }

    // MARK: - 模型：连续改列数

    private let flips = 10

    /// 5 列方格布局（每格 120），可视区高度 800，顶边落在第 19 行里：第 19 行只露出 40，顶部项是第 20 行行首 100，距顶边 40。
    private func makeViewport(selected: [Int] = []) -> SyntheticViewport {
        let layout = SyntheticLayout.squareGrid(columns: 5, count: 1000)
        return SyntheticViewport(layout: layout, top: 20 * 120 - 40, height: 800, selected: selected, sticky: nil)
    }

    func testRepeatedColumnChangesWithStickyNeverDrift() {
        var viewport = makeViewport()
        var anchors: [Int] = []
        for flip in 0..<flips {
            let columns = flip % 2 == 0 ? 6 : 5
            let anchor = viewport.relayout(.squareGrid(columns: columns, count: 1000))
            XCTAssertNotNil(anchor)
            anchors.append(anchor?.index ?? -1)
            if let index = anchor?.index {
                XCTAssertTrue(viewport.isVisible(index), "第 \(flip) 次改列数后锚点 \(index) 不在可视区内")
                // 锚点在屏幕上的位置也不变
                XCTAssertEqual(viewport.offsetOnScreen(of: index) ?? .nan, anchor?.offsetInViewport ?? 0, accuracy: 0.0001)
            }
        }
        XCTAssertEqual(Set(anchors).count, 1, "每次都应是同一个文件：\(anchors)")
    }

    func testRepeatedColumnChangesWithoutStickyDriftBackwards() {
        // 对照：不沿用上一次的锚点（每次都重选顶部行首）就会一行行往前漂，这正是 sticky 存在的理由
        var viewport = makeViewport()
        var anchors: [Int] = []
        for flip in 0..<flips {
            let columns = flip % 2 == 0 ? 6 : 5
            if let anchor = viewport.relayout(.squareGrid(columns: columns, count: 1000), useSticky: false) {
                anchors.append(anchor.index)
            }
        }
        XCTAssertEqual(anchors.count, flips)
        XCTAssertEqual(anchors, anchors.sorted(by: >), "漂移只会向前：\(anchors)")
        XCTAssertLessThan(anchors.last!, anchors.first!, "应当漂掉：\(anchors)")
        XCTAssertGreaterThan(Set(anchors).count, 3, "应当一路换锚点：\(anchors)")
    }

    func testSelectedAnchorStaysPutAcrossColumnChangesEvenWithoutSticky() {
        // 有选中项时锚点就是选中项，不会漂，缩放后也始终可见
        var viewport = makeViewport(selected: [105])
        XCTAssertTrue(viewport.isVisible(105))
        for flip in 0..<flips {
            let columns = flip % 2 == 0 ? 6 : 5
            let anchor = viewport.relayout(.squareGrid(columns: columns, count: 1000), useSticky: false)
            XCTAssertEqual(anchor?.index, 105)
            XCTAssertTrue(viewport.isVisible(105), "第 \(flip) 次改列数后选中项不在可视区内")
        }
    }

    func testStickyAnchorSurvivesWithVariableHeightCells() {
        // 每项高度不同（行高取行内最高）：连续改列数后锚点仍可见、仍是同一项
        let heights: [CGFloat] = (0..<1000).map { [80, 120, 100, 140, 90][$0 % 5] }
        func layout(_ columns: Int) -> SyntheticLayout { SyntheticLayout(columns: columns, heights: heights, rowGap: 6) }
        var viewport = SyntheticViewport(layout: layout(4), top: 6000, height: 700)
        var anchors: [Int] = []
        for flip in 0..<flips {
            if let anchor = viewport.relayout(layout(flip % 2 == 0 ? 5 : 4)) {
                anchors.append(anchor.index)
                XCTAssertTrue(viewport.isVisible(anchor.index))
            }
        }
        XCTAssertEqual(anchors.count, flips)
        XCTAssertEqual(Set(anchors).count, 1, "\(anchors)")
    }

    func testRelayoutIntoContentShorterThanViewportLandsAtTop() {
        // 40 项 5 列共 8 行（800）→ 20 列只剩 2 行（200），比可视区（400）还矮：不能滚过头，锚点仍可见
        var viewport = SyntheticViewport(layout: SyntheticLayout(columns: 5, cellHeight: 100, count: 40), top: 300, height: 400)
        let anchor = viewport.relayout(SyntheticLayout(columns: 20, cellHeight: 100, count: 40))
        XCTAssertEqual(anchor?.index, 15)
        XCTAssertEqual(viewport.top, 0)
        XCTAssertTrue(viewport.isVisible(15))
    }

    func testRelayoutToShorterContentWhileAtTheBottomClampsToMaxTop() {
        // 滚到底（内容 800、可视区 400、top 400）后改成 8 列（5 行 = 500）：锚点在新布局里顶边是 200，本想让它贴着可视区顶边，
        // 但内容只有 500，最多滚到 100
        var viewport = SyntheticViewport(layout: SyntheticLayout(columns: 5, cellHeight: 100, count: 40), top: 400, height: 400)
        let anchor = viewport.relayout(SyntheticLayout(columns: 8, cellHeight: 100, count: 40))
        XCTAssertEqual(anchor?.index, 20)
        XCTAssertEqual(viewport.top, 100, accuracy: 0.0001)
        XCTAssertTrue(viewport.isVisible(20))
    }

    func testAtTopStaysAtTopAndDropsSticky() {
        var viewport = SyntheticViewport(layout: .squareGrid(columns: 5, count: 1000), top: 0, height: 800, selected: [3], sticky: 40)
        let anchor = viewport.relayout(.squareGrid(columns: 6, count: 1000))
        XCTAssertNil(anchor)
        XCTAssertEqual(viewport.top, 0)
        XCTAssertNil(viewport.sticky)
    }

    func testManualScrollAfterZoomKeepsAnchoringTheStickyItemWhileVisible() {
        // 已知取舍（modules.md）：缩放后手动滚动、该文件仍在可视区内，下一次缩放仍锚定它，并保持它在屏幕上的新位置
        var viewport = makeViewport()
        let first = viewport.relayout(.squareGrid(columns: 6, count: 1000))!
        viewport.top -= 150   // 往回滚一点，锚点在屏幕上下移 150，仍可见
        XCTAssertTrue(viewport.isVisible(first.index))
        let offsetBefore = viewport.offsetOnScreen(of: first.index)!
        let second = viewport.relayout(.squareGrid(columns: 5, count: 1000))
        XCTAssertEqual(second?.index, first.index)
        XCTAssertEqual(viewport.offsetOnScreen(of: first.index) ?? .nan, offsetBefore, accuracy: 0.0001)
    }

    func testStickyIsReplacedOnceScrolledAway() {
        // 手动滚到别处、sticky 不再可见：重新取顶部项，而不是跳回旧位置
        var viewport = makeViewport()
        let first = viewport.relayout(.squareGrid(columns: 6, count: 1000))!
        viewport.top += 5000
        XCTAssertFalse(viewport.isVisible(first.index))
        let second = viewport.relayout(.squareGrid(columns: 5, count: 1000))
        XCTAssertNotNil(second)
        XCTAssertNotEqual(second?.index, first.index)
        XCTAssertTrue(viewport.isVisible(second!.index))
    }

    func testSelectionTakesOverFromStaleSticky() {
        var viewport = makeViewport(selected: [105])
        viewport.sticky = 120
        XCTAssertEqual(viewport.capture()?.index, 105)
    }

    // MARK: - 模型：可视区高度变化

    func testViewportHeightChangeScalesTheAnchorOffsetProportionally() {
        // 同一布局，可视区 800 → 400 → 800：锚点距可视区顶边 200 → 100 → 200
        let layout = SyntheticLayout.squareGrid(columns: 5, count: 1000)
        var viewport = SyntheticViewport(layout: layout, top: 2600, height: 800, sticky: nil)
        // 第 21 行 [2520, 2640) 只露出 40，顶部项是第 22 行行首 110，距顶边 40；记下这个距离
        let anchor = viewport.relayout(layout)!
        let index = anchor.index
        let before = viewport.offsetOnScreen(of: index)!
        XCTAssertEqual(before, anchor.offsetInViewport, accuracy: 0.0001)

        viewport.relayout(layout, newHeight: 400)
        XCTAssertEqual(viewport.offsetOnScreen(of: index) ?? .nan, before / 2, accuracy: 0.0001)

        viewport.relayout(layout, newHeight: 800)
        XCTAssertEqual(viewport.offsetOnScreen(of: index) ?? .nan, before, accuracy: 0.0001)
    }

    func testViewportHeightChangeKeepsAnchorVisibleWhenGrowingAndShrinking() {
        var viewport = makeViewport(selected: [105])
        for height in [500, 1200, 300, 900] as [CGFloat] {
            viewport.relayout(viewport.layout, newHeight: height)
            XCTAssertTrue(viewport.isVisible(105), "可视区高度 \(height) 时选中项不在可视区内")
        }
    }
}
