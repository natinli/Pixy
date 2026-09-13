# 会话日志

本日志由 Codex、Claude 或人工共同维护。每个会话条目标题必须标注执行者：`[Codex]`、`[Claude]` 或 `[人工]`。项目级日志记录完整细节；外层 nilo 仓库 `docs/session-log.md` 只记简要条目并指向这里。

## 2026-09-13

### [Claude] · 建立中文文档体系

#### 背景

- 本仓库 fork 自 netdcy/FlowVision（上游 1.7.6），由 natinli/FlowVision 维护。
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
- [ ] 首次 push 到 origin（natinli/FlowVision）。
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
