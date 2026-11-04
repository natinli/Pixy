# 修改指南与 fork 维护

## 代码组织约定（观察自上游）

- **巨型 ViewController + extension 分文件**：ViewController.swift 本体只放核心状态与线程管理；功能实现放 `ViewControllerExtension/` 对应 extension。**新功能优先新建 extension 文件**，不往本体堆。
- **AppKit 命名**：自定义类以 `Custom` 前缀（CustomCollectionView、CustomImageView…）；布局类例外（WaterfallLayout、CustomFlowLayout）。
- 并发以 GCD/OperationQueue/常驻 Thread 为主；新增后台任务优先接入既有 `TaskPool`，不自起线程。
- 设置项直接读写 `globalVar`（进程级）或 `publicVar`（每窗口），配合 UserDefaults 持久化；不自造单例。
- View 反查 ViewController 统一用 `getViewController()`，不要传引用穿透。

## 常见改动落点

| 想改什么 | 去哪里 |
|---|---|
| 新增菜单项/快捷键 | `WindowController.showMoreMenu`（菜单）+ `KeyShortcut.swift`（按键）+ `EventHandler.swift`（动作实现） |
| 新增/调整排序方式 | `Enum.swift` SortType + `DataModel.swift` SortKey `<` 运算符（唯一真源，影响全项目） |
| 布局算法 | `LayoutManagement.recalcLayout`（尺寸计算）+ `Layout.swift` 对应布局类（摆放） |
| 缩略图渲染/单元格外观 | `CustomCollectionViewItem.configureWithImage` |
| 大图行为 | `LargeImage.swift`（打开/切换/预载）+ `LargeImageView.swift`（交互/渲染） |
| 视频播放 | `LargeImageView.swift`（播放控制）+ `VideoPlayerControlsView.swift`（控制条）+ `VideoProcess.swift`（合成辅助） |
| 文件操作 | `FileOperation.swift`；操作后记得同步 `EnhancedIndex`（标签索引） |
| 搜索/过滤 | `Search.swift`；过滤条件由 `treeTraversal` 在扫描时应用 |
| 手势 | `ViewController._rightMouse*`（轨迹采集）+ `RightMouseGesture.analyzeGesture`（判定）+ `switchDirByDirection`（执行） |
| 新设置项 | `GlobalVariable.swift` globalVar + 对应 `SettingsViews/` 面板 |
| 目录扫描逻辑 | `FileSystem.swift treeTraversal`（注意递归方向与过滤链） |
| 缓存策略 | `ImageProcess.swift` LargeImageProcessor / ThumbImageProcessor / CustomCache |

## 修改后必做

1. **同步文档**：`docs/dev/modules.md` 对应文件章节；影响架构时 `docs/dev/architecture.md`；用户可见功能 `docs/user/usage.md`；版本变更 `CHANGELOG.md`。维护规则见 [index.md](../index.md)。
2. 构建 + 冒烟：打开目录、切四种视图、进出大图、缩放、视频、标签过滤（有 Xcode 环境时）。
3. 在 `docs/session-log.md` 记录本次改动。

## fork 上游同步策略

remote 布置：

```
origin   = https://github.com/natinli/Pixy.git    # 日常推送
upstream = https://github.com/netdcy/FlowVision.git     # 只 fetch，不 push
```

同步上游新版本：

```bash
git fetch upstream
git merge upstream/main        # 或 rebase，视本地分叉程度
```

分叉点与冲突预期：

- 根 `README.md` / `README_zh.md` 已完全重写 → **必然冲突**，保留本仓库版本，把上游新增的功能点合并进 `docs/user/usage.md` 与 CHANGELOG。
- `docs/` 下新增的子目录（user/、dev/、index.md、session-log.md）上游不存在 → 一般无冲突；上游 `docs/` 内的预览图变更直接接受。
- `CLAUDE.md`、`CHANGELOG.md`、`.github/workflows/` 为本仓库新增 → 无冲突。
- 源码已不是「只改文档」的分叉。Pixy 相对上游 `1.7.6` 的实质改动集中在下列文件，合并上游时需逐处人工确认：

| 文件 | 改动性质 |
|---|---|
| `Common/DataModel.swift` | 侧栏数据模型：`TreeViewModel`/`TreeNode`/`SidebarNodeRole`、`rebuildSidebar`、`sidebarCandidates` |
| `ViewControllerExtension/DirTree.swift` | 目录跟随与侧栏定位重写（`treeReLocate`） |
| `Views/CustomOutlineViewManager.swift`、`CustomOutlineView.swift` | 侧栏渲染：分组、行高、选中态、OneDrive 图标、推出按钮 |
| `ViewController+SidebarCard.swift`（新增） | 两段式布局：圆角裁剪、共享材质、工具栏避让 |
| `WindowController+ToolbarBlend.swift`（新增） | 大图模式透明标题栏与底部标题胶囊 |
| `ViewControllerExtension/LayoutManagement.swift` | 侧栏刷新与展开状态保存 |
| `WindowController.swift`、`ViewController.swift` | 装配新扩展、工具栏与菜单入口调整 |
| `ViewControllerExtension/EventHandler.swift`、`KeyShortcut.swift`、`FileSystem.swift`、`LargeImage.swift`、`Views/CustomSplitView.swift` | 侧栏导航、快捷键跳过分组行、进入子目录清除选中态、大图融合联动 |
| `Resources/Localizable.xcstrings`、`mul.lproj/Main.xcstrings` | 中文化与文案 |

其余上游文件保持原样。**新增定制优先新建 extension 文件**（如 `ViewController+SidebarCard.swift`），减少与上游同区域的冲突面。

上游发布新版本后：更新 `CHANGELOG.md`（翻译整理上游 release notes），必要时更新 `docs/dev/modules.md` 中受影响文件；上表文件是合并时的重点核对对象。

## 提交约定

- 提交信息用中文，一句话说清改动目的（与 nilo 仓库风格一致）：`docs: xxx` / `fix: xxx` / `feat: xxx`。
- 文档与源码改动分开提交，便于 cherry-pick 回上游时拆分。

## GitHub 仓库设置

公开前的收尾项，记录在此以免以后被无意改回去：

| 设置 | 状态 | 理由 |
|---|---|---|
| Wiki | 关 | 文档全在 `docs/`，wiki 是空入口，且与仓库内容容易分叉 |
| Projects | 关 | 没用它排期 |
| Discussions | 开 | 0 issue 的仓库，讨论区比 issue 门槛低；用默认分类 |
| Homepage | 留空 | 原先填的是仓库地址本身，侧栏重复显示同一个链接 |
| 合入后删除源分支 | 开 | 单人仓库，分支留着只会堆积 |
| PR 分支允许更新 | 开 | 外部提 PR 时一键跟上 `main` |
| Secret scanning + push protection | 开 | 公开仓库免费，配合 `scripts/check-public-hygiene.sh` 双重兜底 |
| Dependabot 安全更新 | 开 | `Package.resolved` 里的 SPM 依赖有漏洞时自动提 PR |
| Social preview | **需手动上传** | GitHub 无 API，仓库 Settings → Social preview 传 `docs/social-preview.png` |

`secret_scanning_validity_checks` 仍是关闭状态——个人账号仓库上开不了，不影响上面两项。
