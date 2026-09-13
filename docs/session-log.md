# 会话日志

本日志由 Codex、Claude 或人工共同维护。每个会话条目标题必须标注执行者：`[Codex]`、`[Claude]` 或 `[人工]`。项目级日志记录完整细节；外层 nilo 仓库 `docs/session-log.md` 只记简要条目并指向这里。

## 2026-09-13

### [Claude] · 建立中文文档体系

#### 背景

- 本仓库 fork 自 netdcy/FlowVision（上游 1.7.6），由 natinli/Pixy 维护。
- 仓库原有文档仅面向最终用户的 README.md/README_zh.md（英文/中文）和 docs/ 下 3 张预览图，无开发向文档。
- 用户要求：完全重新设计、覆盖全面、便于长期维护的全中文文档体系，含用户文档与开发/AI 协作文档；新增 CHANGELOG；完全重写 README；项目内建立更细粒度的会话日志。

#### 完成

- 深读源码 53 个 Swift 文件，研究笔记存于 nilo 仓库 `.trellis/tasks/09-13-flowvision-docs/research/source-notes.md`。
- 新建 `CLAUDE.md`：AI 协作入口（仓库性质、remote 布置、协作约定、文档地图、环境注意）。
- 新建 `CHANGELOG.md`：基于上游 36 个 release（1.0.2 → 1.7.6）整理的中文版本历史，顶部设「Fork」条目记录本仓库改动。
- 完全重写 `README.md` 与 `README_zh.md`：结构对齐新文档体系（功能特性、安装、快速上手、文档导航），双语互相链接，保留上游支持/许可证信息。
- 新建 `docs/index.md`：文档中心总入口 + 硬性维护规则表（哪类改动须更新哪份文档）。
- 新建用户文档 `docs/user/`：installation.md（三种安装方式 + quarantine 处理）、usage.md（四种视图、手势、快捷键、视频、标签评级、设置全览）、faq.md（损坏提示、HDR/RAW、性能、标签等排查）。
- 新建开发文档 `docs/dev/`：architecture.md（模块地图、核心数据流、全局状态组织、缓存去重、唯一真源清单）、modules.md（逐目录逐文件职责与关键接口）、build.md（依赖结构、FFmpegKit、构建步骤、xcconfig、调试、常见问题）、contributing-internal.md（代码约定、常见改动落点、上游同步策略、提交约定）。

#### 验证与边界

- 文档中全部源码路径基于实际勘察（53 文件清单逐目录盘点），模块职责经子代理逐文件深读后撰写。
- **构建命令未实测**：本机仅有 Command Line Tools，无完整 Xcode；build.md 已标注验证状态，Xcode 安装后需按文档实操修正。
- 工程引用仓库外本地 SPM 包（`../BTree`、`../Settings`），build.md 写明目录布置要求。
- 未改动任何上游源码；改动文件：新建 CLAUDE.md、CHANGELOG.md、docs/{index.md,session-log.md,user/*,dev/*}，重写 README.md、README_zh.md。

#### 待跟进

- [x] 安装完整 Xcode 后实测构建命令（2026-09-13 完成，见下条）。
- [ ] 首次 push 到 origin（natinli/Pixy）。
- [ ] 上游发布新版本时按 contributing-internal.md 的同步策略合并。

### [Claude] · Xcode 26.3 实测构建通过

#### 完成

- 安装 Xcode 26.3（Build 17C529），`xcode-select` 已指向 /Applications/Xcode.app。
- 布置本地依赖：clone attaswift/BTree 与 sindresorhus/Settings 到 `projects/`（与 FlowVision 同级，满足工程 `../BTree`、`../Settings` 相对路径引用）。
- 下载上游备份的 ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip（26MB）解压至 `projects/ffmpeg-kit-build/bundle-apple-xcframework-macos/`（8 个 xcframework），`xattr -rd` 清 quarantine。
- Release 构建成功：`xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`，产物 `~/Library/Developer/Xcode/DerivedData/FlowVision-*/Build/Products/Release/FlowVision.app`（约 71MB）。

#### 验证与修正

- **修正 build.md 两处错误认知**：
  1. FFmpegKit 是**硬依赖**——工程 build phase 直接引用 8 个 xcframework，缺失时构建失败；原文档推测"缺失也能构建、仅运行期降级"是错的。dlopen 降级只发生在 xcframework 存在但无法加载的场景。
  2. 新增「签名」一节：无证书时 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` 可跳过签名构建（实测通过）；正式签名需 Xcode 登录 Apple ID 选 Team。
- 常见构建问题表补充两条实测遇到的错误及解法。

#### 待跟进

- [ ] 正式签名配置（Xcode 登录 Apple ID）后重新构建带签名版本。

### [Claude] · 应用更名 FlowVision → Pixy

#### 完成

- 用户经五轮候选名筛选后选定 **Pixy**。
- 改动（仅展示名，符合 PRD 范围）：
  - pbxproj：`INFOPLIST_KEY_CFBundleDisplayName = Pixy`（Debug/Release 两处）；`PRODUCT_NAME` 从 `$(TARGET_NAME)` 改为 `Pixy`/`PixyDbg`。
  - `WindowController.swift:502` 工具栏默认标题、"DataModel.swift:896" localizedName → "Pixy"。
  - 文档品牌替换：README 双语标题与 fork 说明、CLAUDE.md、docs/index.md、installation.md、faq.md、build.md 产物路径。
  - CHANGELOG.md 顶部 Fork 条目追加更名记录。
- 未改动：bundle id（netdcy.FlowVision）、数据目录（Application Support/FlowVision）、scheme 名、仓库目录名、上游 URL、GitHub 仓库名。

#### 验证与技术记录

- Release 构建通过；启动后 Dock、菜单栏、进程 displayed name 均为 **Pixy**。
- 关键发现：`CFBundleDisplayName` 只改菜单栏/关于窗口显示；**Dock 悬停与快捷菜单用 `CFBundleName`**，它被构建系统强制写为 `$(PRODUCT_NAME)`，改 pbxproj 的 `INFOPLIST_KEY_CFBundleName` 无效（Xcode 不支持该键），源 Info.plist 加该键也会被覆盖。**唯一正规改法是设置 `PRODUCT_NAME`**——产物从 FlowVision.app 变为 Pixy.app，CFBundleName 随之变 Pixy。
- LaunchServices 缓存旧名时用 `lsregister -f <app>` + `killall Dock` 刷新。

### [Claude] · 仓库更名与依赖迁移

#### 完成

- GitHub 仓库更名：natinli/FlowVision → **natinli/Pixy**（gh repo rename），origin 已更新；upstream（netdcy/FlowVision）不变。
- 本地目录更名：`projects/FlowVision` → `projects/Pixy`；nilo 登记表与 .gitignore 同步更新。
- **构建依赖迁出 projects/**：BTree、Settings、ffmpeg-kit-build 移至 `~/Developer/pixy-deps/`，projects/ 只留项目本体。pbxproj 10 处相对路径同步更新（BTree/Settings 为 XCLocalSwiftPackageReference，ffmpeg 的 8 个 xcframework 为 PBXFileReference path）。
- 文档更新：build.md 依赖结构表与目录树（含「仓库不在标准位置需调整相对深度」说明）、CLAUDE.md 环境注意、排障表。

#### 验证与技术记录

- Release 构建通过（新路径实测）。
- 关键点：pbxproj 相对路径以**仓库目录**（projects/Pixy/）为基准；本仓库在 `~/Documents/nilo/projects/` 下，故到主目录需 `../../../../`（4 级）。路径深度写错时报 `the package at '...' cannot be accessed`，报错信息里会显示解析后的绝对路径，可用于定位差几级。
- Git 仓库更名后旧 URL 自动重定向，但本地 origin 与文档链接应手动更新。

#### 待跟进

- [ ] 首次 push 到 origin（natinli/Pixy）。
- [ ] 上游发布新版本时按 contributing-internal.md 的同步策略合并。

### [Claude] · 更换应用图标

#### 完成

- 应用图标替换为用户选定的 icons8 "Photo Gallery" 图标（96px 下载版放大至 1024px 写入 AppIcon.appiconset/icon.png）。
- 构建通过，Dock/应用已重启生效。

#### 边界

- 源图为 icons8 版权素材，免费许可需署名（"Icons by icons8"）；放大到 1024px 后大尺寸略糊。后续可换用 icons8 高清正版授权或 docs/design/ 原创概念稿。

### [Claude] · 修复菜单栏残留旧名

#### 完成

- 根因：应用菜单（关于/隐藏/退出 FlowVision）标题写死在 Main.storyboard 与两个 .xcstrings（101+51 处多语言文案）里，前两轮只改了代码与 Info.plist 未覆盖到。
- 处理：storyboard 中 UI 标题全部改为 Pixy（12 处 customModule="FlowVision" 为 TARGET 模块引用，**必须保留**，改了会白屏）；两个 xcstrings 全量替换 FlowVision→Pixy（JSON 校验通过）。
- 构建通过，编译产物 Main.storyboardc 已验证含 "About Pixy"/"Quit Pixy"。

#### 边界

- 源码中仍有少量 FlowVision：工程名/TARGET/scheme（用户决定保留）、数据目录 appendingPathComponent（避免数据迁移）、customModule 引用。

### [Claude] · 两项 UX 优化

#### 完成

- **侧边栏毛玻璃**：storyboard 侧边栏 customView 插入 NSVisualEffectView（behindWindow + sidebar material，置于最底层）；CustomTableRowView.drawBackground 不再填充 OutlineViewBgColor 纯色改为透明，右键边框逻辑保留。明暗模式均生效。
- **Dock 图标联动（方案 A）**：closeLargeImage 开头检测 publicVar.isLaunchFromFile（Finder/外部打开图片的会话标记），命中则关窗口并 NSApp.terminate；常规浏览会话不受影响。windowWillClose 已有完整的保存/清理/terminate 链路，直接复用。
- 已知边界：customModule="FlowVision"、工程名/scheme、数据目录名保持不变（此前决策）。

#### 验证

- Release 构建通过；启动后侧边栏透出壁纸色调（vibrancy 生效），选中样式正常。
- 关闭大图退出行为待用户 Finder 双击图片实测（isLaunchFromFile 场景）。
