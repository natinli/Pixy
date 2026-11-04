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

不要把证书、密码、Team ID 或 keychain 配置写入仓库。发布脚本有两种模式：

**签名 + 公证（正式发布，需要付费 Apple Developer Program）**

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

**未签名版（没有开发者账号时）**

```bash
scripts/release.sh --unsigned
```

不签名、不公证，只用 ad-hoc 签名（`codesign -s -`）让包在 Apple Silicon 上可以运行，产物名带 `-unsigned` 后缀。Gatekeeper 仍会拦截首次启动，用户需要按 [安装说明](../user/installation.md#当前版本未签名) 放行。

两种模式都会先跑 `check-public-hygiene.sh` 和 `check-dependency-notices.sh`；这两个门禁只检查 `git ls-files` 列出的文件，`.gitignore` 里的 `LocalDev.xcconfig`、`dist/`、`.build/` 不参与检查，但一旦被误提交就会被拦下。

CI 分成两个工作流，区别在于要不要占用 macOS runner：

| 工作流 | runner | 触发 | 跑什么 |
|---|---|---|---|
| `.github/workflows/ci.yml`（CI checks） | `ubuntu-latest` | 每次 push / PR | `check-public-hygiene.sh`、`check-dependency-notices.sh` |
| `.github/workflows/ci-build.yml`（CI build） | `macos-14` | push / PR，但 `paths-ignore` 掉 `docs/**`、`**.md`、`.trellis/**` | bootstrap 依赖 + `xcodebuild` Release 构建 + 上传产物 |

**为什么拆开**：macOS arm64 runner 配额紧张时，作业会排队约 15 分钟后直接以 `The job was not acquired by Runner of type hosted` 失败——这不是代码问题。而本仓库绝大多数提交是文档，没必要为此占用 macOS 配额。卫生检查反而**不能**跳过文档改动（敏感信息最常出现在文档与日志里），所以它单独放在 ubuntu 上，对任何改动都跑。

两个工作流都加了 `concurrency` + `cancel-in-progress`，同一分支连续推送时取消上一轮，避免排队堆积。遇到 runner 配额失败时，等几分钟在 Actions 页面 `Re-run failed jobs` 即可。

发布工作流 `.github/workflows/release.yml` 只在 `v*` tag 触发，根据是否配置了 `APPLE_CERTIFICATE_BASE64` Secret 自动选择签名或未签名模式。完整的发布流程与 Secret 清单见 [发布流程](release.md)。

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
