// MARK: - 共享透明侧边栏材质与内容区单侧圆角

import Cocoa

/// 材质只负责绘制，不参与分栏布局，也不接收目录树的鼠标事件。
private final class SidebarBackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 内容白面只在靠侧边栏的一侧做圆角；边界完全由填充 path 的反锯齿自然形成。
/// The content surface rounds only its leading side; its boundary is formed
/// solely by the antialiased fill path so no second line can drift from it.
private final class ContentPaneSurfaceView: NSView {
    var contentColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 8 {
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

    /// 侧边栏使用窗口背后的透明材质，目录树和滚动容器保持透明。
    func applySidebarCardStyle() {
        guard let effectView = findSidebarEffectView(in: view),
              let sidebarPane = effectView.superview else { return }

        // 分栏共享一张材质背景，圆角外侧与目录栏连续。
        effectView.isHidden = true
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .followsWindowActiveState
        sidebarPane.wantsLayer = true
        sidebarPane.layer?.backgroundColor = NSColor.clear.cgColor

        outlineScrollView.drawsBackground = false
        outlineScrollView.backgroundColor = .clear
        outlineScrollView.contentView.drawsBackground = false
        outlineScrollView.contentView.backgroundColor = .clear
        outlineView.backgroundColor = .clear
        // 只隐藏滚动条，滚轮、触控板和键盘滚动继续由 NSScrollView 处理。
        outlineScrollView.hasVerticalScroller = false
        outlineScrollView.hasHorizontalScroller = false
    }

    /// 内容面板使用 8pt 单侧圆角，弧外露出共享侧边栏材质。
    func applyContentCardStyle() {
        applySidebarCardStyle()

        guard let splitView = findSplitView(in: view),
              let scrollView = findMainScrollView(in: view),
              let pane = scrollView.superview,
              splitView.arrangedSubviews.contains(where: { $0 === pane }),
              let container = splitView.superview else { return }

        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        let backdrop: SidebarBackdropView
        if let existing = container.subviews.first(where: { $0 is SidebarBackdropView }) as? SidebarBackdropView {
            backdrop = existing
        } else {
            backdrop = SidebarBackdropView(frame: splitView.frame)
            backdrop.identifier = NSUserInterfaceItemIdentifier("PixySplitBackdrop")
            // NSSplitView 会管理子视图几何；背景放在同级，避免被当作分栏调整。
            container.addSubview(backdrop, positioned: .below, relativeTo: splitView)
        }
        backdrop.material = .sidebar
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        backdrop.frame = splitView.frame
        backdrop.autoresizingMask = [.width, .height]

        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor.clear.cgColor

        let surfaceView: ContentPaneSurfaceView
        if let existing = pane.subviews.first(where: { $0 is ContentPaneSurfaceView }) as? ContentPaneSurfaceView {
            surfaceView = existing
        } else {
            surfaceView = ContentPaneSurfaceView(frame: pane.bounds)
            pane.addSubview(surfaceView, positioned: .below, relativeTo: scrollView)
        }
        surfaceView.frame = pane.bounds
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.cornerRadius = 8
        surfaceView.leadingEdgeIsLeft = splitView.userInterfaceLayoutDirection != .rightToLeft
        surfaceView.contentColor = NSApp.effectiveAppearance.name == .darkAqua
            ? hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_DARK)
            : hexToNSColor(hex: COLOR_COLLECTIONVIEW_BG_LIGHT)

        updateContentCornerMask()

        // scroll/clip/collection 使用透明背景，由内容面统一填充底色。
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

    /// 裁剪整条内容绘制链，缩略图滚动到边缘时也不能盖住圆角。
    func updateContentCornerMask() {
        guard let splitView = findSplitView(in: view),
              let pane = findMainScrollView(in: view)?.superview else { return }
        if let backdrop = splitView.superview?.subviews.first(where: { $0 is SidebarBackdropView }) {
            backdrop.frame = splitView.frame
        }
        let rect = pane.bounds
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(8, min(rect.width, rect.height) / 2)
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        let isRTL = splitView.userInterfaceLayoutDirection == .rightToLeft
        path.addRect(CGRect(x: isRTL ? rect.minX : rect.midX,
                            y: rect.minY, width: rect.width / 2, height: rect.height))
        let mask = (pane.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = rect
        mask.path = path
        pane.layer?.mask = mask
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
