# Pixy (FlowVision fork) AI 协作指南

macOS 瀑布流图片查看器，应用展示名为 **Pixy**。本仓库是上游 [netdcy/FlowVision](https://github.com/netdcy/FlowVision) 的 fork，由 [natinli/Pixy](https://github.com/natinli/Pixy) 维护。

## 仓库性质

- **origin**：`https://github.com/natinli/Pixy.git`（fork，日常工作推送到这里）
- **upstream**：`https://github.com/netdcy/FlowVision.git`（原仓库，只 fetch 合并，不推送）
- fork 上的改动（文档、修复、定制）会与上游分叉；上游同步策略见 [docs/dev/contributing-internal.md](docs/dev/contributing-internal.md)。

## 快速了解

| 我想… | 看这里 |
|---|---|
| 了解整体架构和数据流 | [docs/dev/architecture.md](docs/dev/architecture.md) |
| 查某个文件/类的职责 | [docs/dev/modules.md](docs/dev/modules.md) |
| 编译运行 | [docs/dev/build.md](docs/dev/build.md) |
| 改代码前了解约定 | [docs/dev/contributing-internal.md](docs/dev/contributing-internal.md) |
| 版本历史 | [CHANGELOG.md](CHANGELOG.md) |

用户向文档在 [docs/user/](docs/user/installation.md)，文档总入口是 [docs/index.md](docs/index.md)。

## 协作约定

- 技术栈：**纯 AppKit**（无 SwiftUI），Swift + Xcode 工程布置，SPM 依赖 SDWebImage(+WebP)、BTree、Settings，FFmpegKit 以 xcframework dlopen 懒加载。
- 代码组织是「巨型 ViewController + extension 分文件」：改功能先看 `FlowVision/Sources/ViewControllerExtension/` 是否已有对应扩展文件，把改动放进对应 extension，不往 ViewController.swift 本体堆。
- 应用展示名为 **Pixy**（见 pbxproj `INFOPLIST_KEY_CFBundleDisplayName` 与 WindowController/DataModel 中字符串）；目录名、scheme、bundle id 仍为 FlowVision，改动时勿混淆。
- 跨窗口/进程级状态在 `Common/GlobalVariable.swift` 的 `globalVar`；每窗口视图状态在 `ViewController.PublicVar`。不要另造全局单例。
- 排序逻辑唯一真源在 `Common/DataModel.swift` 的 `SortKey` 比较运算符；布局计算唯一真源在 `ViewControllerExtension/LayoutManagement.swift` 的 `recalcLayout`。改这两处必须理解其被全项目依赖的范围。
- **改代码后必须同步更新** `docs/dev/modules.md` 对应文件章节；影响架构时同步 `docs/dev/architecture.md`。
- 每次会话产生实际改动后，在 `docs/session-log.md` 顶部追加条目（标注执行者，写明完成事项与验证结果）。
- 版本变更时在 `CHANGELOG.md` 顶部追加条目。

## 环境注意

- 构建需要完整 Xcode（15.2+）；本机若只有 Command Line Tools 则无法 `xcodebuild`，详见 [docs/dev/build.md](docs/dev/build.md)。
- 工程引用仓库外本地依赖（BTree、Settings、FFmpegKit），统一放在 `~/Developer/pixy-deps/`，clone 后直接构建会缺包，布置方法见 build.md。
