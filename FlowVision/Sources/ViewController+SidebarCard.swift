// MARK: - 两段式结构样式：灰色外壳（侧边栏列）+ 白色内容卡（圆角分界）
// MARK: - Two-part structure: gray shell (sidebar column) + white content card (rounded separation)

import Cocoa

extension ViewController {

    /// 侧边栏：实心灰，铺满左列全高（无内缩无圆角）
    /// Sidebar: solid gray, full-bleed, no inset or rounding
    func applySidebarCardStyle() {
        let contentView = view
        guard let effectView = findSidebarEffectView(in: contentView) else { return }

        effectView.blendingMode = NSVisualEffectView.BlendingMode.withinWindow
        effectView.material = NSVisualEffectView.Material.windowBackground
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// 内容区：白色实心铺满右列（无内缩无圆角）
    /// Content: solid white filling the right pane, no inset or rounding
    func applyContentCardStyle() {
        applySidebarCardStyle()

        guard let splitView = findSplitView(in: view),
              splitView.subviews.count >= 2 else { return }
        let pane = splitView.subviews[1]  // 右侧内容面板 / right content pane

        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor.white.cgColor
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
