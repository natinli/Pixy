# 构建与调试

> **验证状态**：已在 Xcode 26.3（macOS 15）实测通过，产物 `Pixy.app` 约 71MB。未配置签名证书时需按「签名」一节传附加参数。

## 环境要求

- **Xcode 15.2+**（完整版，非 Command Line Tools；实测环境 Xcode 26.3）
- macOS 11.0+ SDK（随 Xcode 自带）
- 检查：`xcodebuild -version`；若输出 `Command Line Tools` 相关说明只有 CLT，需从 App Store 安装完整 Xcode，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 依赖结构（关键！）

工程引用**仓库外的本地依赖**（pbxproj 相对路径），clone 本仓库后直接构建会缺包：

| 依赖 | 引用方式 | 获取 |
|---|---|---|
| SDWebImageWebPCoder 0.14.6 | 远程 SPM（自动解析，连带 SDWebImage、libwebp） | 自动 |
| BTree | 本地包 `../../../../Developer/pixy-deps/BTree` | [attaswift/BTree](https://github.com/attaswift/BTree) |
| Settings | 本地包 `../../../../Developer/pixy-deps/Settings` | [sindresorhus/Settings](https://github.com/sindresorhus/Settings) |
| FFmpegKit | 嵌入式 xcframework，同在 pixy-deps | 见下节 |

**依赖统一放在 `~/Developer/pixy-deps/`**（pbxproj 里的相对路径以仓库目录为基准：`projects/Pixy/` → `../../../../` 即用户主目录）。正确结构：

```
~/Developer/pixy-deps/
├── ffmpeg-kit-build/
│   └── bundle-apple-xcframework-macos/
│       ├── ffmpegkit.xcframework
│       └── lib*.xcframework × 7
├── BTree/                 # clone attaswift/BTree
└── Settings/              # clone sindresorhus/Settings
```

若你的仓库不在 `~/Documents/nilo/projects/` 下，需按实际深度调整 pbxproj 中 10 处相对路径（grep `pixy-deps` 即可全部找到）。

## FFmpegKit 准备

由于上游项目中止和版权原因，预构建二进制已从原仓库移除，备份在：

```
https://github.com/netdcy/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip
```

步骤：

1. 下载 `ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip`（full-gpl 6.0，非 LTS）。
2. 解压到 `~/Developer/pixy-deps/ffmpeg-kit-build/bundle-apple-xcframework-macos/`。
3. 移除 quarantine 属性（否则签名/加载失败）：

```bash
sudo xattr -rd com.apple.quarantine ~/Developer/pixy-deps/ffmpeg-kit-build/bundle-apple-xcframework-macos
```

> **注意**：xcframework 是**硬依赖**——工程在 build phase 直接引用全部 8 个 xcframework，缺失时构建直接失败（并非仅运行期降级）；运行期 dlopen 降级只发生在 xcframework 存在但未签名/无法加载的场景。

## 构建步骤

1. 确认依赖已就位（`~/Developer/pixy-deps/` 下有 BTree、Settings、ffmpeg-kit-build）。
2. 用 Xcode 打开 `FlowVision.xcodeproj`（首次打开会自动 resolve SPM 远程包）。
3. 菜单 **Product → Build For → Profiling**（上游推荐的 Release 级构建方式）。
4. **Product → Show Build Folder in Finder** → `Products/Release/Pixy.app`。

命令行方式（实测通过）：

```bash
xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build
```

## 签名

工程已配置正式签名（DEVELOPMENT_TEAM=FPUF4BSUML，bundle id `com.natinli.Pixy`，免费 Personal Team + 自动生成的 Apple Development 证书）。直接构建即可：

```bash
xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build -allowProvisioningUpdates
```

- 证书过期（免费 Team 有效期约 7 天，会自动续）或换机器时重新执行上述命令即可。
- 正式签名让 TCC 隐私授权跨构建生效（ad-hoc 签名每次构建都视为新应用，会反复弹"访问文稿"）。
- 无证书的应急构建（不推荐）：加 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`。

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
| `package ... cannot be accessed` | 本地依赖缺失或路径不符，按「依赖结构」布置到 `~/Developer/pixy-deps/`（clone [BTree](https://github.com/attaswift/BTree)、[Settings](https://github.com/sindresorhus/Settings)），或按仓库实际深度调整 pbxproj 相对路径 |
| `There is no XCFramework found at .../ffmpegkit.xcframework` | FFmpegKit 未布置，是**硬依赖**，按「FFmpegKit 准备」下载解压 |
| `No signing certificate "Mac Development" found` | 无签名证书，按「签名」一节处理（临时构建加 `CODE_SIGNING_ALLOWED=NO`） |
| xcframework 签名错误 / 加载失败 | quarantine 属性未移除，`xattr -rd` 清理 |
| SPM resolve 慢/失败 | 检查网络；远程包仅 SDWebImageWebPCoder 一条链 |
| 部分视频无法播放（构建成功） | ffmpegkit.xcframework 未就位或运行期加载失败，属预期降级行为 |
| macOS 26 外观问题 | 上游提供 Xcode 26 编译版本（见 CHANGELOG 1.7.6 说明） |
