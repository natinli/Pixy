// MARK: - 两段式结构样式：灰色外壳（侧边栏列）+ 白色内容卡（圆角分界）
// MARK: - Two-part structure: gray shell (sidebar column) + white content card (rounded separation)

import Cocoa

extension ViewController {

    /// 侧边栏：内缩圆角卡片——四周留缝，四角圆角，与白色内容卡同为浮动卡片
    /// Sidebar as inset rounded card: margins on all sides, rounded corners, floating like the content card
    func applySidebarCardStyle() {
        let contentView = view
        guard let effectView = findSidebarEffectView(in: contentView) else { return }

        effectView.blendingMode = NSVisualEffectView.BlendingMode.withinWindow
        effectView.material = NSVisualEffectView.Material.windowBackground
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        // 内缩：上 6（工具栏行下方起）、左 6、下 6、右 4（与内容卡之间留分界缝）
        let inset: CGFloat = 6
        if let superviewBounds = effectView.superview?.bounds {
            effectView.frame = superviewBounds.insetBy(dx: inset, dy: inset)
            effectView.autoresizingMask = [.width, .height]
        }

        // 目录树 scrollView：内容避让圆角区
        var current: NSView? = outlineView
        while let v = current {
            if let scroll = v as? NSScrollView {
                scroll.contentInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
                break
            }
            current = v.superview
        }
    }

    /// 内容区白卡：四周留缝的浮动圆角卡片（上 52 给工具栏行，右/下 8，左 8 与侧边栏分界）
    /// White content card: floating rounded card with margins (top 52 for toolbar row, right/bottom 8, left 8 separating from sidebar)
    func applyContentCardStyle() {
        applySidebarCardStyle()

        guard let splitView = findSplitView(in: view),
              splitView.subviews.count >= 2 else { return }
        let pane = splitView.subviews[1]  // 右侧内容面板 / right content pane

        // 面板本体透明，露灰色外壳；白色卡片由 scrollView 层承担
        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor.clear.cgColor

        if let scrollView = findMainScrollView(in: pane) {
            scrollView.wantsLayer = true
            scrollView.layer?.backgroundColor = NSColor.white.cgColor
            scrollView.layer?.cornerRadius = 12
            scrollView.layer?.masksToBounds = true
            scrollView.contentInsets = NSEdgeInsets(top: 52, left: 8, bottom: 8, right: 8)
        }
    }

    // MARK: 视图查找

    private func findSidebarEffectView(in root: NSView) -> NSVisualEffectView? {
        if let v = root as? NSVisualEffectView, v.identifier?.rawValue == "PixySidebarEffect" {
            return v
        }
        for sub in root.subviews {
            if let found = findSidebarEffectView(in: sub) { return found }
        }
        return nil
    }

    private func findSplitView(in root: NSView) -> NSSplitView? {
        if let v = root as? NSSplitView { return v }
        for sub in root.subviews {
            if let found = findSplitView(in: sub) { return found }
        }
        return nil
    }

    private func findMainScrollView(in root: NSView) -> NSScrollView? {
        if let v = root as? NSScrollView, v.documentView is NSCollectionView { return v }
        for sub in root.subviews {
            if let found = findMainScrollView(in: sub) { return found }
        }
        return nil
    }
}
