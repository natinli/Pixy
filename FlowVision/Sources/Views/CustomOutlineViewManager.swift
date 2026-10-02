//
//  CustomOutlineViewManager.swift
//  FlowVision
//

import Foundation
import Cocoa

class CustomOutlineViewManager: NSObject {
    var fileDB: DatabaseModel
    var treeViewData: TreeViewModel
    var ifActWhenSelected = true
    // 侧栏点击触发的目录切换需要保留选中态；内容区、路径栏等其他入口应清除侧栏选中。
    var isNavigatingFromSidebar = false
    // 路径定位只需要读取每一级的直接子项，避免启动时为用户主目录扫描所有后代目录。
    var suppressDeepChildInspection = false
    weak var outlineView: NSOutlineView?
    
    private var adjustColumnWidthWorkItem: DispatchWorkItem?

    private static let coreTypesResourceDirectory = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"

    private static func sidebarResourceImage(named resourceName: String) -> NSImage? {
        if let image = NSImage(named: resourceName) {
            image.isTemplate = true
            return image
        }
        let path = "\(coreTypesResourceDirectory)/\(resourceName)"
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        // Finder 将这些 CoreTypes 资源作为模板图标使用，再交给侧栏颜色统一着色。
        image.isTemplate = true
        return image
    }

    private func sidebarTagImage(for node: TreeNode) -> NSImage? {
        guard let url = TreeViewModel.normalizedURL(node.fullPath) else { return nil }
        if url.path == "/VirtualFinderTagsFolder" {
            return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
                NSColor.secondaryLabelColor.setStroke()
                for x: CGFloat in [2, 6] {
                    let ring = NSBezierPath(ovalIn: NSRect(x: x, y: 4, width: 8, height: 8))
                    ring.lineWidth = 1
                    ring.stroke()
                }
                return true
            }
        }
        let tag = FinderTag.byName(url.lastPathComponent)
        let color: NSColor
        switch tag?.colorIndex {
        case 1: color = .systemGray
        case 2: color = .systemGreen
        case 3: color = .systemPurple
        case 4: color = .systemBlue
        case 5: color = .systemYellow
        case 6: color = .systemRed
        case 7: color = .systemOrange
        default: color = tag?.color ?? .secondaryLabelColor
        }
        // 文件标签源色保持原样；侧栏圆点只采用系统语义色，以匹配 Finder。
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10)).fill()
            return true
        }
    }
    
    init(fileDB: DatabaseModel, treeViewData: TreeViewModel, outlineView: NSOutlineView) {
        self.fileDB = fileDB
        self.treeViewData = treeViewData
        self.outlineView = outlineView
    }
}

extension CustomOutlineViewManager: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let treeNode = item as? TreeNode else {
            return treeViewData.root?.children?.count ?? 0
        }
        return treeNode.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let treeNode = item as? TreeNode else {
            return treeViewData.root?.children?[index] ?? ""
        }
        return treeNode.children?[index] ?? ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let treeNode = item as? TreeNode else {
            return false
        }
        if treeNode.role == .separator || treeNode.role == .file { return false }
        if (treeNode.children?.count ?? 0) > 0 {
            return true
        }
        if treeNode.hasChild {
            return true
        }
        return false
    }
    func outlineViewItemWillExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? TreeNode {
            if ifActWhenSelected && item.isNavigable {
                treeViewData.activeSidebarEntryID = item.entryID
            }
            log("TreeData expand: \(item.fullPath)")
            treeViewData.expand(node: item, isLookSub: !suppressDeepChildInspection)
        }
    }

}
extension CustomOutlineViewManager: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        (item as? TreeNode)?.role != .group
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        // 分组使用普通行，自行控制标题间距，避免系统源列表额外叠加留白。
        false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? TreeNode)?.isSelectable == true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        (item as? TreeNode)?.role != .group
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch (item as? TreeNode)?.role {
        case .group: return (item as? TreeNode)?.entryID == "favorites" ? 18 : 32
        case .separator: return 10
        default: return 28
        }
    }


    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let treeNode = item as? TreeNode else { return nil }
        if treeNode.role == .group {
            let container = NSTableCellView()
            let title = NSTextField(labelWithString: treeNode.name)
            title.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(title)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                title.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: treeNode.entryID == "favorites" ? 0 : 7)
            ])
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            return container
        }
        if treeNode.role == .separator {
            let line = NSBox()
            line.boxType = .separator
            return line
        }
        guard let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("DataCell"), owner: self) as? CustomTableCellView else { return nil }
        view.textField?.stringValue = treeNode.localizedName ?? treeNode.name
        view.textField?.font = .systemFont(ofSize: 13)
        view.textField?.textColor = .labelColor
        view.textField?.lineBreakMode = .byTruncatingTail
        view.toolTip = treeNode.fileURL?.path ?? treeNode.name
        if treeNode.role == .tag {
            view.imageView?.image = sidebarTagImage(for: treeNode)
            view.imageView?.contentTintColor = nil
        } else {
            view.imageView?.image = treeNode.sidebarResourceName.flatMap(Self.sidebarResourceImage(named:))
                ?? NSImage(systemSymbolName: treeNode.symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
            view.imageView?.contentTintColor = treeNode.role == .volume ? .secondaryLabelColor : .systemBlue
        }
        let shouldShowEject = treeNode.role == .volume
            && treeNode.name == "Minimalist"
        view.ejectImageView.image = shouldShowEject
            ? NSImage(systemSymbolName: "eject", accessibilityDescription: NSLocalizedString("Eject", comment: "推出"))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            : nil
        view.ejectImageView.contentTintColor = .secondaryLabelColor
        let isCut = globalVar.cutItemPaths.contains(treeNode.fullPath)
        if isCut {
            view.alphaValue = 0.4
        } else if treeNode.fileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true {
            view.alphaValue = 0.4
        } else if treeNode.isHidden {
            view.alphaValue = 0.5
        } else {
            view.alphaValue = 1.0
        }
        
        return view
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        
        let selectedIndex = outlineView.selectedRow
        if selectedIndex != -1, let item = outlineView.item(atRow: selectedIndex) as? TreeNode {
            // 这里调用你的函数，例如:
            // Call your function here, for example:
            itemSelected(item)
        }
    }
    
    func itemSelected(_ item: TreeNode) {
        guard let viewController = getViewController(outlineView) else { return }
        guard item.isNavigable else { return }
        if item.role == .special {
            treeViewData.activeSidebarEntryID = item.entryID
            // 系统虚拟入口没有文件夹路径；交给 Finder 打开对应页面，Pixy 当前目录保持不变。
            let finderURL: URL?
            finderURL = item.entryID == "icloud:drive" ? URL(string: "x-apple-finder://iCloudDrive") : nil
            if let finderURL { NSWorkspace.shared.open(finderURL) }
            return
        }
        if let url = item.fileURL, !FileManager.default.fileExists(atPath: url.path) { return }
        if ifActWhenSelected {
            treeViewData.activeSidebarEntryID = item.entryID
            // log("Selected item: \(item.name)")
            // fileDB.lock()
            // let lastFolderPath = fileDB.curFolder
            // fileDB.curFolder = item.fullPath
            // log(fileDB.curFolder)
            // fileDB.unlock()
            // viewController.publicVar.folderStepStack.insert(lastFolderPath, at: 0)
            // 点击侧栏目录只切换内容；子目录由用户点击披露箭头按需展开。
            isNavigatingFromSidebar = true
            defer { isNavigatingFromSidebar = false }
            viewController.switchDirByDirection(direction: .zero, dest: item.fullPath, doCollapse: false, expandLast: false, skip: false, stackDeep: 0)
        }
        
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return CustomTableRowView()
    }
    
    func outlineViewItemDidExpand(_ notification: Notification) {
        adjustColumnWidth()
        
    }
    
    func outlineViewItemDidCollapse(_ notification: Notification) {
        adjustColumnWidth()
    }
    
    func adjustColumnWidth() {
        // 防抖：短时间内多次调用时，只执行最后一次
        // Debounce: when called frequently in a short time, only execute the last one
        adjustColumnWidthWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let outlineView = self.outlineView else { return }
            
            // 指定你需要调整的列的索引
            // Specify the index of the column you need to adjust
            let columnIndex = 0
            let column = outlineView.tableColumns[columnIndex]
            // 列宽归属滚动容器：长名截断并显示 tooltip，不横向撑大选中行。
            let width = outlineView.enclosingScrollView?.contentSize.width ?? outlineView.bounds.width
            if abs(column.width - width) > 0.5 { column.width = width }

        }
        
        adjustColumnWidthWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let node = item as? TreeNode, let url = node.fileURL,
              node.role != .file, FileManager.default.fileExists(atPath: url.path) else { return [] }
        outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let outlineItem = item as? TreeNode, outlineItem.role != .file, outlineItem.fileURL != nil else { return false }
        guard let viewController = getViewController(outlineView) else { return false }

        if let targetUrl = outlineItem.fileURL {
            let pasteboard = info.draggingPasteboard
            if let data = pasteboard.data(forType: .fileURL),
               let pasteboardUrl = URL(dataRepresentation: data, relativeTo: nil),
               pasteboardUrl == targetUrl {
                // URLs are identical, do not perform the move
                return false
            }
            
            if viewController.handleFilePromiseDrop(targetURL: targetUrl, pasteboard: pasteboard) {
                return true
            }
            
            // 从outlineView自身拖拽时，显示确认对话框防止误操作
            if info.draggingSource is NSOutlineView,
               let data = pasteboard.data(forType: .fileURL),
               let sourceUrl = URL(dataRepresentation: data, relativeTo: nil) {
                let sourceName = sourceUrl.lastPathComponent
                let confirmed = showConfirmation(
                    title: NSLocalizedString("Move Items", comment: "移动项目"),
                    message: String(format: NSLocalizedString("Are you sure you want to move xxx to xxx?", comment: "确定要移动 xxx 到 xxx?"), sourceName, targetUrl.lastPathComponent)
                )
                if !confirmed {
                    return false
                }
            }
            
            viewController.handleMove(targetURL: targetUrl, pasteboard: pasteboard)
            return true
        }
        
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let outlineItem = item as? TreeNode, let url = outlineItem.fileURL else { return nil }
        
        let pasteboardItem = NSPasteboardItem()

        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        
        return pasteboardItem
    }
    
}

class CustomTableCellView: NSTableCellView {
    
    private var didSetupConstraints = false
    let ejectImageView = NSImageView()

    override func awakeFromNib() {
        super.awakeFromNib()

        guard !didSetupConstraints, let imageView = imageView, let textField = textField else { return }
        didSetupConstraints = true

        // 两种书写方向共享 leading/trailing 约束，正文垂直居中。

        imageView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        ejectImageView.translatesAutoresizingMaskIntoConstraints = false
        ejectImageView.imageScaling = .scaleProportionallyDown
        ejectImageView.contentTintColor = .secondaryLabelColor
        addSubview(ejectImageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Finder 将推出按钮留在行右侧约 24pt 的位置；不要让它贴到侧栏边界。
            ejectImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            ejectImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ejectImageView.widthAnchor.constraint(equalToConstant: 14),
            ejectImageView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    
//    override var backgroundStyle: NSView.BackgroundStyle {
//        didSet {
//            imageView?.contentTintColor = backgroundStyle == .emphasized ? NSColor.black : NSColor.green
//            // 检查是否处于选中状态
//            switch backgroundStyle {
//            case .emphasized: // 选中状态
//                textField?.textColor = NSColor.green
//                // 如果需要，还可以在这里修改imageView的contentTintColor
//            default: // 非选中状态
//                textField?.textColor = NSColor.red
//                // 根据需要恢复imageView的contentTintColor
//            }
//        }
//    }
}

class CustomTableRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }


    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
            // 边距
            // Margin
            let selectionRect = NSInsetRect(self.bounds, 10, 1.5)
            // 圆角半径
            // Corner radius
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
            
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let alpha: CGFloat = window?.isKeyWindow == true ? 0.16 : 0.10
            (dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()
            selectionPath.fill()
        }
    }

    // 侧边栏改为毛玻璃半透明：行背景不再填充纯色，透出底层 NSVisualEffectView
    // Sidebar uses vibrancy: row background no longer fills solid color, letting the underlying NSVisualEffectView show through
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.clear.setFill()
        __NSRectFillUsingOperation(dirtyRect, .sourceOver)

        // 右键选中行的边框
        // Border for right-clicked row
        // 边距
        // Margin
        let selectionRect = NSInsetRect(self.bounds, 9, 2.5)
        // 圆角半径
        // Corner radius
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
        // 获取当前 row 的 index
        // Get current row's index
        if let tableView = self.superview as? NSTableView {
            let rowIndex = tableView.row(for: self)
            if rowIndex == getViewController(self)?.outlineView.curRightClickedIndex {
                // 设置边框颜色
                // Set border color
                NSColor.controlAccentColor.setStroke()
                // 设置边框宽度
                // Set border width
                selectionPath.lineWidth = 2.0
                // 绘制边框
                // Draw border
                selectionPath.stroke()
            }
        }
    }
}
