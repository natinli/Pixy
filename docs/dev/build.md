# 构建与调试

> 本文面向源码贡献者。公开发布包的签名、公证和归档流程见 `scripts/release.sh`；需要 Developer ID 证书和 Apple 公证凭据。

## 环境要求

- **Xcode 15.2+**（完整版，不是 Command Line Tools）
- macOS 11.0+ SDK（随 Xcode 自带）
- Apple Silicon 或 Intel Mac

检查环境：

```bash
xcodebuild -version
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 依赖结构

Pixy 的公开工程不依赖仓库外的绝对路径。BTree、Settings、SDWebImage 和 WebP coder 通过 `Package.resolved` 锁定的 Swift Package 自动解析。

| 依赖 | 来源 | 备注 |
|---|---|---|
| BTree | `https://github.com/attaswift/BTree.git` | `master` 分支，具体 revision 由 `Package.resolved` 锁定 |
| Settings | `https://github.com/sindresorhus/Settings.git` | 3.1.2 |
| SDWebImage / WebP coder / libwebp | Swift Package 依赖链 | 版本由 `Package.resolved` 锁定 |
| FFmpegKit | `scripts/bootstrap-dependencies.sh` 下载 | 可选开发依赖；正式发布包必须准备 |

首次构建前，建议运行：

```bash
# 图片浏览开发构建，不下载视频运行库
scripts/bootstrap-dependencies.sh --skip-ffmpeg

# 需要视频播放或准备发布包时
scripts/bootstrap-dependencies.sh --with-ffmpeg
```

FFmpegKit 下载包会校验 SHA-256；脚本还会清理 macOS quarantine 属性。下载地址、版本和校验值都记录在脚本中，变更时需要同步 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)。

## 构建步骤

命令行构建使用锁定依赖，并关闭本地开发签名：

```bash
xcodebuild \
  -project FlowVision.xcodeproj \
  -scheme FlowVision \
  -configuration Release \
  -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY='' \
  build
```

也可以用 Xcode 打开 `FlowVision.xcodeproj`，选择 `FlowVision` scheme 后执行 Product → Build。工程的展示名是 Pixy，scheme 和工程文件名仍保留 FlowVision 以便同步上游。

切换「带 FFmpegKit」和「不带 FFmpegKit」的构建时，先执行一次 clean，避免旧的 framework 留在 DerivedData：

```bash
xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release clean
```

带 FFmpegKit 的构建会把 8 个通用 macOS framework 复制到 `Pixy.app/Contents/Frameworks/`；未准备 FFmpegKit 时，脚本会跳过运行库，图片浏览功能仍可编译。

工程使用 Xcode Automatic Signing，与上游 FlowVision 的工程配置保持一致。公开源码不携带任何维护者 Team ID；需要在本机签名时，将自己的 `DEVELOPMENT_TEAM` 写入被 `.gitignore` 忽略的 `LocalDev.xcconfig`，并确保钥匙串里有匹配的 Mac Development 证书。正式分发必须使用 Developer ID Application；CI 的源码构建显式传入 `CODE_SIGNING_ALLOWED=NO`，不会要求证书。

## 公开发布：签名、公证和产物

不要把证书、密码、Team ID 或 keychain 配置写入仓库。具备本机证书时，设置以下环境变量后运行：

```bash
export APPLE_TEAM_ID="你的 Apple Developer Team ID"
export NOTARY_PROFILE="本机 notarytool keychain profile 名称"
scripts/release.sh
```

`release.sh` 会：

1. 下载并校验 FFmpegKit；
2. 创建 Release archive；
3. 使用 `Developer ID Application` 签名并导出 `Pixy.app`；
4. 生成 `.zip` 与 `.dmg`；
5. 分别提交 `.zip` 与 `.dmg` 公证，随后 staple App 和 DMG 公证票据；
6. 运行 `codesign`、`spctl` 并生成 SHA-256 清单。

CI 发布工作流位于 `.github/workflows/release.yml`，只在 `v*` tag 触发。GitHub Secrets 的命名和证书导入步骤见该工作流；本地无需配置 CI Secrets。

## 调试

- 三条常驻后台线程（readInfo/thumb/memMonitor）在主线程断点外需用 Xcode 线程视图切换。
- 日志：应用内「菜单栏 → 查看 → 操作日志/日志窗口」。
- `Log.swift` 的 `log(_:level:)` 是全局日志入口；新增日志使用该函数。
- 内存问题关注 `MemoryManagement.swift` 的 footprint 报告与 memMonitorThread 行为。

## 常见构建问题

| 现象 | 原因与解决 |
|---|---|
| `package ... cannot be accessed` | 清理 DerivedData 后重试，并确认使用完整 Xcode；依赖应来自 Swift Package，而不是本地绝对路径 |
| `There is no XCFramework found at ...` | 运行 `scripts/bootstrap-dependencies.sh --with-ffmpeg`；发布包必须包含 FFmpegKit |
| `Sandbox: ditto deny` | 确认使用仓库当前工程配置；FFmpeg 复制脚本需要关闭该 target 的 User Script Sandboxing |
| `No signing certificate "Developer ID Application" found` | 本地开发使用 `CODE_SIGNING_ALLOWED=NO`；发布请导入 Developer ID 证书后再运行 `scripts/release.sh` |
| Gatekeeper 拦截源码构建 | 源码构建未签名；使用 GitHub Releases 中已签名并完成公证的包 |
| 部分视频无法播放 | FFmpegKit 未准备或运行时加载失败；重新运行 bootstrap，并查看应用日志 |
| macOS 26 外观问题 | 先确认 Xcode 版本和 macOS 版本，再按复现环境提交 issue |
