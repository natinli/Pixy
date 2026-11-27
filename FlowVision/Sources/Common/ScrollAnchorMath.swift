//
//  ScrollAnchorMath.swift
//  FlowVision
//

import Foundation
import CoreGraphics

/// 浏览位置锚点里不依赖 AppKit 的纯数学部分：「选哪一项当锚点」和「滚到哪」。
/// AppKit 层（LayoutManagement.swift）只负责取 frame / 可视区、调用这里、再滚动，便于用合成布局做模型测试。
/// The AppKit-free math behind the browsing-position anchor: which item to anchor and where to scroll.
/// LayoutManagement.swift only reads frames / the visible rect, calls in here, then scrolls.
enum ScrollAnchorMath {

    /// 选锚点。返回 nil 表示不锚定视口（原本就在顶部，或可视区内没有可用项）；此时调用方仍应保留选中项信息。
    /// Pick the anchor item. nil means "do not anchor the viewport" (already at the top, or nothing usable is visible);
    /// the caller still keeps the selection.
    ///
    /// 决策顺序 / Order of precedence:
    /// 1. 可视区 minY <= 0.5：在顶部，返回 nil。At the top: nil.
    /// 2. `selected`（调用方已按升序排好）里第一个与可视区相交的项。First selected item intersecting the visible rect.
    /// 3. `sticky`（上一次缩放恢复到的锚点）仍与可视区相交：继续用它；若每次都重选顶部行首，重排后行首会落到原锚点之前，连续缩放就会一行行往前漂。
    ///    The previous zoom's anchor if still on screen; re-picking the row start each time drifts backwards on every zoom.
    /// 4. 可视区顶部的项：先在「中点不低于可视区顶边」（至少露出一半）的项里取 minY 最小者，并列取 index 小的；一个都没有则退回「最靠上的相交项」（规则相同）。
    ///    Topmost item that is at least half visible (smallest minY, ties by lower index), else the topmost intersecting item.
    ///
    /// - Parameters:
    ///   - selected: 选中项的 index，升序。越界 / 取不到 frame 的会被忽略。Selected item indexes, ascending.
    ///   - sticky: 已由调用方校验过身份的上一次锚点 index，没有则 nil。Previous anchor index, already identity-checked by the caller.
    ///   - visibleRect: 可视区（已扣除 contentInsets），高度必须 > 0（调用方 makeScrollAnchor 已保证；零高度矩形会让「相交」退化成点命中）。
    ///     Visible rect without content insets; its height must be > 0 (makeScrollAnchor guarantees it; a zero-height rect turns "intersects" into a point hit).
    ///   - frameOf: 取某项 frame；项不存在返回 nil。高度 <= 0 的 frame 在这里一律视为不可用。Frame lookup; zero-height frames are ignored here.
    ///   - visibleCandidates: 第 4 步才会调用（且至多一次）：布局认为落在可视区内的项的 index，顺序无关。
    ///     Only invoked for step 4, at most once: indexes the layout reports for the visible rect, order irrelevant.
    static func pickAnchor(selected: [Int],
                           sticky: Int?,
                           visibleRect: CGRect,
                           frameOf: (Int) -> CGRect?,
                           visibleCandidates: () -> [Int]) -> (index: Int, frame: CGRect)? {
        // 原本就在顶部：不锚定视口，缩放后仍从顶部开始。
        // Already at the top: no viewport anchor, the view stays at the top after zooming.
        let isAtTop = visibleRect.minY <= 0.5
        if isAtTop { return nil }

        func usableFrame(_ index: Int) -> CGRect? {
            guard let frame = frameOf(index), frame.height > 0 else { return nil }
            return frame
        }

        for index in selected {
            if let frame = usableFrame(index), frame.intersects(visibleRect) {
                return (index, frame)
            }
        }

        if let sticky, let frame = usableFrame(sticky), frame.intersects(visibleRect) {
            return (sticky, frame)
        }

        // 优先露出至少一半的项，避免锚到几乎被顶边裁掉的那一行。
        // Prefer items at least half visible so a row mostly scrolled off the top is not chosen.
        var best: (frame: CGRect, item: Int)?
        var fallback: (frame: CGRect, item: Int)?
        for index in visibleCandidates() {
            guard let frame = usableFrame(index), frame.intersects(visibleRect) else { continue }
            let candidate = (frame: frame, item: index)
            func isBetter(_ current: (frame: CGRect, item: Int)?) -> Bool {
                guard let current else { return true }
                if frame.minY != current.frame.minY { return frame.minY < current.frame.minY }
                return index < current.item
            }
            if frame.midY >= visibleRect.minY {
                if isBetter(best) { best = candidate }
            } else if isBetter(fallback) {
                fallback = candidate
            }
        }
        if let chosen = best ?? fallback {
            return (chosen.item, chosen.frame)
        }
        return nil
    }

    /// 视口要滚到的 y（可直接传给 `clipView.scroll(to:)`，已减去 `insetTop`）：让锚点项在新布局里保持原来的相对高度。
    /// 可视区高度变了就按比例缩放偏移，并夹到合法范围。
    /// The y to scroll the clip view to (already minus `insetTop`) so the anchor item keeps its relative height on screen
    /// in the new layout; the offset is scaled if the viewport height changed, then clamped.
    ///
    /// - Parameters:
    ///   - anchorMinY / anchorHeight: 锚点项在新布局里的 frame.minY / frame.height。Anchor item frame in the new layout.
    ///   - offsetInViewport: 捕获时锚点项顶边相对可视区顶边的距离。Distance from the visible top to the anchor top at capture time.
    ///   - oldViewportHeight: 捕获时的可视区高度。Visible height at capture time.
    ///   - newViewportHeight: 现在的可视区高度（已扣除 contentInsets）。Visible height now, without content insets.
    ///   - contentHeight: 现在的内容总高度（collectionView.frame.height）。Current content height.
    ///   - insetTop: clip view 的 contentInsets.top。
    static func targetScrollTop(anchorMinY: CGFloat,
                                anchorHeight: CGFloat,
                                offsetInViewport: CGFloat,
                                oldViewportHeight: CGFloat,
                                newViewportHeight: CGFloat,
                                contentHeight: CGFloat,
                                insetTop: CGFloat) -> CGFloat {
        var offset = offsetInViewport
        if oldViewportHeight > 0, newViewportHeight > 0, abs(oldViewportHeight - newViewportHeight) > 0.5 {
            offset = offset * newViewportHeight / oldViewportHeight
        }
        offset = min(max(0, offset), max(0, newViewportHeight - anchorHeight))
        let maxTop = max(0, contentHeight - newViewportHeight)
        let targetTop = min(max(0, anchorMinY - offset), maxTop)
        return targetTop - insetTop
    }
}
