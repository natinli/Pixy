# 构建与调试

> **验证状态**：本文撰写时本机仅有 Command Line Tools，未装完整 Xcode，构建命令**未在本机实测**；步骤整理自上游 README 与工程勘察。装好 Xcode 后请按本文操作并反馈修正。

## 环境要求

- **Xcode 15.2+**（完整版，非 Command Line Tools；上游 1.7.6 提供 Xcode 26 编译版）
- macOS 11.0+ SDK（随 Xcode 自带）
- 检查：`xcodebuild -version`；若输出 `Command Line Tools` 相关说明只有 CLT，需从 App Store 安装完整 Xcode，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 依赖结构（关键！）

工程引用两个**仓库外的本地 SPM 包**（相对路径），clone 本仓库后直接构建会缺包：

| 依赖 | 引用方式 | 获取 |
|---|---|---|
| SDWebImageWebPCoder 0.14.6 | 远程 SPM（自动解析，连带 SDWebImage、libwebp） | 自动 |
| BTree | 本地包 `../BTree` | [attaswift/BTree](https://github.com/attaswift/BTree) |
| Settings | 本地包 `../Settings` | [sindresorhus/Settings](https://github.com/sindresorhus/Settings) |
| FFmpegKit | 嵌入式 xcframework | 见下节 |

正确的父目录结构：

```
父目录/
├── FlowVision/            # 本仓库（含 FlowVision.xcodeproj）
├── ffmpeg-kit-build/
│   └── bundle-apple-xcframework-macos/
│       └── ffmpegkit.xcframework
├── BTree/                 # clone attaswift/BTree
└── Settings/              # clone sindresorhus/Settings
```

## FFmpegKit 准备

由于上游项目中止和版权原因，预构建二进制已从原仓库移除，备份在：

```
https://github.com/netdcy/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip
```

步骤：

1. 下载 `ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip`（full-gpl 6.0，非 LTS）。
2. 解压到 `父目录/ffmpeg-kit-build/bundle-apple-xcframework-macos/`。
3. 移除 quarantine 属性（否则签名/加载失败）：

```bash
sudo xattr -rd com.apple.quarantine ./ffmpeg-kit-build/bundle-apple-xcframework-macos
```

> 不提供 xcframework 也能构建运行：`FFmpegKit.swift` 用 dlopen 懒加载，缺失时全部 FFmpeg 功能静默降级（部分视频格式不可解码）。

## 构建步骤

1. 按上文结构组织父目录。
2. 用 Xcode 打开 `FlowVision.xcodeproj`（首次打开会自动 resolve SPM 远程包）。
3. 菜单 **Product → Build For → Profiling**（上游推荐的 Release 级构建方式）。
4. **Product → Show Build Folder in Finder** → `Products/Release/FlowVision.app`。

命令行方式（验证用）：

```bash
xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build
```

## xcconfig 说明

- `Base.xcconfig` — 基础构建配置，通过 `#include? "LocalDev.xcconfig"` 可选引入本地覆盖
- `LocalDev.xcconfig.template` — 复制为同目录 `LocalDev.xcconfig`（gitignored）后生效：
  ```
  SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) LOCAL_DEV
  ```
- 启用后代码中可用 `#if LOCAL_DEV`（Debug/Release 都生效）守护开发者专用路径

## 调试

- 三条常驻后台线程（readInfo/thumb/memMonitor）在主线程断点外需用 Xcode 线程视图切换
- 日志：应用内「菜单栏 → 查看 → 操作日志/日志窗口」（`Log.swift`，按级别过滤着色）
- `Log.swift` 的 `log(_:level:)` 是全局日志入口；新增日志用该函数而非 print
- 内存问题关注 `MemoryManagement.swift` 的 footprint 报告与 memMonitorThread 行为

## 常见构建问题

| 现象 | 原因与解决 |
|---|---|
| `../BTree` not found | 本地包缺失，按「依赖结构」布置父目录 |
| xcframework 签名错误 / 加载失败 | quarantine 属性未移除，`xattr -rd` 清理 |
| SPM resolve 慢/失败 | 检查网络；远程包仅 SDWebImageWebPCoder 一条链 |
| 部分视频无法播放（构建成功） | ffmpegkit.xcframework 未就位，属预期降级行为 |
| macOS 26 外观问题 | 上游提供 Xcode 26 编译版本（见 CHANGELOG 1.7.6 说明） |
