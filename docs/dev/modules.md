# 模块详解

> 逐目录逐文件的一句话职责 + 关键接口。行数截至 fork 时（上游 1.7.6，53 个 Swift 文件）。查找文件用 ⌘F；模块间关系见 [architecture.md](architecture.md)。

## 根级（3 文件）

### AppDelegate.swift（1281 行）
应用生命周期入口。
- `applicationWillFinishLaunching` — 菜单初始化、设置面板注册、globalVar 默认值
- `createNewWindow(_:useCreateWindowShowDelay:isLaunchFromFile:urlsToSelect:)` — 创建 WindowController，携带跨窗口启动临时状态
- `application(_:openFiles:)` — Finder 双击入口：目录打开 or 文件大图打开
- `openImageInMainWindow` / `openImageInTargetWindow` — 写 `publicVar.openFromFinderPath` 触发定位
- `menuNeedsUpdate` / `validateMenuItem` — 主菜单动态构建

### WindowController.swift（2052 行）
单窗口壳。
- `toolbar(_:itemForItemIdentifier:)` — 全部工具栏项构建，action 转发 ViewController
- `showMoreMenu` — 「更多」巨型菜单（HDR、锁定、RAW 内嵌缩略图、便携/递归模式等约 80 项）
- `saveWindowState` / `windowWillClose` — frame、lastFolder 持久化 → `viewController.prepareForDeinit()`
- `windowWillEnterFullScreen/DidEnter/DidExit` — 黑底、工具栏/光标隐藏联动

### ViewController.swift（2479 行）
核心中枢，文件内含三个类：
- `CustomProfile: Codable` — 布局外观配置（layoutType、thumbSize、CellPadding 等派生属性）；UserDefaults key `"CustomStyle_v2_current"`
- `PublicVar` — 每窗口状态：视图模式、过滤、folderStepStack 历史栈、isInLargeView、三个布局实例、`setFileExtensions()`
- `ViewController`：
  - `viewDidLoad` — 装配 manager 们、读 UserDefaults、按 profile 选布局、注册 7 类 NSEvent monitor
  - `startBackgroundTaskThread` — 启动三条常驻线程（readInfo / thumb / memMonitor）
  - `setLoadThumbPriority` — 滚动时按可见中心距离重排加载队列
  - `startWatchingDirectory` / `scheduledRefresh` — 目录监听 + 防抖刷新
  - `_rightMouseDown/Dragged/Up` — 手势轨迹采集（增量式，阈值 4px）
  - `afterFinishLoad` — 决定启动目录 → 启动后台线程

## Common/（11 文件）

### DataModel.swift（1042 行）
核心数据结构，全部基于 BTree 有序 Map。
- `SortKey/SortKeyFile/SortKeyDir` — Comparable 排序键；`<` 是**全项目排序唯一真源**（path/日期/size/exif/rating/tag + SortType/folderFirst/randomSeed）；`writeExifInfo`/`writeTagInfo` 惰性加载
- `FileModel` — 单文件：path/ext/type/image/thumbSize/originalSize/rotate/finderTags/lock/ver
- `DirModel` — `files: Map<SortKeyFile,FileModel>` + layoutCalcPos（增量布局游标）+ keepScrollPos；`changeSortType` 重建排序
- `DatabaseModel` — `db: Map<SortKeyDir,DirModel>` + curFolder + `ver`（版本号，使旧任务失效）
- `TreeViewModel`/`TreeNode` — 目录树数据
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

### GlobalVariable.swift（208 行）
三层组织：顶层 let 常量（DEFAULT_SIZE、预载范围 20/40、阈值）→ `globalVar` 单例（扩展名白名单 init 硬编码、设置项、跨窗口启动状态、剪切模式）→ 自由函数（`getViewController()` responder 链上溯是 View 反查 VC 的通用手段）。

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
| Log.swift（330） | 全局 log() + 日志查看窗口 |
| Enum.swift（32） | FileType / 手势方向 / LayoutType(justified,waterfall,grid,detail) / SortType（21 种）/ 设置页注册 |
| TempVariable.swift（13） | 编译期开关：`EDIT_FEATURE_ENABLED=false`、SDK_VERSION |
| RefCode.swift（38） | FSEvents 参考实现，未接入主链路（主链路用 DispatchSourceFileSystemObject） |

## ViewControllerExtension/（16 文件，全是 ViewController extension）

### FileSystem.swift（1812 行）— 扫描与导航核心
- `treeTraversal(folderURL:round:initURL:direction:sameLevel:skip:dryRun:)` — 递归扫描：过滤隐藏/搜索/标签/评级 → 分离 subFolders/files → 写 DirModel；按 direction 前序/后序递归
- `switchDirByDirection(direction:dest:...)` — 导航状态机：zero/left/right/up/down/forward；维护历史栈；`fileDB.ver+=1`；定位 → treeReLocate + switchFolder
- `switchFolder(path:)` — 清任务池、快照渐隐动画、处理 Finder 打开定位、文件推入 readInfoTaskPool
- `scanFiles` / `scanVirtualFiles` — 递归模式枚举 / 按标签聚合的虚拟目录
- `handleGetInfo` 系列 — 文件信息窗口数据组装

### LayoutManagement.swift（235 行）— 布局计算唯一真源
- `recalcLayout(targetFolder)` — 增量计算（从 layoutCalcPos 起）：justified 宽高比凑行 / waterfall·grid 固定列宽 → 写 FileModel.thumbSize/lineNo
- `switchToJustifiedView/GridView/WaterfallView/DetailView`、`changeThumbSize`、`refreshAll`

### 其他 extension
| 文件 | 职责 / 关键接口 |
|---|---|
| LargeImage.swift（1052） | `openLargeImage`（双击入口，目录/替身/图片分派）、`changeLargeImage`（预载+异步可取消）、`preloadLargeImage`（前后 2~3 张） |
| FileOperation.swift（1735） | handleCopy/Paste/Move/Delete/Rename（批量面板）、mergeFolder 冲突状态机、handleFilePromiseDrop（Finder 拖入）、操作后同步 EnhancedIndex |
| KeyShortcut.swift（996） | `KeyShortcutManager(event:)` 单函数全快捷键分发，含输入焦点判断 |
| EventHandler.swift（441） | 菜单动作实现层：历史导航、约 25 个 toggle、前往文件夹、操作日志 |
| Search.swift（520） | showSearchOverlay、performSearch（正则/拼音/全路径）、applyFilter（过滤条件由 treeTraversal 应用）、quickSearch 防抖 |
| ArrowKeyLocate.swift（280） | `findClosestItem` 方向键导航：grid 列偏移 / waterfall 4×列数邻域 / justified 同行，选屏幕中心最近 |
| Tagging.swift（262） | 标签/评级动作与过滤器（与/或、反向）；依赖 FinderTag.swift |
| RightMouseGesture.swift（135） | `analyzeGesture` 方向组合→动作：1 方向（左右上下）、2 方向（up+right=平级下一个、down+right=关闭）；RTL 左右互换 |
| WindowManagement.swift（417） | maximize/suitable/portable 窗口尺寸系列 |
| MemoryManagement.swift（87） | LRUMemRecord（目录访问 LRU）、内存 footprint 报告 |
| AutoScrollPlay.swift（149） | 自动滚动（Timer 连续滚动）与自动播放（定时 nextLargeImage） |
| DirTree.swift（150） | `treeReLocate` 切目录后树中逐级展开并选中 |
| LayoutProfileConfig.swift（127） | 自定义布局风格保存/切换 |
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
| CustomCollectionViewItem.swift（1590） | 缩略图单元格。`configureWithImage` **唯一渲染入口**（文件名/选中/标签/评级/角标/剪切变淡）；`playVideo/stopVideo` 内联播放；鼠标事件系列 |
| CustomCollectionView.swift（485） | 右键菜单（打开方式/新建/粘贴/标签过滤）、目录统计浮层、焦点协调 |
| CustomCollectionViewManager.swift（126） | DataSource/Delegate；`sizeForItemAt` 是布局类读 thumbSize 的 delegate 通道 |
| LargeImageView.swift（2875） | 大图查看器：缩放/平移/镜像、视频播放控制+AB 循环、EXIF 浮层、OCR/二维码、边缘箭头 |
| VideoPlayerControlsView.swift（848） | 自绘控制条：进度 SliderSubclass、音量、AB 标记、自动隐藏 |
| CustomOutlineView(.swift 421 / Manager 403) | 目录树 View+Manager（DataSource、展开联动、拖放） |
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
| CustomSettingsViewController（309） | 缩略图排除目录（拖放表格） |
| TaggingSettingsViewController（431） | 自定义标签管理、增强索引 |
| AdvancedSettingsViewController（183） | 内存上限、缩略图线程数、搜索深度（内/外置卷分开）、FFmpeg 开关 |
| ActionsSettingsViewController（58） / DemoSettingsViewController（20） | 动作说明 / 占位页 |

## 工程配置要点

- 部署目标 **macOS 11.0**（xcodeproj 4 处配置一致）
- SPM：SDWebImageWebPCoder 0.14.6（远程）；**BTree、Settings 为本地包 `../BTree`、`../Settings`**（相对仓库外目录，clone 后需按 build.md 布置）
- `ffmpegkit.xcframework` 嵌入 CopyFiles（CodeSignOnCopy），运行时 dlopen
- `LocalDev.xcconfig.template` → 复制为 `LocalDev.xcconfig`（gitignored）启用 `LOCAL_DEV` 编译条件；Base.xcconfig 用 `#include?` 可选引入
