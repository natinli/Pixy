// MARK: - 工具栏透明融合（大图模式：标题栏透明 + 底部标题胶囊）
// MARK: - Toolbar transparency blend (large-image mode: transparent titlebar + bottom title pill)

import Cocoa

extension WindowController {

    /// 大图模式：标题栏透明，内容延伸到标题栏后方，工具栏浮在毛玻璃上
    /// Large-image mode: transparent titlebar, full-size content, toolbar floats over vibrancy
    func enableToolbarBlend() {
        guard let window = window else { return }
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.toolbar?.isVisible = true
        setupBottomTitleBar()
    }

    /// 退出大图模式（回到缩略图浏览）：保持两段式结构（透明标题栏），只隐藏底部标题
    /// Leaving large-image mode: KEEP the two-part structure (transparent titlebar), just hide the bottom pill
    func disableToolbarBlend() {
        guard let window = window else { return }
        window.titleVisibility = .hidden
        window.toolbar?.isVisible = true
        hideBottomTitleBar()
    }

    // MARK: 底部标题条（方案 1：分色同行——文件名实色 · 张数半透明）

    /// 在内容区底部中央显示标题胶囊：文件名 · 张数（张数弱化），浮在毛玻璃上
    /// Bottom-center title pill: "filename · count" with the count de-emphasized, over vibrancy
    private func setupBottomTitleBar() {
        guard let contentView = window?.contentView else { return }

        let pair: (bar: NSVisualEffectView, nameLabel: NSTextField, countLabel: NSTextField)
        if let bar = bottomTitleBar, let name = bottomTitleNameLabel, let count = bottomTitleCountLabel {
            pair = (bar, name, count)
        } else {
            pair = makeBottomTitleBar()
        }
        let bar = pair.bar
        let nameLabel = pair.nameLabel
        let countLabel = pair.countLabel

        if bar.superview == nil { contentView.addSubview(bar) }
        if nameLabel.superview == nil { contentView.addSubview(nameLabel) }
        if countLabel.superview == nil { contentView.addSubview(countLabel) }

        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            nameLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            countLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            // 水平排列：name 在左，count 在右，间距 6；两者共同撑开胶囊宽度
            countLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            countLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
        ])

        updateBottomTitleText()
    }

    private func makeBottomTitleBar() -> (bar: NSVisualEffectView, nameLabel: NSTextField, countLabel: NSTextField) {
        let bar = NSVisualEffectView()
        bar.material = .hudWindow
        bar.state = .active
        bar.blendingMode = .withinWindow
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 10
        bar.layer?.masksToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = NSColor.labelColor.withAlphaComponent(0.55)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        bottomTitleBar = bar
        bottomTitleNameLabel = nameLabel
        bottomTitleCountLabel = countLabel
        return (bar, nameLabel, countLabel)
    }

    /// 同步底部标题：name 实色，count 半透明（方案 1 分色同行）
    /// Sync bottom title: name full color, count de-emphasized (Plan 1)
    func updateBottomTitleText() {
        guard let bar = bottomTitleBar, let nameLabel = bottomTitleNameLabel, let countLabel = bottomTitleCountLabel else { return }
        let vc = contentViewController as? ViewController
        let name = vc?.publicVar.toolbarTitle ?? ""
        let count = vc?.publicVar.titleStatisticInfo ?? ""
        nameLabel.stringValue = name
        countLabel.stringValue = count
        bar.isHidden = name.isEmpty
        nameLabel.isHidden = name.isEmpty
        countLabel.isHidden = name.isEmpty || count.isEmpty
    }

    private func hideBottomTitleBar() {
        bottomTitleBar?.isHidden = true
        bottomTitleNameLabel?.isHidden = true
        bottomTitleCountLabel?.isHidden = true
    }

    // MARK: 状态存储

    private static var bottomTitleBarKey: Void?
    private static var bottomTitleNameLabelKey: Void?
    private static var bottomTitleCountLabelKey: Void?

    private var bottomTitleBar: NSVisualEffectView? {
        get { objc_getAssociatedObject(self, &Self.bottomTitleBarKey) as? NSVisualEffectView }
        set { objc_setAssociatedObject(self, &Self.bottomTitleBarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var bottomTitleNameLabel: NSTextField? {
        get { objc_getAssociatedObject(self, &Self.bottomTitleNameLabelKey) as? NSTextField }
        set { objc_setAssociatedObject(self, &Self.bottomTitleNameLabelKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var bottomTitleCountLabel: NSTextField? {
        get { objc_getAssociatedObject(self, &Self.bottomTitleCountLabelKey) as? NSTextField }
        set { objc_setAssociatedObject(self, &Self.bottomTitleCountLabelKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
