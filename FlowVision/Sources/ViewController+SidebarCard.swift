// MARK: - 两段式结构样式：灰色外壳（侧边栏列）+ 内容 pane 的连续圆角分界
// MARK: - Two-part structure: gray shell (sidebar column) + continuous content-pane edge

import Cocoa

/// 内容 pane 的弧外背景。这里不能使用透明材质：pane 靠近窗口底部时，
/// 半透明材质会采样窗口外的 Dock，导致圆角下面出现脏色或暗色楔形。
/// Background outside the rounded content surface. It must be opaque: near
/// the bottom of the window, a translucent material can sample the Dock and
/// create a dirty wedge below the rounded corner.
private final class ContentPaneShellView: NSView {
    var fillColor: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        dirtyRect.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 背景层不能挡住内容 pane 或分割线的交互。
        // The background layer must not intercept content or divider events.
        return nil
    }
}

/// 内容白面只在靠侧边栏的一侧做圆角；边界完全由填充 path 的反锯齿自然形成。
/// The content surface rounds only its leading side; its boundary is formed
/// solely by the antialiased fill path so no second line can drift from it.
private final class ContentPaneSurfaceView: NSView {
    var contentColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 12 {
        didSet { needsDisplay = true }
    }

    var leadingEdgeIsLeft = true {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 这是纯视觉层，不能挡住 collectionView 的点击和滚动。
        // This is a visual-only layer and must not intercept collection input.
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let radius = min(cornerRadius, min(bounds.height / 2, bounds.width / 2))
        let path = leadingSurfacePath(in: bounds, radius: radius)

        contentColor.setFill()
        path.fill()
    }

    private func leadingSurfacePath(in rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let k: CGFloat = 0.5522847498

        if leadingEdgeIsLeft {
            path.move(to: NSPoint(x: left + radius, y: top))
            path.line(to: NSPoint(x: right, y: top))
            path.line(to: NSPoint(x: right, y: bottom))
            path.line(to: NSPoint(x: left + radius, y: bottom))
            path.curve(
                to: NSPoint(x: left, y: bottom - radius),
                controlPoint1: NSPoint(x: left + radius * (1 - k), y: bottom),
                controlPoint2: NSPoint(x: left, y: bottom - radius * (1 - k))
            )
            path.line(to: NSPoint(x: left, y: top + radius))
            path.curve(
                to: NSPoint(x: left + radius, y: top),
                controlPoint1: NSPoint(x: left, y: top + radius * (1 - k)),
                controlPoint2: NSPoint(x: left + radius * (1 - k), y: top)
            )
        } else {
            path.move(to: NSPoint(x: left, y: top))
            path.line(to: NSPoint(x: right - radius, y: top))
            path.curve(
                to: NSPoint(x: right, y: top + radius),
                controlPoint1: NSPoint(x: right - radius * (1 - k), y: top),
                controlPoint2: NSPoint(x: right, y: top + radius * (1 - k))
            )
            path.line(to: NSPoint(x: right, y: bottom - radius))
            path.curve(
                to: NSPoint(x: right - radius, y: bottom),
                controlPoint1: NSPoint(x: right, y: bottom - radius * (1 - k)),
                controlPoint2: NSPoint(x: right - radius * (1 - k), y: bottom)
            )
            path.line(to: NSPoint(x: left, y: bottom))
            path.close()
        }

        path.close()
        return path
    }

}

extension ViewController {

    /// 侧边栏：实心灰，铺满左列全高（无内缩无圆角）
    /// Sidebar: solid gray, full-bleed, no inset or rounding
    func applySidebarCardStyle() {
        let contentView = view
        guard let effectView = findSidebarEffectView(in: contentView),
              let sidebarPane = effectView.superview else { return }

        // 侧边栏和内容 pane 的圆角外侧必须共享同一块确定性的底色。
        // NSVisualEffectView 即使设置为 withinWindow，仍会在窗口边界参与材质合成；
        // 这会让侧边栏和圆角外壳出现不同色阶。保留 storyboard 里的 effect view
        // 作为兼容占位，但由同一个不透明背景 view 负责最终绘制。
        // The sidebar and the rounded pane's outside area must share one stable
        // color. NSVisualEffectView can still introduce a different material
        // grade at the window edge, so keep it as a storyboard placeholder but
        // let one opaque background view own the final pixels.
        effectView.isHidden = true

        let backgroundView: ContentPaneShellView
        if let existing = sidebarPane.subviews.first(where: { $0 is ContentPaneShellView }) as? ContentPaneShellView {
            backgroundView = existing
        } else {
            backgroundView = ContentPaneShellView(frame: sidebarPane.bounds)
            sidebarPane.addSubview(backgroundView, positioned: .below, relativeTo: outlineScrollView)
        }
        backgroundView.fillColor = NSColor.windowBackgroundColor
        backgroundView.frame = sidebarPane.bounds
        backgroundView.autoresizingMask = [.width, .height]
    }

    /// 内容区：pane 全高铺外壳，内容白面只在 leading 侧做 12pt 圆角。
    /// Content: shell fills the pane; the white surface rounds only its leading side.
    func applyContentCardStyle() {
        applySidebarCardStyle()

        guard let splitView = findSplitView(in: view),
              let scrollView = findMainScrollView(in: view),
              let pane = scrollView.superview,
              splitView.arrangedSubviews.contains(where: { $0 === pane }) else { return }

        // 分栏间隙由 NSSplitView 自身露出；若保留窗口的 OutlineViewBgColor，
        // 会在灰色侧边栏与白色内容面之间形成一列更亮的直线。
        // The divider gap is exposed by NSSplitView itself. Its default
        // OutlineViewBgColor is lighter than the sidebar and creates a bright
        // straight seam between the gray sidebar and the white content pane.
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // pane 本体透明，圆角外侧露出确定性的窗口背景。
        // Keep the pane transparent so the opaque shell is visible outside the surface.
        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor.clear.cgColor

        let shellView: ContentPaneShellView
        if let existing = pane.subviews.first(where: { $0 is ContentPaneShellView }) as? ContentPaneShellView {
            shellView = existing
        } else {
            shellView = ContentPaneShellView(frame: pane.bounds)
            pane.addSubview(shellView, positioned: .below, relativeTo: scrollView)
        }
        shellView.fillColor = NSColor.windowBackgroundColor
        shellView.frame = pane.bounds
        shellView.autoresizingMask = [.width, .height]

        let surfaceView: ContentPaneSurfaceView
        if let existing = pane.subviews.first(where: { $0 is ContentPaneSurfaceView }) as? ContentPaneSurfaceView {
            surfaceView = existing
        } else {
            surfaceView = ContentPaneSurfaceView(frame: pane.bounds)
            pane.addSubview(surfaceView, positioned: .above, relativeTo: shellView)
        }
        surfaceView.frame = pane.bounds
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.cornerRadius = 12
        surfaceView.leadingEdgeIsLeft = splitView.userInterfaceLayoutDirection != .rightToLeft
        surfaceView.contentColor = NSApp.effectiveAppearance.name == .darkAqua
            ? hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_DARK)
            : hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_LIGHT)

        // 清掉 AppKit 在 scroll/clip/collection 链上的矩形背景，避免盖住圆角外壳。
        // Clear AppKit's rectangular backgrounds so they cannot cover the rounded shell.
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor

        let clipView = scrollView.contentView
        clipView.drawsBackground = false
        clipView.backgroundColor = .clear
        clipView.wantsLayer = true
        clipView.layer?.backgroundColor = NSColor.clear.cgColor

        if let collectionView = scrollView.documentView as? NSCollectionView {
            // 使用一个明确的 clear 色，避免 [] 回退成系统默认的 opaque fill view。
            // An explicit clear color avoids [] falling back to AppKit's opaque fill.
            collectionView.backgroundColors = [.clear]
            collectionView.wantsLayer = true
            collectionView.layer?.backgroundColor = NSColor.clear.cgColor
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
