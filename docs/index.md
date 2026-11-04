# Pixy 文档中心

macOS 瀑布流图片查看器（fork 自 FlowVision，展示名已更改为 Pixy）。全部文档为中文，按「你是谁、要做什么」分流。

## 用户文档（docs/user/）

| 文档 | 内容 |
|---|---|
| [安装](user/installation.md) | 下载安装、首次启动放行、源码编译、设为默认应用 |
| [使用说明](user/usage.md) | 浏览操作、右键手势、快捷键、视频播放、标签与评级、设置全览 |
| [常见问题](user/faq.md) | 打不开、缩略图、HDR/RAW、视频、性能等问题排查 |

## 按任务找文档

| 我想… | 看这里 |
|---|---|
| 装到自己的 Mac 上 | [user/installation.md](user/installation.md) |
| 学会右键手势与快捷键 | [user/usage.md](user/usage.md) |
| 排查启动被拦截、视频放不了 | [user/faq.md](user/faq.md) |
| 改侧栏 / 目录树行为 | [dev/modules.md](dev/modules.md) 的 `DataModel.swift`、`DirTree.swift`、`CustomOutlineView` 段，配合 [dev/architecture.md](dev/architecture.md)「Finder 风格侧栏」 |
| 改缩略图布局算法 | [dev/modules.md](dev/modules.md) 的 `LayoutManagement.swift`、`Layout.swift` 段 |
| 改大图模式 / 视频控制条 | [dev/modules.md](dev/modules.md) 的 `LargeImage.swift`、`LargeImageView.swift`、`VideoPlayerControlsView.swift` 段 |
| 加新功能 | [dev/contributing-internal.md](dev/contributing-internal.md) 的落点规则 |
| 编译 / 调试 | [dev/build.md](dev/build.md) |
| 发版 / 打 tag / 配 CI 凭据 | [dev/release.md](dev/release.md) |
| 了解为什么某处这样设计 | [dev/architecture.md](dev/architecture.md) 与 [CHANGELOG](../CHANGELOG.md) |
| 和上游同步 | [dev/contributing-internal.md](dev/contributing-internal.md) |

## 开发与 AI 协作文档（docs/dev/）

| 文档 | 内容 |
|---|---|
| [架构总览](dev/architecture.md) | 技术栈、模块地图、核心数据流、并发模型、全局状态组织 |
| [模块详解](dev/modules.md) | 逐目录逐文件职责与关键接口，改代码前先查这里 |
| [构建与调试](dev/build.md) | Xcode 环境、公开依赖、构建、签名、公证和常见问题 |
| [发布流程](dev/release.md) | 版本号规则、签名/未签名两种模式、CI Secrets、打 tag 步骤 |
| [首发 Smoke Checklist](dev/release-smoke-checklist.md) | 每次签名公证发布前的真实产物验收清单 |
| [修改指南与 fork 维护](dev/contributing-internal.md) | 常见改动落点、代码约定、上游同步策略 |

## 仓库级文档

| 文档 | 内容 |
|---|---|
| [README_zh](../README_zh.md) / [README](../README.md) | 项目简介、功能特性速览 |
| [CHANGELOG](../CHANGELOG.md) | 版本历史（含 fork 后改动记录） |
| [CLAUDE.md](../CLAUDE.md) | AI 协作入口：仓库性质、协作约定、文档地图 |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | 面向社区贡献者的开发、验证和提交要求 |
| [SECURITY.md](../SECURITY.md) | 安全漏洞报告与支持版本 |
| [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) | 依赖许可证和发布注意事项 |

## 维护规则

改代码时必须同步更新对应文档，这是硬性约定：

| 改动类型 | 须更新 |
|---|---|
| 新增 / 删除 / 移动源文件 | `dev/modules.md`；影响架构时加 `dev/architecture.md` |
| 构建配置、依赖、xcconfig 变化 | `dev/build.md` |
| 新的用户可见功能 / 交互变化 | `user/usage.md`；易混淆点加 `user/faq.md` |
| 版本发布 / fork 改动 | `../CHANGELOG.md` 顶部追加 |
| 修改指南、代码约定变化 | `dev/contributing-internal.md` |

每次会话有实际改动后，在 [session-log.md](session-log.md) 顶部追加条目；同时在外层 nilo 仓库的 `docs/session-log.md` 追加简要条目。

模块详解只写到「一句话职责 + 关键接口」粒度，避免逐行描述导致文档腐化；细节以源码为准，文档负责导航。
