// MARK: - 侧栏路径定位与刷新
import Cocoa

extension ViewController {
    func expandSidebarGroups() {
        for group in treeViewData.root?.children ?? [] { outlineView.expandItem(group) }
    }

    func treeReLocate(path: String, doCollapse: Bool, expandLast: Bool) {
        guard let target = TreeViewModel.normalizedURL(path) else { return }
        let groups = treeViewData.root?.children ?? []
        let candidates = treeViewData.sidebarCandidates(for: target)
        let previousAction = outlineViewManager.ifActWhenSelected
        outlineViewManager.ifActWhenSelected = false
        let previousDeepInspection = outlineViewManager.suppressDeepChildInspection
        outlineViewManager.suppressDeepChildInspection = true
        let previousRelocationTarget = treeViewData.sidebarRelocationTarget
        treeViewData.sidebarRelocationTarget = target
        defer {
            outlineViewManager.ifActWhenSelected = previousAction
            outlineViewManager.suppressDeepChildInspection = previousDeepInspection
            treeViewData.sidebarRelocationTarget = previousRelocationTarget
        }
        guard let (group, entry) = candidates.first else { outlineView.deselectAll(nil); return }
        outlineView.expandItem(group)
        var node = entry
        var ancestors = Set<String>()
        while let url = TreeViewModel.normalizedURL(node.fullPath), url.path != target.path {
            ancestors.insert(node.stableID)
            outlineView.expandItem(node)
            guard let next = node.children?.first(where: {
                guard let childURL = TreeViewModel.normalizedURL($0.fullPath) else { return false }
                return TreeViewModel.contains(childURL, target)
            }) else { outlineView.deselectAll(nil); return }
            node = next
        }
        if expandLast { ancestors.insert(node.stableID); outlineView.expandItem(node) }
        if doCollapse || treeViewData.activeSidebarEntryID == nil {
            func collapseUnrelated(_ item: TreeNode) {
                if item.role == .group {
                    for child in item.children ?? [] { collapseUnrelated(child) }
                } else if !ancestors.contains(item.stableID) {
                    outlineView.collapseItem(item, collapseChildren: true)
                } else {
                    for child in item.children ?? [] { collapseUnrelated(child) }
                }
            }
            for group in groups { collapseUnrelated(group) }
        }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { outlineView.deselectAll(nil); return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        // 启动阶段程序定位不建立用户分支，避免临时根目录污染后续排名。
        if treeViewData.activeSidebarEntryID != nil {
            treeViewData.activeSidebarEntryID = entry.entryID
        }
    }

    @objc func sidebarFavoritesDidChange(_ notification: Notification) {
        refreshTreeView()
    }
}
