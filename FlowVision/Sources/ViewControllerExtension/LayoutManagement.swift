//
//  LayoutManagement.swift
//  FlowVision
//

import Foundation
import Cocoa
import AVFoundation
import DiskArbitration

/// 目录重载前的浏览位置锚点（缩放、大目录的监听刷新）。按文件对象身份恢复，不依赖像素偏移或 index。
/// Browsing-position anchor captured before a directory reload (zoom, watcher refresh of a large folder); restored by file identity, not pixel offset or index.
struct ScrollAnchor {
    let folder: String
    /// 视口锚定的文件；缩放前在顶部时为 nil（恢复后仍在顶部，只恢复选中）。
    /// File to keep on screen; nil when the view was already at the top.
    let file: FileModel?
    let path: String
    /// 锚点项顶边相对可视区顶边的距离。
    /// Distance from the visible area top to the anchor item's top edge.
    let offsetInViewport: CGFloat
    let viewportHeight: CGFloat
    /// 缩放前的选中项，重新布局后选回（目录刷新本身会清空选中）。
    /// Selection before the zoom; reselected afterwards because the directory refresh clears it.
    let selectedFiles: [FileModel]
    /// 绑定到缩放触发的那一轮目录加载（dirModel.ver）；nil 表示尚未开始加载。
    /// The directory load (dirModel.ver) this anchor belongs to; nil until that load starts.
    var dirVer: Int?
}

extension ViewController {

    /// 可视区（扣除 contentInsets）在 collectionView 坐标系中的矩形。
    /// Visible area of the collection view, excluding scroll view content insets.
    private func visibleContentRectForAnchor() -> NSRect {
        let clipView = mainScrollView.contentView
        let insets = clipView.contentInsets
        return NSRect(x: clipView.bounds.minX,
                      y: clipView.bounds.minY + insets.top,
                      width: clipView.bounds.width,
                      height: max(0, clipView.bounds.height - insets.top - insets.bottom))
    }

    /// 目录重载前捕获锚点：可视区内有选中项取第一个，否则取顶部第一个可见项。
    /// Capture before a directory reload: first selected item inside the visible area, else the topmost visible item.
    func captureScrollAnchor() {
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()

        // 上一次缩放的锚点还没恢复（连续快速缩放），沿用它；此时视口还停在旧布局的位置，重新捕获只会锚到错的内容。
        // A previous zoom's anchor has not been restored yet (rapid repeated zoom): keep it, the viewport is stale.
        if var pending = publicVar.scrollAnchor, pending.folder == curFolder {
            pending.dirVer = nil
            publicVar.scrollAnchor = pending
            return
        }
        publicVar.scrollAnchor = nil

        guard curFolder != "",
              let layout = collectionView.collectionViewLayout else { return }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else { return }
        let visibleRect = visibleContentRectForAnchor()
        guard visibleRect.height > 0 else { return }

        func itemFrame(_ indexPath: IndexPath) -> NSRect? {
            guard indexPath.section == 0, indexPath.item < itemCount,
                  let frame = layout.layoutAttributesForItem(at: indexPath)?.frame,
                  frame.height > 0 else { return nil }
            return frame
        }

        let selection = collectionView.selectionIndexPaths.sorted()
        var anchorIndex: Int?
        var anchorFrame = NSRect.zero

        // 原本就在顶部：不锚定视口，缩放后仍从顶部开始。
        // Already at the top: no viewport anchor, the view stays at the top after zooming.
        let isAtTop = visibleRect.minY <= 0.5
        if !isAtTop {
            for indexPath in selection {
                if let frame = itemFrame(indexPath), frame.intersects(visibleRect) {
                    anchorIndex = indexPath.item
                    anchorFrame = frame
                    break
                }
            }
            if anchorIndex == nil, let lastFile = publicVar.lastZoomAnchorFile {
                // 上一次缩放的锚点仍在可视区内：继续用它。若每次都重选顶部行首，重排后行首会落到原锚点之前，连续缩放就会一行行往前漂。
                // The previous zoom's anchor is still on screen: keep it, otherwise re-picking the row start drifts backwards on every zoom.
                fileDB.lock()
                let lastIndex: Int? = fileDB.db[SortKeyDir(curFolder)]?.files.elementSafe(atOffset: lastFile.id)?.1 === lastFile ? lastFile.id : nil
                fileDB.unlock()
                if let lastIndex, let frame = itemFrame(IndexPath(item: lastIndex, section: 0)),
                   frame.intersects(visibleRect) {
                    anchorIndex = lastIndex
                    anchorFrame = frame
                }
            }
            if anchorIndex == nil {
                // 优先露出至少一半的项，避免锚到几乎被顶边裁掉的那一行。
                // Prefer items at least half visible so a row mostly scrolled off the top is not chosen.
                var best: (frame: NSRect, item: Int)?
                var fallback: (frame: NSRect, item: Int)?
                for attributes in layout.layoutAttributesForElements(in: visibleRect) {
                    guard let indexPath = attributes.indexPath,
                          let frame = itemFrame(indexPath),
                          frame.intersects(visibleRect) else { continue }
                    let candidate = (frame: frame, item: indexPath.item)
                    func isBetter(_ current: (frame: NSRect, item: Int)?) -> Bool {
                        guard let current else { return true }
                        if frame.minY != current.frame.minY { return frame.minY < current.frame.minY }
                        return indexPath.item < current.item
                    }
                    if frame.midY >= visibleRect.minY {
                        if isBetter(best) { best = candidate }
                    } else if isBetter(fallback) {
                        fallback = candidate
                    }
                }
                if let chosen = best ?? fallback {
                    anchorIndex = chosen.item
                    anchorFrame = chosen.frame
                }
            }
        }

        fileDB.lock()
        let files = fileDB.db[SortKeyDir(curFolder)]?.files
        let anchorFile = anchorIndex.flatMap { files?.elementSafe(atOffset: $0)?.1 }
        let selectedFiles = selection.compactMap { files?.elementSafe(atOffset: $0.item)?.1 }
        fileDB.unlock()

        guard anchorFile != nil || !selectedFiles.isEmpty else { return }
        publicVar.scrollAnchor = ScrollAnchor(
            folder: curFolder,
            file: anchorFile,
            path: anchorFile?.path ?? "",
            offsetInViewport: anchorFile == nil ? 0 : anchorFrame.minY - visibleRect.minY,
            viewportHeight: visibleRect.height,
            selectedFiles: selectedFiles,
            dirVer: nil)
    }

    /// 文件监听触发刷新前调用：>5000 文件的目录会清空重插而回到顶部，先记下浏览位置；
    /// ≤5000 的目录由 reloadData 自身保持位置，无需锚点。目录文件数恰好跨过阈值（刷新后才超过）时也捕获。
    /// Before a watcher-triggered refresh: folders over the threshold are cleared and re-inserted (view jumps to the top), so remember the position;
    /// smaller folders keep it through reloadData. A folder about to cross the threshold is captured too.
    func captureScrollAnchorForRefresh() {
        fileDB.lock()
        let fileNum = fileDB.db[SortKeyDir(fileDB.curFolder)]?.files.count ?? 0
        fileDB.unlock()
        guard fileNum >= RESET_VIEW_FILE_NUM_THRESHOLD else { return }
        captureScrollAnchor()
    }

    /// 目录加载开始时调用：锚点绑定到这一轮加载；换了目录或又一轮加载则作废。
    /// Called when a directory load starts: bind the anchor to this load, drop it for another folder or a later load.
    func bindScrollAnchorToLoad(folder: String, ver: Int) {
        guard var anchor = publicVar.scrollAnchor else { return }
        if anchor.folder == folder && anchor.dirVer == nil {
            anchor.dirVer = ver
            publicVar.scrollAnchor = anchor
        } else {
            publicVar.scrollAnchor = nil
        }
    }

    /// 布局就绪后恢复锚点（只恢复一次）。isFinal 表示本轮加载已结束，无法恢复也要作废。
    /// Restore the anchor once the layout is ready (one shot). isFinal: the load is complete, drop it either way.
    func restoreScrollAnchorIfReady(folder: String, ver: Int, isFinal: Bool) {
        guard let anchor = publicVar.scrollAnchor,
              anchor.folder == folder,
              anchor.dirVer == ver else { return }

        fileDB.lock()
        let curFolder = fileDB.curFolder
        let files = fileDB.db[SortKeyDir(folder)]?.files
        func indexOf(_ file: FileModel) -> Int? {
            guard let element = files?.elementSafe(atOffset: file.id), element.1 === file else { return nil }
            return file.id
        }
        var anchorIndex: Int?
        if let file = anchor.file {
            anchorIndex = indexOf(file)
            if anchorIndex == nil, let files {
                // 文件在刷新中被替换成新对象（如内容变化）时按路径兜底。
                // Fallback by path when the file model was replaced during the refresh.
                for (offset, element) in files.enumerated() where element.1.path == anchor.path {
                    anchorIndex = offset
                    break
                }
            }
        }
        let selectedIndexes = anchor.selectedFiles.compactMap { indexOf($0) }
        fileDB.unlock()

        guard curFolder == folder, anchor.file == nil || anchorIndex != nil else {
            publicVar.scrollAnchor = nil
            return
        }

        // 只需选回选中项（缩放前在顶部）：等本轮加载结束再选，避免分批插入时只选回一部分。
        // Selection-only anchor (view was at the top): wait for the load to finish so the whole selection can be restored.
        if anchor.file == nil && !isFinal { return }

        let itemCount = collectionView.numberOfItems(inSection: 0)
        var anchorFrame: NSRect?
        if let anchorIndex {
            if anchorIndex < itemCount {
                collectionView.layoutSubtreeIfNeeded()
                anchorFrame = collectionView.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: anchorIndex, section: 0))?.frame
            }
            if anchorFrame == nil {
                // 锚点项还没插入或布局未就绪，留待下一批插入再试。
                // Anchor item not inserted / laid out yet; retry on the next insert batch.
                if isFinal { publicVar.scrollAnchor = nil }
                return
            }
        }
        publicVar.scrollAnchor = nil
        publicVar.lastZoomAnchorFile = anchorFrame != nil ? anchor.file : nil

        if let anchorFrame {
            let clipView = mainScrollView.contentView
            let insets = clipView.contentInsets
            let visibleRect = visibleContentRectForAnchor()
            var offset = anchor.offsetInViewport
            if anchor.viewportHeight > 0, visibleRect.height > 0, abs(anchor.viewportHeight - visibleRect.height) > 0.5 {
                offset = offset * visibleRect.height / anchor.viewportHeight
            }
            offset = min(max(0, offset), max(0, visibleRect.height - anchorFrame.height))
            let maxTop = max(0, collectionView.frame.height - visibleRect.height)
            let targetTop = min(max(0, anchorFrame.minY - offset), maxTop)
            clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: targetTop - insets.top))
            mainScrollView.reflectScrolledClipView(clipView)
            // 目录刷新时网格先被清空、clip 被压回 0；若恢复的位置恰好等于缩放前的位置，NSCollectionView 察觉不到变化，
            // 可见 item 仍停在顶部那一批，屏幕一片空白。让布局失效一次，强制按当前可视区重新铺 item。
            // The refresh clamps the clip to 0; if we land exactly on the pre-zoom origin, NSCollectionView keeps the
            // items tiled for the top and the screen stays blank. Invalidate once so it retiles for the current visible rect.
            collectionView.collectionViewLayout?.invalidateLayout()
        }

        let selection = Set(selectedIndexes.filter { $0 < itemCount }.map { IndexPath(item: $0, section: 0) })
        if !selection.isEmpty {
            collectionView.selectItems(at: selection, scrollPosition: [])
        }
        setLoadThumbPriority(ifNeedVisable: true)
    }

    func changeWaterfallLayoutNumberOfColumns(){
        var singleWidth = Double(publicVar.profile.thumbSize) / 512 * 300
        
        let scrollbarWidth = publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth=self.mainScrollView.bounds.width - scrollbarWidth - 2 * publicVar.profile.ThumbnailCellPadding
        if totalWidth < 25 {totalWidth = 25}
        if publicVar.isInLargeView && globalVar.portableMode {totalWidth = 1000}
        
        var columnNum = Int(ceil(totalWidth / singleWidth))
        if columnNum <= 0 {columnNum=1}
        publicVar.waterfallLayout.numberOfColumns = columnNum
    }
    
    func recalcLayout(_ targetFolder: String){
        recalcLayoutTimes+=1
        // log("recalcLayout:"+String(recalcLayoutTimes))
        
        // var WIDTH_THRESHOLD=6.0/2000
        var WIDTH_THRESHOLD=6.4/1920*512/Double(publicVar.profile.thumbSize)
        
        if publicVar.profile.layoutType == .grid {
            WIDTH_THRESHOLD=10.0/1920*512/Double(publicVar.profile.thumbSize)
        }
        
        let scrollbarWidth = publicVar.profile.ThumbnailScrollbarWidth
        var totalWidth = self.mainScrollView.bounds.width - scrollbarWidth - 2 * publicVar.profile.ThumbnailCellPadding
        if totalWidth < 25 {totalWidth = 25}
        if publicVar.isInLargeView && globalVar.portableMode {totalWidth = 1000}
        
        let actualThreshold=WIDTH_THRESHOLD*totalWidth
        var sum=0.0
        var lineCount=0
        var singleIds=[FileModel]()
        var lastSingleHeight:Double?
        
        fileDB.lock()
        guard let dirModel = fileDB.db[SortKeyDir(targetFolder)] else {
            fileDB.unlock()
            return
        }
        let count = dirModel.files.count
        let fileCount = dirModel.fileCount
        let layoutCalcPos = dirModel.layoutCalcPos
        // let startKey = fileDB.db[targetFolder]!.files.elementSafe(atOffset: layoutCalcPos).0
        if layoutCalcPos>0 {
            if let thumbSize=dirModel.files.elementSafe(atOffset: layoutCalcPos-1)?.1.thumbSize {
                lastSingleHeight = thumbSize.height - (2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
            }
        }
        if layoutCalcPos < count {
            for i in layoutCalcPos...(count-1) {
                guard let file = dirModel.files.elementSafe(atOffset: i)?.1 else{break}
                guard var originalSize=file.originalSize else{break}
                if file.canBeCalcued != true {break}

                // if publicVar.profile.layoutType == .grid { originalSize=DEFAULT_SIZE }
                sum+=(originalSize.width/originalSize.height)
                singleIds.append(file)
                if sum>=actualThreshold || i==count-1 {
                    sum=max(sum,actualThreshold)
                    var singleHeight = floor((totalWidth - 2 * (publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding) * Double(singleIds.count))/sum)
                    // 防止最后一行不一样大小
                    // Prevent last row from having different size
                    // if publicVar.profile.layoutType == .grid && lastSingleHeight != nil { singleHeight=lastSingleHeight! }
                    lastSingleHeight=singleHeight
                    for singleId in singleIds{
                        var originalSizeSingle=singleId.originalSize!
                        
                        // if publicVar.profile.layoutType == .grid { originalSizeSingle=DEFAULT_SIZE }
                        
                        var singleWidth = floor(originalSizeSingle.width/originalSizeSingle.height*singleHeight)
                        
                        if publicVar.profile.layoutType == .waterfall {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            singleWidth = floor(totalWidth/numberOfColumns-2*(publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding))
                            singleHeight = round(originalSizeSingle.height/originalSizeSingle.width*singleWidth)
                        }
                        
                        if publicVar.profile.layoutType == .grid {
                            let numberOfColumns=Double(publicVar.waterfallLayout.numberOfColumns)
                            let sideLength = floor(totalWidth/CGFloat(numberOfColumns+1)-2*(publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailCellPadding))
                            let squareFrame = NSRect(x: 0, y: 0, width: sideLength, height: sideLength)
                            let newFrame = AVMakeRect(aspectRatio: originalSizeSingle, insideRect: squareFrame)
                            singleWidth = round(newFrame.width)
                            singleHeight = round(newFrame.height)
                        }
                        
                        let size=NSSize(width: singleWidth+2*publicVar.profile.ThumbnailBorderThickness, height: singleHeight+2*publicVar.profile.ThumbnailBorderThickness+publicVar.profile.ThumbnailFilenamePadding)
                        singleId.thumbSize=size
                        singleId.lineNo=lineCount
                    }
                    for singleId in singleIds.reversed(){
                        singleId.isLayoutCalcued=true
                    }
                    singleIds=[]
                    sum=0.0
                    lineCount+=1
                    dirModel.layoutCalcPos=i+1
                }
            }
        }
        fileDB.unlock()
    }
    
    func switchToJustifiedView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.justified, forKey: "layoutType")
        if !doNotRefresh { captureScrollAnchor() }
        publicVar.profile.layoutType = .justified
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToGridView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.grid, forKey: "layoutType")
        if !doNotRefresh { captureScrollAnchor() }
        publicVar.profile.layoutType = .grid
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToWaterfallView(doNotRefresh: Bool = false){
//        let defaults = UserDefaults.standard
//        defaults.setEnum(LayoutType.waterfall, forKey: "layoutType")
        if !doNotRefresh { captureScrollAnchor() }
        publicVar.profile.layoutType = .waterfall
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        publicVar.updateToolbar()
        publicVar.isNeedChangeLayoutType = true
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func switchToDetailView(doNotRefresh: Bool = false){
        assertionFailure()
        return
    }
    
    func changeThumbSize(thumbSize: Int, doNotRefresh: Bool = false){
        // 所有缩放入口都经过这里：改尺寸前记下正在看的内容，重新布局后再按文件身份找回。
        // Every zoom entry funnels through here: remember what is on screen before the size changes.
        captureScrollAnchor()
        publicVar.profile.thumbSize = thumbSize
        // UserDefaults.standard.set(thumbSize, forKey: "thumbSize")
        publicVar.profile.saveToUserDefaults(withKey: "CustomStyle_v2_current")
        changeWaterfallLayoutNumberOfColumns()
        if !doNotRefresh {
            refreshCollectionView(dryRun: true, needLoadThumbPriority: true)
        }
    }
    
    func refreshAll(_ reloadThumbType: [FileType] = [], dryRun: Bool = false, needStopAutoScroll: Bool = true, needLoadThumbPriority: Bool){
        refreshTreeView()
        refreshCollectionView(reloadThumbType, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll, needLoadThumbPriority: needLoadThumbPriority)
    }
    
    func refreshCollectionView(_ reloadThumbType: [FileType] = [], dryRun: Bool = false, needStopAutoScroll: Bool = true, needLoadThumbPriority: Bool){
        fileDB.lock()
        let curFolder = fileDB.curFolder
        if let files = fileDB.db[SortKeyDir(curFolder)]?.files {
            for file in files {
                if reloadThumbType.contains(file.1.type) || reloadThumbType.contains(.all) {
                    file.1.originalSize=nil
                    file.1.thumbSize=nil
                    file.1.image=nil
                    file.1.folderImages=[]
                }
            }
        }
        fileDB.unlock()
        switchDirByDirection(direction: .zero, doCollapse: false, skip: dryRun, stackDeep: 0, dryRun: dryRun, needStopAutoScroll: needStopAutoScroll)
        
        if needLoadThumbPriority {
            DispatchQueue.main.async { [weak self] in
                self?.setLoadThumbPriority(ifNeedVisable: true)
            }
        }
    }
    
    func refreshTreeView() {
        var expanded = Set<String>()
        let selectedID = (outlineView.item(atRow: outlineView.selectedRow) as? TreeNode)?.stableID
        func capture(_ node: TreeNode) {
            if outlineView.isItemExpanded(node) { expanded.insert(node.stableID) }
            for child in node.children ?? [] { capture(child) }
        }
        for node in treeViewData.root?.children ?? [] { capture(node) }
        let previousAction = outlineViewManager.ifActWhenSelected
        outlineViewManager.ifActWhenSelected = false
        defer { outlineViewManager.ifActWhenSelected = previousAction }
        treeViewData.rebuildSidebar()
        func refresh(_ node: TreeNode) {
            if expanded.contains(node.stableID), node.role != .group {
                treeViewData.expand(node: node, isLookSub: true)
            }
            for child in node.children ?? [] { refresh(child) }
        }
        for node in treeViewData.root?.children ?? [] { refresh(node) }
        outlineView.reloadData()
        expandSidebarGroups()
        func restore(_ node: TreeNode) {
            if expanded.contains(node.stableID) { outlineView.expandItem(node) }
            if node.stableID == selectedID {
                let row = outlineView.row(forItem: node)
                if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
            for child in node.children ?? [] { restore(child) }
        }
        outlineView.deselectAll(nil)
        for node in treeViewData.root?.children ?? [] { restore(node) }
        fileDB.lock()
        let curFolder = fileDB.curFolder
        fileDB.unlock()
        if globalVar.dirTreeAutoExpand { treeReLocate(path: curFolder, doCollapse: false, expandLast: false) }
        outlineViewManager.adjustColumnWidth()
    }
}
