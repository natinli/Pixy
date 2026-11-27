# 模块详解

> 逐目录逐文件的一句话职责 + 关键接口。行数截至 2026-11 整理时（当前共 60 个 Swift 文件）。查找文件用 ⌘F；模块间关系见 [architecture.md](architecture.md)。

## 根级（6 文件）

### AppDelegate.swift（1281 行）
应用生命周期入口。
- `applicationWillFinishLaunching` — 菜单初始化、设置面板注册、globalVar 默认值
- `createNewWindow(_:useCreateWindowShowDelay:isLaunchFromFile:urlsToSelect:)` — 创建 WindowController，携带跨窗口启动临时状态
- `application(_:openFiles:)` — Finder 双击入口：目录打开 or 文件大图打开
- `openImageInMainWindow` / `openImageInTargetWindow` — 写 `publicVar.openFromFinderPath` 触发定位
- `menuNeedsUpdate` / `validateMenuItem` — 主菜单动态构建
- `isCheckingForUpdates` / `validateMenuItem` — 「检查更新…」进行中的标志（主线程读写）；`validateMenuItem` 在**没有窗口时**也让这个菜单项可用（其余项此时一律置灰），检查进行中置灰
- `showQuickSearch` — 编辑菜单「快速搜索（Q）」入口，转发 `ViewController.startQuickSearch()`；菜单项不注册无修饰键的 key equivalent（避免抢走文本框里的 q），`validateMenuItem` 在大图模式或搜索浮层打开时置灰

### WindowController.swift（2052 行）
单窗口壳。
- `toolbar(_:itemForItemIdentifier:)` — 全部工具栏项构建，action 转发 ViewController
- `getItemIdentifiers` — 地址区域前置固定间距，与导航按钮保持留白
- `showMoreMenu` — 「更多」巨型菜单（HDR、锁定、RAW 内嵌缩略图、便携/递归模式等约 80 项）
- `saveWindowState` / `windowWillClose` — frame、lastFolder 持久化 → `viewController.prepareForDeinit()`
- `windowWillEnterFullScreen/DidEnter/DidExit` — 黑底、工具栏/光标隐藏联动

### ViewController.swift（2479 行）
核心中枢，文件内含三个类：
- `CustomProfile: Codable` — 布局外观配置（layoutType、thumbSize、CellPadding 等派生属性）；UserDefaults key `"CustomStyle_v2_current"`
- `PublicVar` — 每窗口状态：视图模式、过滤、folderStepStack 历史栈、isInLargeView、三个布局实例、`setFileExtensions()`；`scrollAnchor` 为缩放缩略图前捕获的浏览位置锚点（类型 `ScrollAnchor` 定义在 LayoutManagement.swift），`lastZoomAnchorFile`、`resizeScrollAnchor`（窗口 / 侧栏宽度变化时的锚点）（weak）为上一次缩放恢复到的锚点文件
- `ViewController`：
  - `viewDidLoad` — 装配 manager 们、读 UserDefaults、按 profile 选布局、注册 7 类 NSEvent monitor
  - `startBackgroundTaskThread` — 启动三条常驻线程（readInfo / thumb / memMonitor）
  - `setLoadThumbPriority` — 滚动时按可见中心距离重排加载队列
  - `startWatchingDirectory` / `scheduledRefresh` — 目录监听 + 防抖刷新
  - `_rightMouseDown/Dragged/Up` — 手势轨迹采集（增量式，阈值 4px）
  - `afterFinishLoad` — 决定启动目录 → 启动后台线程
  - readInfo 主循环回到主线程后：≤5000 文件保持位置路径在最后一次 `reloadData` 后调用 `restoreScrollAnchorIfReady`；清空重插路径（>5000）只在最后一批 `insertItems` 之后、下一个 runloop 调用（插入中途强制布局并滚动会让网格空白，见 session-log 2026-11-17）

### AppDelegate+UpdateCheck.swift
应用菜单「检查更新…」（Pixy 菜单，「关于 Pixy」之后）的动作与结果界面。
- `checkForUpdates(_:)` — 仅在用户点击时调用：标志 `isCheckingForUpdates` 置位（防叠加：进行中菜单项置灰，动作入口再兜底一次，所以不会有第二个请求或第二个对话框）→ `UpdateChecker.check` 在后台发**一个**请求 → 回主线程 `presentUpdateCheckResult`，**对话框关闭后**才复位标志（对话框 `runModal` 期间动作被再次触发也会被忽略）。不在 `applicationDidFinishLaunching`、定时器、窗口激活等任何地方被调用。
- `presentUpdateCheckResult` — 三种 `NSAlert`：有新版（标题含新版本号；正文含当前版本、`brew upgrade --cask pixy` 与「也可从发布页下载」；按钮顺序 打开发布页〔默认〕/ 复制命令〔写通用剪贴板〕/ 好〔Esc〕）、已是最新（标题「没有可用更新」类，正文含当前版本号）、失败（离线 / 超时 / 非 200 / 响应异常 / 链接不可信统一一条「无法检查更新，请检查网络后稍后重试」；具体原因只进应用内日志）。对话框期间与其它 `showInformation` 一样暂停主窗口键盘事件。
- 文案：`update-*` 标识符 key（`value:` 带英文回退，`Localizable.xcstrings` 补齐 17 种语言），菜单标题在 `mul.lproj/Main.xcstrings`（`cfu-Mn-It1.title`）；按钮「好」复用已有的 `OK`。

### ViewController+SidebarCard.swift
- `applySidebarCardStyle` — 目录树与 scroll/clip 背景透明，共享窗口背后动态 sidebar 材质，目录顶部根据 window.contentLayoutRect 避让工具栏，再保留 15pt 内容间距；关闭横纵滚动条，保留滚动容器。
- `applyContentCardStyle` — 侧边栏和内容圆角外侧共享 behindWindow/sidebar 材质，背景位于 NSSplitView 同级，不参与分栏布局；内容面采用 leading 侧 8pt 填充圆角，并让主滚动区避开透明标题栏下方的工具栏保护带。
- `updateContentToolbarInsets` — 按内容面板与 `window.contentLayoutRect` 的几何关系重设主滚动区高度，确保滚动内容不穿过工具栏。
- `updateContentCornerMask` — 按内容面板尺寸更新整层裁剪，覆盖 scroll/clip/collection 的绘制；支持 RTL，布局时同步更新。

### WindowController+ToolbarBlend.swift（133 行）
大图模式的标题栏透明融合与底部标题胶囊。
- `enableToolbarBlend` — 进入大图模式：`titlebarAppearsTransparent` + `fullSizeContentView`，内容延伸到标题栏后方，工具栏浮在毛玻璃上，并调起底部标题条。
- `disableToolbarBlend` — 退出大图模式：保持两段式结构（透明标题栏），只隐藏底部标题胶囊。
- `setupBottomTitleBar` / `makeBottomTitleBar` — 在内容区底部中央生成「文件名 · 张数」胶囊，张数做弱化处理，浮在毛玻璃上。

## Common/（14 文件）

### DataModel.swift（1301 行）
核心数据结构，全部基于 BTree 有序 Map。
- `SortKey/SortKeyFile/SortKeyDir` — Comparable 排序键；`<` 是**全项目排序唯一真源**（path/日期/size/exif/rating/tag + SortType/folderFirst/randomSeed）；`writeExifInfo`/`writeTagInfo` 惰性加载
- `FileModel` — 单文件：path/ext/type/image/thumbSize/originalSize/rotate/finderTags/lock/ver
- `DirModel` — `files: Map<SortKeyFile,FileModel>` + layoutCalcPos（增量布局游标）+ keepScrollPos；`changeSortType` 重建排序
- `DatabaseModel` — `db: Map<SortKeyDir,DirModel>` + curFolder + `ver`（版本号，使旧任务失效）
- `TreeViewModel`/`TreeNode` — Finder 风格侧栏分组与目录树数据；`SidebarNodeRole` 隔离分组、目录、卷、标签、文件、特殊入口及分隔线，`entryID` + 规范路径组成节点身份；`rebuildSidebar` 是初建与刷新的共同入口，构建精简的个人收藏、iCloud、位置和标签四组，并过滤系统虚拟入口与 TimeMachine；`sidebarCandidates` 负责虚拟域隔离和入口排名，`activeSidebarEntryID` 由用户选择／展开建立，随后成功程序定位更新当前分支。
  - `SidebarNaming`（无状态，便于单测）— 位置分组的命名与排序规则：`oneDriveEntries` 枚举 `~/Library/CloudStorage` 下名为 `OneDrive` 或 `OneDrive-<账号>` 的目录（账号后缀随系统语言变化，所以不做后缀识别，只用数量决定显示名：仅一个叫「OneDrive」，多个时带后缀的叫「OneDrive - <后缀>」）；`volumeRank` 让磁盘排在云存储前、同档按名称自然排序，不特判任何具体卷名；`spacedComputerName` 只在「的」紧邻 ASCII 字母数字时补空格，其余电脑名原样显示。
  - 侧栏文案：分组标题与 iCloud 云盘、「所有标签」走 `sidebar-*` key，`NSLocalizedString(key, value: <英文>, comment:)` 带英文回退（`specialEntry` 的 `fallback` 参数同理），`Localizable.xcstrings` 里 6 个在用 key 补齐 17 种语言、沿用 Finder 侧栏用词（如德文「Favoriten / Orte / Tags」）；已无调用的 `sidebar-airdrop/recents/shared` 已删除。`scripts/check-localization.py`（CI `ci.yml` 里跑）强制：标识符式 key 必须存在于 xcstrings，且语言齐全或调用处带 `value:`。
- `normalizedURL`/`isVirtualTagURL`/`contains` — 统一文件 URL 规范化与路径组件祖先关系；不按显示名称定位、不解析符号链接改变路径语义；虚拟标签域隔离真实目录候选和文件操作。
- `TaskPool` — 多队列优先级任务池（makeQueue/push/pop/setMostPriority）

### ImageProcess.swift（2774 行）
图像工具全集（最重工具文件）。
- `getImageInfo(url:needMetadata:)` — ImageIO 尺寸/EXIF orientation/HDR 判定/XMP Rating；视频走 AVAsset/FFmpeg 兜底
- `getImageThumb(url:size:refSize:isPreferInternalThumb:)` — 万能缩略图入口：目录→拼贴；视频→多时间点选最亮帧；RAW→内嵌 EXIF 缩略图；普通图→CGImageSource 512px
- `getResizedImage` — CGContext 高质量缩放（EXIF orientation/索引色/alpha 兼容），失败回退 CILanczosScaleTransform
- `writeRating` — XMP 评级写入：只重写元数据段（无损）+ 同卷原子替换 + 255 字节文件名截断
- `createCompositeImage` — 目录缩略图拼贴（叠放/平铺两种）
- `LargeImageProcessor` — 大图缓存：LRU 16、key 含 ver、**nil 也缓存**、信号量去重、`needWaitWhenSame=false` 预载不阻塞
- `ThumbImageProcessor` — 缩略图版同构缓存
- `CustomCache<K,V>` — 自实现 LRU（字典+访问序数组+NSLock）

### GlobalVariable.swift
三层组织：顶层 let 常量（DEFAULT_SIZE、预载范围 20/40、阈值）→ `globalVar` 单例（扩展名白名单 init 硬编码、设置项、跨窗口启动状态、剪切模式）→ 自由函数（`getViewController()` responder 链上溯是 View 反查 VC 的通用手段）。

`myFavoritesArray` 保留原存储格式，所有写入口通过 didSet 在主线程发出 `favoritesDidChange`；窗口订阅并在关闭清理中解除通知，侧栏只读取该状态。

### FinderTag.swift（885 行）
- `FinderTag` struct + `FinderTagDotsView`（可点击圆点）
- `FinderTagHelper` — 读写标签（NSMetadataQuery / xattr）
- `EnhancedIndex` — 自建标签索引：递归扫描建索引、增量更新、反查、移动/删除维护、延迟落盘

### 其他
| 文件 | 职责 |
|---|---|
| Common.swift（961） | Atomic 包装器、MyTimer 节流、showAlert 系列、VolumeManager（外置卷检测）、拼音转换、AppleScript 显示文件 |
| FFmpegKit.swift（192） | `FFmpegKitWrapper.shared` dlopen 懒加载 xcframework，未加载时静默降级 |
| VideoProcess.swift（86） | NoHitAVPlayerView（不挡手势）、AB 循环音视频合成辅助 |
| Log.swift（348） | 全局 log() + 日志查看窗口；**仅 Debug 构建**：环境变量 `PIXY_LOG_FILE` 非空时，`Logger.init` 清空（或新建）该文件、把 `logFileURL` 指向它并开启 `isFileLoggingEnabled`，之后每条日志追加一行（`时间戳 [级别] [函数] 内容`），供 `scripts/bench/run.sh` 解析 `Time taken to …` 计时行。不设置时行为不变（日志不写文件，`isFileLoggingEnabled` 默认 false，原有的 `Application Support/Pixy/Pixy.log` 路径逻辑原样保留）；这段代码在 `#if DEBUG` 里，Release 产物里没有这个字符串（`strings` 实测 0 处，Debug 的代码在 `PixyDbg.debug.dylib` 里恰 1 处） |
| Enum.swift（32） | FileType / 手势方向 / LayoutType(justified,waterfall,grid,detail) / SortType（21 种）/ 设置页注册 |
| TempVariable.swift（13） | 编译期开关：`EDIT_FEATURE_ENABLED=false`、SDK_VERSION |
| RefCode.swift（38） | FSEvents 参考实现，未接入主链路（主链路用 DispatchSourceFileSystemObject） |
| AccessibilityLabels.swift | 辅助功能标签的纯函数（无 AppKit 依赖，便于单测）：`kind(isDirectory:type:)` 把 `FileModel` 的 `isDir` / `type` 归成文件夹 / 图像 / 视频 / 其它；`typeWord` 取 `Folder`/`Image`/`Video`/`Other` 这批已有本地化 key（与 `setWindowTitle` 统计文案同源，不新增文案）；`thumbnail(name:kind:)` 与 `largeImage(name:kind:)` 返回「文件名, 类型词」（文件名原样保留、不截断，空名或全空白只返回类型词）；`sidebar(name:role:isAllTagsEntry:)` 按 `SidebarNodeRole`：分隔线 / 根节点返回 nil，标签条目追加「标签」（名称为空时只有「标签」；「所有标签…」入口 `isAllTagsEntry` 为真时只用名称，调用方按 `fullPath == "file:///VirtualFinderTagsFolder/"` 判断——不能用 `entryID`，颜色标签也是 "tags"；也不能用 `fileURL`，标签节点恒为 nil），其余条目只用名称、空名返回 nil（卷没有合适的已有类型词，`Volume` 在中文里是「音量」）。接入点：`CustomCollectionViewItem.configureWithImage`、`CustomOutlineViewManager` 的 `viewFor`、`LargeImageView.file` 的 `didSet` |
| UpdateChecker.swift | 「检查更新…」的版本比较、请求与响应解析（只 import Foundation）。**全工程唯一出现 `URLSession` / `URLRequest` 的文件**，也是应用唯一的联网点：只在用户点菜单时被调用，没有启动 / 定时 / 后台检查，没有自动更新。`SemanticVersion`：解析 `v0.0.6` / `0.0.6` / `1.2`（缺的补 0）/ `0.0.7-rc1` / `0.0.6+2026112601`，`+元数据`（含应用 build 号 YYYYMMDDNN）解析后丢弃、不参与比较，4 段以上 / 空串 / 非数字 / 负号 / 空白 / 前导尾随垃圾返回 nil，预发布后缀按 semver 优先级比较且低于同号正式版。`parseLatestRelease` 取 `tag_name`（须能解析）与 `html_url`；空数据、超过 `maxResponseBytes`（1 MiB）、非 JSON 对象、缺字段 / 类型不对、`draft` / `prerelease` 为 true 都算失败；`html_url` 必须是 `https://github.com`（无账号、无端口）才算可信（`isTrustedReleaseURL`），否则 `.untrustedReleaseURL`，防止被篡改的响应诱导「打开发布页」去任意地址。`makeRequest`：**单次 GET** `api.github.com/repos/natinli/Pixy/releases/latest`，请求头只设 `Accept: application/vnd.github+json` 与 `User-Agent: Pixy/<主.次.修订>`（实测线上还有系统网络层自动加的 `Host`、`Accept-Encoding`、`Accept-Language`、`Connection`，不含 cookie / 鉴权 / build 号 / 任何用户标识），`timeoutInterval = 10`，无 query / body。`makeSessionConfiguration`：`ephemeral`，cookie / 凭据 / 缓存存储全置 nil，`reloadIgnoringLocalCacheData`，请求超时 10 秒、总时长 20 秒、`waitsForConnectivity = false`（离线立即失败）。`check(currentVersion:endpoint:allowLoopbackReleaseURL:session:completion:)`：当前版本读不出来就不发请求直接 `.failed(.invalidCurrentVersion)`；否则发一个请求、无重试，结果 `UpdateCheckResult`（`.upToDate` 含当前版本 ≥ 最新、`.updateAvailable(current:latest:releaseURL:)`、`.failed(UpdateCheckFailure)`），回调在后台队列，`session` 由本次检查接管（发出后 `finishTasksAndInvalidate`，每次传新会话）；`URLSession` 注入使 `URLProtocol` 桩测试成为可能。**仅 `#if DEBUG`**：环境变量 `PIXY_UPDATE_URL` 覆盖请求地址并放宽 `html_url` 校验到 127.0.0.1 / localhost（见 [build.md](build.md#检查更新的本机验证)）；这段代码与字符串编译不进 Release（`strings` 实测 0 处）。接入点：`AppDelegate+UpdateCheck.swift`；`PixyTests/UpdateCheckerTests.swift`（41 个用例）覆盖版本解析 / 比较、响应解析与链接校验、请求构造与会话配置、桩网络下的各条路径并断言一次检查恰好 1 个请求 |
| ScrollAnchorMath.swift | 浏览位置锚点里不依赖 AppKit 的纯数学（只 import Foundation + CoreGraphics，便于用合成布局做模型测试）：`pickAnchor(selected:sticky:visibleRect:frameOf:visibleCandidates:)` 决定「选哪一项当锚点」，顺序为 在顶部（`visibleRect.minY <= 0.5`）返回 nil（只保留选中）→ 可视区内第一个选中项（调用方传升序）→ 仍与可视区相交的 sticky 项（即 `PublicVar.lastZoomAnchorFile`，身份校验由调用方做）→ 顶部项（中点不低于可视区顶边的项里 `minY` 最小、并列取 index 小的；一个都没有就退回最靠上的相交项）；高度 ≤ 0 的 frame 一律忽略，`frameOf` 取不到 frame（含越界）的项忽略。`frameOf` / `visibleCandidates` 用闭包而不是数组，是为了与原实现保持同样的惰性：命中选中项或 sticky 后不会再去问布局可视区里有哪些项，也不会为整个选中集合取 frame。`targetScrollTop(anchorMinY:anchorHeight:offsetInViewport:oldViewportHeight:newViewportHeight:contentHeight:insetTop:)` 算视口要滚到的 y（已减 `insetTop`）：可视区高度变化超过 0.5 时偏移按比例缩放 → 夹到 `[0, 新可视区高度 − 锚点高度]` → 目标顶边夹到 `[0, max(0, 内容高度 − 新可视区高度)]`。接入点：`LayoutManagement.swift` 的 `makeScrollAnchor`、`applyAnchorScroll`（AppKit 层只负责取 frame / 可视区、调用、滚动）；`PixyTests/ScrollAnchorMathTests.swift` 用合成布局（`SyntheticLayout`）与最小滚动视图模型（`SyntheticViewport`）测 |

## ViewControllerExtension/（16 文件，全是 ViewController extension）

### FileSystem.swift（1812 行）— 扫描与导航核心
- `treeTraversal(folderURL:round:initURL:direction:sameLevel:skip:dryRun:)` — 递归扫描：过滤隐藏/搜索/标签/评级 → 分离 subFolders/files → 写 DirModel；按 direction 前序/后序递归
- `switchDirByDirection(direction:dest:...)` — 导航状态机：zero/left/right/up/down/forward；维护历史栈；`fileDB.ver+=1`；定位 → treeReLocate + switchFolder；内容区进入新目录后清除侧栏选中态，侧栏入口发起的导航保留选中。
- `switchFolder(path:)` — 清任务池、快照渐隐动画、处理 Finder 打开定位、文件推入 readInfoTaskPool；推任务前 `bindScrollAnchorToLoad` 把缩放锚点绑定到本轮加载（换目录或又一轮加载则作废）
- `scanFiles` / `scanVirtualFiles` — 递归模式枚举 / 按标签聚合的虚拟目录
- `handleGetInfo` 系列 — 文件信息窗口数据组装

### LayoutManagement.swift — 布局计算唯一真源
- `refreshTreeView` 按稳定节点身份保存、刷新和恢复用户手动展开／选中状态；与初建共享 `rebuildSidebar`，保持原目录排序。默认导航不自动展开当前路径，目录仍可通过披露箭头按需展开。
- `recalcLayout(targetFolder)` — 增量计算（从 layoutCalcPos 起）：justified 宽高比凑行 / waterfall·grid 固定列宽 → 写 FileModel.thumbSize/lineNo
- `switchToJustifiedView/GridView/WaterfallView/DetailView`、`changeThumbSize`、`refreshAll`
- 缩放锚定（`ScrollAnchor`）：`changeThumbSize` 是所有缩放入口（`+`/`-`/`0`、工具栏尺寸菜单、布局配置切换）的汇合点，改尺寸前 `captureScrollAnchor` 记下锚点——可视区内第一个选中项，否则顶部第一个至少露出一半的项（「选谁」由 `makeScrollAnchor` 调用纯函数 `ScrollAnchorMath.pickAnchor` 决定，「滚到哪」由 `applyAnchorScroll` 调用 `ScrollAnchorMath.targetScrollTop` 计算，两者的取舍规则与测试见 `Common/ScrollAnchorMath.swift` 一行；`makeScrollAnchor` / `applyAnchorScroll` 本身只剩取 frame、查 `fileDB`、滚动与 `invalidateLayout`）；记录 FileModel 身份、路径、距可视区顶边的偏移（扣除 contentInsets）和缩放前选中项；原本在顶部则不锚定视口。连续缩放时沿用尚未恢复的旧锚点；上一次恢复到的锚点文件（`PublicVar.lastZoomAnchorFile`，weak）仍在可视区内时继续锚定它，否则每次重选顶部行首会让连续缩放逐行往前漂。已知取舍：缩放后手动滚动、而该文件仍在可视区内时，下一次缩放仍锚定它（它保持在屏幕原位），而不是改锚顶部那张。`restoreScrollAnchorIfReady` 按文件身份（`files.elementSafe(atOffset: file.id)?.1 === file`，失败按路径兜底）找回 index，布局就绪后无动画滚到 `frame.minY - offset`（夹到合法范围），并选回原选中项；只恢复一次，本轮加载结束仍无法恢复则丢弃。同一套锚点也用于目录监听刷新：`scheduledRefresh` 在 `refreshAll` 前调用 `captureScrollAnchor`，不分目录大小都捕获（>5000 的目录刷新走清空重插，视图会回到顶部，上游 #120；≤5000 的目录 `reloadData` 只保留像素偏移，新文件插在可视区上方时内容会被整体挤下去，实测新增 6 个文件后顶部漂了一行）。锚点的捕获入口一共有：缩放（`changeThumbSize`）、切换布局（`switchToJustifiedView` / `switchToGridView` / `switchToWaterfallView`，仅 `doNotRefresh == false` 时捕获，避免没有后续刷新时留下悬空锚点）、「配置样式」切换（`useCustomProfile` 开头捕获一次，其后各步都是 `doNotRefresh`）、显示隐藏文件 / 所有类型 / 图片 / RAW / 视频的切换（可见集合会变，不分目录大小都捕获；锚点文件若被过滤掉则放弃恢复）、手动刷新 `handleUserRefresh`（`captureScrollAnchorForRefresh`，仅 ≥ `RESET_VIEW_FILE_NUM_THRESHOLD` 的大目录：内容没变，小目录像素偏移本来就对）。切换布局会改变像素与内容的对应关系，≤5000 的目录也会丢位置，所以这几处不做阈值判断。窗口 / 侧栏宽度变化走另一条同步路径：`splitViewDidResizeSubviews` 在一次宽度变化的第一次回调（布局缓存还没被改动）用 `makeScrollAnchor` 记下 `PublicVar.resizeScrollAnchor`，`splitViewSizeChanged` 重算布局后由 `restoreScrollAnchorAfterResize` 同步滚回（不涉及目录重载，不改选中），宽度没变则丢弃；恢复到的文件同样写入 `lastZoomAnchorFile`，反复收起/展开侧栏不会一行行漂移。鼠标拖分隔条（0.1 秒防抖）与菜单切换（立即）两条分支都走这里

### 其他 extension
| 文件 | 职责 / 关键接口 |
|---|---|
| LargeImage.swift（1052） | `openLargeImage`（双击入口，目录/替身/图片分派）、`changeLargeImage`（预载+异步可取消）、`preloadLargeImage`（前后 2~3 张） |
| FileOperation.swift（1767） | handleCopy/Paste/Move/Delete/Rename（批量面板）、`DeleteConfirmPolicy`（删除前是否弹确认的纯函数：设置「删除时不再询问」只免掉普通的移到废纸篓确认，Shift 永久删除、外置卷无废纸篓、无自动化权限三种情况照常询问）、mergeFolder 冲突状态机、handleFilePromiseDrop（Finder 拖入）、操作后同步 EnhancedIndex |
| KeyShortcut.swift（996） | `KeyShortcutManager(event:)` 单函数全快捷键分发，含输入焦点判断；目录上下键通过可选行扫描跨越分组、分隔线及失效入口 |
| EventHandler.swift（441） | 菜单动作实现层：历史导航、约 25 个 toggle、前往文件夹、操作日志 |
| Search.swift | showSearchOverlay、performSearch（正则/拼音/全路径）、applyFilter（过滤条件由 treeTraversal 应用）、quickSearch 防抖：空输入时浮层提示「输入文件名 · Esc 退出」，前缀与包含两次匹配都失败时显示「无匹配」；`startQuickSearch` 为菜单入口，等同按 Q |
| ArrowKeyLocate.swift（280） | `findClosestItem` 方向键导航：grid 列偏移 / waterfall 4×列数邻域 / justified 同行，选屏幕中心最近 |
| Tagging.swift（262） | 标签/评级动作与过滤器（与/或、反向）；依赖 FinderTag.swift |
| RightMouseGesture.swift（135） | `analyzeGesture` 方向组合→动作：1 方向（左右上下）、2 方向（up+right=平级下一个、down+right=关闭）；RTL 左右互换 |
| WindowManagement.swift（417） | maximize/suitable/portable 窗口尺寸系列 |
| MemoryManagement.swift（87） | LRUMemRecord（目录访问 LRU）、内存 footprint 报告 |
| AutoScrollPlay.swift（149） | 自动滚动（Timer 连续滚动）与自动播放（定时 nextLargeImage） |
| DirTree.swift | `treeReLocate` 按真实 URL 选择当前入口／最深收藏祖先／位置；开启跟随当前目录时才逐级展开，默认只选中目标；`expandSidebarGroups` 和收藏变更通知入口 |
| LayoutProfileConfig.swift | 自定义布局风格保存/切换；`useCustomProfile` 先改缩略图尺寸，再切布局类型、边栏、排序（缩放锚点须按切换前的排序和可视区捕获） |
| ProgressBar.swift（219） | 底部细进度条，sessionId 防串台 |

## Views/（19 文件）

### Layout.swift（318 行）— 布局引擎（三布局 + detail）
- `CustomFlowLayout`（justified）— 流式行，行高=行内最高；尺寸由 recalcLayout 预先算好，布局只摆放
- `CustomGridLayout` — 固定 (列数+1) 等分格，格内居中；列数复用 waterfall 的 numberOfColumns
- `WaterfallLayout` — 固定列，放入最矮列，高度按宽比缩放
- `LeftAlignedCollectionViewFlowLayout` — detail 列表用，修系统默认居中
- 共同点：prepare() 全量预计算 cache、RTL 镜像、`getViewController` 反查 VC 读 profile

### 其他 Views
| 文件 | 职责 / 关键接口 |
|---|---|
| CustomCollectionViewItem.swift（1616） | 缩略图单元格。`configureWithImage` **唯一渲染入口**（文件名/选中/标签/评级/角标/剪切变淡；同时经 `updateAccessibilityLabel` 把整个单元格作为一个「文件名, 类型」辅助功能元素（角色 cell，并清空子元素：NSImageView 上 `setAccessibilityElement(false)` 无效，缩略图、文件名文本框、视频角标必须由父视图用 `setAccessibilityChildren([])` 去掉；用 cell 而不是 group，因为 AXGroup 容器不出现在多数自动化工具的元素树里），标签取自路径而不是 `imageNameField`，所以关闭「显示缩略图文件名」也能读到；单元格的角色、元素属性与清空子元素都在 `viewDidLoad` 一次设好，复用不丢，标签随每次 `configureWithImage` 更新）；`playVideo/stopVideo` 内联播放；鼠标事件系列（`mouseDown` 的双击分支：设置「双击用默认应用打开」开启时，普通文件交给 `NSWorkspace.open`，文件夹和替身仍走 `openLargeImage`；⌘/⇧ 双击开新标签页的逻辑在它之前，不受影响） |
| CustomCollectionView.swift（485） | 右键菜单（打开方式/新建/粘贴/标签过滤）、目录统计浮层、焦点协调 |
| CustomCollectionViewManager.swift（126） | DataSource/Delegate；`sizeForItemAt` 是布局类读 thumbSize 的 delegate 通道 |
| LargeImageView.swift（2875） | 大图查看器：缩放/平移/镜像、视频播放控制+AB 循环、EXIF 浮层、OCR/二维码、边缘箭头；整个视图是一个「文件名, 类型」辅助功能元素（角色 group，图片与视频共用，标签挂在容器上因为视频播放时 `imageView` 是隐藏的；`accessibilityChildren()` 重写成「未隐藏的子视图去掉 imageView，再经 `NSAccessibility.unignoredChildren(from:)` 展开」；不能过滤 `super` 的结果——它返回的是已展开的元素，NSImageView 以 cell（NSImageCell）出现，`!== imageView` 匹配不到，这也是 `setAccessibilityElement(false)` 对 NSImageView 无效的原因：暴露出来的是 cell；不展开的话，控制条、提示浮层这类本身不是辅助功能元素的容器视图会原样出现在返回值里），标签跟着 `file` 的 `didSet` 更新（赋值点有 `changeLargeImage` 与 `switchFolder` 两处） |
| VideoPlayerControlsView.swift（848） | 自绘控制条：进度 SliderSubclass、音量、AB 标记、自动隐藏 |
| CustomOutlineView / Manager | 分组目录树的数据源、plain table style、28pt 正文行与动态灰色选中绘制、leading/trailing 布局；角色检查隔离标题、分隔线和标签的文件操作，标签圆点仅在侧栏使用系统语义色，「所有标签」绘制双环；固定 Finder 入口复用 macOS CoreTypes 图标资源，OneDrive 使用 Finder 同形模板字形，卷行按 Finder 位置显示推出按钮；目录继续支持右键与拖放；辅助功能：分组标题与数据行单元格各自带 `AccessibilityLabels.sidebar` 的标签（标签条目带「标签」），分隔线 `NSBox` 设为非元素，分组标题与数据行用 `setAccessibilityChildren([])` 去掉图标和文本框这些重复/无名的子元素（推出图标因此不单独暴露：显式列为子元素或保持默认都实测出不来，且它没有「按下」动作）；标题自行绘制间距，移除分组额外缩进，列宽固定为 viewport，不绘制展开箭头（`frameOfOutlineCell` 恒为 `.zero`），展开 / 收起靠双击行（`outlineViewDoubleClicked`）或键盘 ←/→/空格/回车 |
| CustomImageView.swift（215） | Interpolated/Integer/Bordered/Thumb/Large 各 ImageView 变体 |
| FileInfoWindow.swift（621） | 文件信息窗口（可折叠 sections、纯文本导出） |
| ImageEditingView.swift（982） | 标注编辑画布（EDIT_FEATURE_ENABLED 门控，默认关闭） |
| CustomPathControl.swift（371） | 面包屑路径条：逐段命中检测、右键打开方式、拖文件到段=移动 |
| FavoritesPopoverViewController.swift（403） | 收藏夹弹窗（增删改、拖拽排序、持久化） |
| CoreAreaView.swift（194） | 内容区容器：中央提示、扫描进度、拖放进目录 |
| CustomEffectView / CustomSplitView / DrawingView / CustomProfileView | 拖放透传效果视图 / 分隔条中键折叠 / 手势轨迹浮层（hitTest=nil 不挡事件）/ 布局风格编辑弹窗 |

## SettingsViews/（6 文件）

全部基于 sindresorhus/Settings 库，直接读写 globalVar/UserDefaults：

| 文件 | 内容 |
|---|---|
| GeneralSettingsViewController（279） | 启动行为、滚动灵敏度、过滤保持、拼音搜索 |
| CustomSettingsViewController（323） | 设置面板「查看」页：大图/视频/搜索/保持状态/缩略图等勾选项与缩略图排除目录（拖放表格）；「文件操作」分组两个开关 `deleteWithoutConfirm`、`doubleClickOpenWithDefaultApp`（`globalVar` + UserDefaults 同名键，`AppDelegate` 启动时读取，默认关） |
| TaggingSettingsViewController（431） | 自定义标签管理、增强索引 |
| AdvancedSettingsViewController（183） | 内存上限、缩略图线程数、搜索深度（内/外置卷分开）、FFmpeg 开关 |
| ActionsSettingsViewController（58） / DemoSettingsViewController（20） | 动作说明 / 占位页 |

## 工程配置要点

- `PixyTests/`：单元测试 target（宿主为 Pixy，仅 Debug）。`SidebarNamingTests`、`DeleteConfirmPolicyTests`、`TreeViewModelURLTests`、`SortKeyTests`、`AccessibilityLabelsTests`、`ScrollAnchorMathTests`、`UpdateCheckerTests`，共 124 个用例；pbxproj 里没有自动同步文件夹，新增测试文件用 `scripts/pbxproj-add-file.py <路径> --target tests` 登记进 `PixyTests` 组与 Sources 阶段（见 [build.md](build.md#新增源文件)）。命令见 [build.md](build.md#单元测试)

- `scripts/bench/run.sh [300|6000|20000 ...]`（图片生成器 `scripts/bench/gen-images.py`，回归测试 `scripts/test-bench-run.sh`）：本机性能基线，对 Debug 的 PixyDbg 测目录加载耗时（读 `PIXY_LOG_FILE` 里的计时行）与内存（`ps` RSS 采样 + `footprint`）；只作本机对比、不进 CI，不碰 `/Applications/Pixy.app`，只在 PixyDbg 的偏好域里临时改 `lastFolder` / `hasNormalExit` 并还原。测量定义与基线数字见 [performance-baseline.md](performance-baseline.md)，命令见 [build.md](build.md#性能基线本机)

- `scripts/release-prepare.sh <版本>`（助手 `release-prepare-edit.py`，回归测试 `test-release-prepare.sh`）：发版前的本地准备，只改 pbxproj 里 FlowVision 目标的 4 行版本 / build 号（按 目标 → 配置列表 → 配置 定位，测试目标 PixyTests 的 `1.0` / `1` 不动）、CHANGELOG「未发布」标题与 checklist「## 记录」段顶部的骨架，再跑两个检查并打印手动步骤；不联网、不 commit、不 push、不打 tag。流程与拒绝条件见 [release.md](release.md#发布步骤)
- 部署目标 **macOS 11.0**（xcodeproj 4 处配置一致）
- SPM 依赖全部来自公开仓库，版本由 `FlowVision.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 锁定：SDWebImageWebPCoder、SDWebImage、libwebp-xcode、**BTree**、**Settings**。clone 后无需在仓库外准备任何本地包。
- `ffmpegkit.xcframework` 嵌入 CopyFiles（CodeSignOnCopy），运行时 dlopen；由 `scripts/bootstrap-dependencies.sh` 下载并校验 SHA-256。
- `LocalDev.xcconfig.template` → 复制为 `LocalDev.xcconfig`（gitignored）启用 `LOCAL_DEV` 编译条件；Base.xcconfig 用 `#include?` 可选引入。`DEBUG && LOCAL_DEV` 时 `ViewController` 的 `treeRootFolder` 指向作者的测试数据目录，侧栏只显示该目录而不是真实的磁盘/OneDrive；要在本机 Debug 构建里看真实侧栏，命令行加 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` 覆盖
