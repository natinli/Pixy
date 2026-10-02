# 架构总览

> 粒度控制：本文只写模块地图与数据流；逐文件细节见 [modules.md](modules.md)。以源码为准。

## 技术栈

- **纯 AppKit**（无 SwiftUI），Swift + Xcode 工程（`FlowVision.xcodeproj`）
- 部署目标：macOS 11.0
- SPM 依赖：
  - SDWebImageWebPCoder 0.14.6（连带 SDWebImage 5.21.0、libwebp-xcode 1.5.0）——远程包
  - **BTree**、**Settings**——**仓库外本地包**（相对路径 `../BTree`、`../Settings`），clone 后需按 build.md 组织目录
- FFmpegKit：`ffmpegkit.xcframework` 嵌入 Bundle，`dlopen` 懒加载，未加载时全部 FFmpeg 功能静默降级
- 并发模型：传统 GCD / OperationQueue / 常驻 Thread 为主，少量 `Task{}`；自建 `TaskPool` 管理后台任务

## 模块地图

```
FlowVision/Sources/（53 个 Swift 文件，约 3.3 万行）
├── AppDelegate.swift          应用入口：生命周期、窗口创建、Finder 打开分发、菜单
├── WindowController.swift     单窗口壳：工具栏、标题栏、全屏、窗口状态持久化
├── ViewController.swift       核心中枢（~2500 行）：持有数据/布局/线程池，协调全链路
│                              ├── CustomProfile      布局外观配置（UserDefaults 持久化）
│                              └── PublicVar          每窗口运行时状态
├── ViewControllerExtension/   主控制器功能拆分（16 个 extension 文件）
│   ├── FileSystem.swift       目录扫描与导航状态机（treeTraversal / switchDirByDirection / switchFolder）
│   ├── LayoutManagement.swift 布局计算唯一真源（recalcLayout）
│   ├── LargeImage.swift       大图打开/切换/预载
│   ├── FileOperation.swift    文件操作全集（复制/剪切/删除/重命名/合并冲突）
│   ├── KeyShortcut.swift      全部键盘快捷键分发（单函数巨型分发器）
│   ├── EventHandler.swift     菜单/快捷键动作实现（约 25 个 toggle）
│   ├── Search.swift           搜索浮层与过滤
│   ├── RightMouseGesture.swift 右键手势方向分析
│   ├── ArrowKeyLocate.swift   方向键定位
│   ├── Tagging.swift          标签/评级动作与过滤器
│   ├── DirTree.swift          目录树定位（treeReLocate）
│   ├── WindowManagement.swift 窗口尺寸调整（便携模式等）
│   ├── MemoryManagement.swift LRU 目录访问记录、内存报告
│   ├── AutoScrollPlay.swift   自动滚动/自动播放
│   ├── LayoutProfileConfig.swift 布局风格配置切换
│   └── ProgressBar.swift      底部进度条
├── Views/                     自定义视图（19 个文件）
│   ├── Layout.swift           布局引擎：CustomFlowLayout(justified) / CustomGridLayout / WaterfallLayout / LeftAligned(detail)
│   ├── CustomCollectionViewItem.swift  缩略图单元格（configureWithImage 唯一渲染入口）
│   ├── CustomCollectionView.swift / Manager  集合视图与数据源
│   ├── LargeImageView.swift   大图查看器（缩放/平移/视频/EXIF/OCR）
│   ├── VideoPlayerControlsView.swift  视频控制条
│   ├── CustomOutlineView(.swift/Manager)  左侧目录树
│   ├── CustomImageView.swift  各场景 ImageView 变体
│   ├── FileInfoWindow.swift   文件信息窗口
│   ├── ImageEditingView.swift 图片标注编辑（EDIT_FEATURE_ENABLED 门控，默认关）
│   └── …（路径条、收藏夹弹窗、手势轨迹浮层等）
├── Common/                    模型与工具（11 个文件）
│   ├── DataModel.swift        核心数据结构：SortKey/FileModel/DirModel/DatabaseModel/TaskPool（BTree Map）
│   ├── ImageProcess.swift     图像解码/缩放/缩略图/元数据 + LargeImageProcessor 缓存去重（最大工具文件）
│   ├── GlobalVariable.swift   globalVar 单例：扩展名白名单、设置项、跨窗口状态
│   ├── FinderTag.swift        Finder 标签全链路 + EnhancedIndex 自建标签索引
│   ├── FFmpegKit.swift        dlopen 封装
│   ├── VideoProcess.swift     AVPlayer 视图变体、AB 循环合成
│   ├── Common.swift           杂项：Atomic/节流/弹窗/VolumeManager/拼音
│   ├── Log.swift              日志与日志窗口
│   ├── Enum.swift             FileType/LayoutType/SortType(21 种)/手势方向
│   ├── TempVariable.swift     编译期开关（EDIT_FEATURE_ENABLED、SDK_VERSION）
│   └── RefCode.swift          FSEvents 参考实现（未接入主链路）
└── SettingsViews/             设置面板（6 文件，基于 sindresorhus/Settings）
```

## 核心数据流（选目录 → 显示缩略图）

```
任意 UI 入口（点击/手势/快捷键/树选中）
  → ViewController.switchDirByDirection        FileSystem.swift   导航状态机：历史栈、ver+=1 失效旧任务
  → treeTraversal                              FileSystem.swift   递归扫描：过滤、SortKey 建序、写 DirModel
  → 在 db 有序 Map 定位 nextFolder
  → switchFolder                               FileSystem.swift   清任务池、快照动画、文件推入 readInfoTaskPool
  → readInfoThread（常驻线程）                  ViewController.swift
  → getImageInfo                               ImageProcess.swift ImageIO 读尺寸/EXIF/HDR 判定
  → recalcLayout                               LayoutManagement.swift 增量计算 thumbSize（justified 凑行 / 固定列）
  → Layout.prepare（三个布局类之一）            Layout.swift       从 delegate 读 thumbSize 摆放
  → thumbThread 取 loadImageTaskPool 任务      ViewController.swift
  → ThumbImageProcessor.getImageCache          ImageProcess.swift 缓存/去重 → miss 则 getImageThumb 解码
  → item.configureWithImage                    CustomCollectionViewItem.swift 渲染单元格
```

大图链路：`openLargeImage`（双击）→ `changeLargeImage`（预载前后 2~3 张）→ `LargeImageProcessor.getImageCache`（LRU 16）→ `LargeImageView` 显示。

内存回收：`memMonitorThread` 每 2 秒检查——LRU 末项超 600s 或内存 footprint 超限 → 清除非可见范围（保留 PRELOAD_THUMB_RANGE_PRE/NEXT=20/40）的图像缓存。

## 全局状态组织

| 层 | 位置 | 内容 |
|---|---|---|
| 编译期常量 | `TempVariable.swift` | EDIT_FEATURE_ENABLED（编辑功能总开关，默认 false）、SDK_VERSION 条件编译 |
| 进程级常量 | GlobalVariable.swift 顶层 let | DEFAULT_SIZE、预载范围、阈值、颜色 |
| 进程级单例 | `globalVar: GlobalVar` | 扩展名白名单（init 硬编码派生）、设置项、跨窗口启动临时状态、剪切模式 |
| 每窗口状态 | `ViewController.PublicVar` | 视图模式、过滤状态、历史栈、三个布局实例 |
| 目录数据 | `fileDB: DatabaseModel` | 全局目录库（BTree Map），ver 版本号使旧任务失效 |

分界原则：跨窗口/进程级 → `globalVar`；每窗口视图态 → `publicVar`。View 反查 ViewController 统一走 `getViewController()`（responder 链上溯）。

## 缓存与去重（LargeImageProcessor / ThumbImageProcessor）

- 自实现 LRU：字典 + 访问序数组 + NSLock，countLimit=16
- cacheKey 含 `ver`（DirModel/FileModel 版本号），文件变更即整键失效
- **nil 失败结果也入缓存**，避免反复重试失败文件
- 同 key 并发去重：`ongoingTasks` + DispatchSemaphore，后来者 wait 后读缓存；`needWaitWhenSame=false` 时直接返回 nil（预载不阻塞）

## 关键唯一真源（修改须谨慎）

| 逻辑 | 位置 | 说明 |
|---|---|---|
| 排序 | `DataModel.swift` SortKey 的 `<` | 全项目排序唯一实现，21 种 SortType × 各种开关 |
| 布局尺寸 | `LayoutManagement.swift` recalcLayout | 增量游标 layoutCalcPos，写入 FileModel.thumbSize/lineNo |
| 目录遍历 | `FileSystem.swift` treeTraversal | 扫描/过滤/递归方向全在此 |
| 手势判定 | `RightMouseGesture.swift` analyzeGesture | 方向组合 → switchDirByDirection 的映射 |

## 值得注意的设计

- **巨型 VC + extension 分文件**：新功能优先建 `ViewControllerExtension/` 新文件，不扩 ViewController.swift 本体。
- **常驻 Thread + TaskPool**：readInfoThread/thumbThread/memMonitorThread 三条常驻线程消费任务池；滚动时 `setLoadThumbPriority` 按「可见中心距离」重排队列。
- **目录监听**：DispatchSourceFileSystemObject + 防抖（RefCode.swift 的 FSEvents 是未接入的参考实现）。
- **FFmpeg 懒加载**：未提供 xcframework 时应用正常运行，仅视频解码能力降级。
- **RTL 镜像**：三个布局类各自镜像 x 坐标，手势判定在 RTL 下左右语义互换。

## Finder 风格侧栏

`TreeViewModel.rebuildSidebar` 将桌面、文稿、下载、用户主目录、`globalVar.myFavoritesArray`、iCloud 云盘、当前本机、实际挂载卷、OneDrive 及现有 Finder 标签投影为个人收藏／iCloud／位置／标签四组。隔空投送、最近使用、应用程序、共享和 TimeMachine 不生成侧栏节点。分组节点不携带文件 URL，普通目录保持按需枚举；不同入口使用独立节点对象，身份由角色、入口 ID 和完整路径组成。刷新复用同身份节点并恢复用户手动展开、选中状态。

目录跟随由 `DirTree.treeReLocate` 统一负责：按规范 URL 的路径组件判断祖先关系，由 `TreeViewModel.sidebarCandidates` 排名，优先当前已成功定位的入口分支，其次最深收藏祖先，最后位置。默认导航不调用路径展开，侧栏只选中目标行；内容区进入子文件夹时清除侧栏选中态，避免灰色高亮与实际入口脱节；用户可通过披露箭头手动展开目录，右键开启「跟随当前目录」后才恢复路径祖先定位。标签继续使用既有虚拟路径；`isVirtualTagURL` 统一识别虚拟域，标签收藏按标签角色投影，路径候选不会与真实根目录混合。自定义树根作为位置入口保留，收藏存储格式不变。

收藏唯一源仍是 `globalVar.myFavoritesArray`；其 didSet 在主线程通知全部窗口，窗口刷新投影，关闭清理时解除观察。固定系统快捷入口只参与显示和去重，不写回收藏，也不保存侧栏展开状态到收藏。

`CustomOutlineView` 与 Manager 根据节点角色隔离标题、分隔线的导航／右键／拖放，标签不参与真实文件读写。原生 OutlineView 显式使用 plain style，由自定义行统一拥有标题间距、去除分组层视觉缩进和灰底选中几何，避免自动源列表样式附加边距。目录内容顶部按 `window.contentLayoutRect` 计算被工具栏遮挡的高度，再增加 15pt 间距，背景保持覆盖全窗口；布局变化时更新。主内容滚动区同样按内容面板完整几何避让工具栏，避免滚动缩略图遮住标题栏。列宽固定为 viewport，长名称截断并显示 tooltip；初始侧栏宽 238pt，收起时侧栏宽度置零并让内容面板吃满可用宽度，重新展开恢复 238pt 标准宽度。外观统一使用系统动态颜色、线性图标、28pt 正文行及 leading/trailing 约束，Finder 侧栏只保留文件夹、iCloud 云盘和位置入口，OneDrive 使用资源目录中的 Finder 同形模板字形，本机入口使用 `macmini` 符号，外置磁盘行保留推出按钮；侧栏与内容 8pt 圆角外侧共享窗口背后动态 sidebar 材质。
