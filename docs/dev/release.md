# 发布流程

本文件说明 Pixy 如何从源码产出可公开下载的 release。构建环境见 [构建与调试](build.md)，发布前的实机验收项见 [首发 Smoke Checklist](release-smoke-checklist.md)。

## 版本号

Pixy 使用**自己的版本线**，从 `0.0.1` 开始，与上游 FlowVision 的 `1.x` 版本号无关。

- 上游 `1.0` ~ `1.7.6` 的 tag 随 fork 一并带到了本仓库，属于历史 tag，**不要复用**。
- Pixy 的 release tag 一律带 `v` 前缀：`v0.0.1`、`v0.1.0`、`v1.0.0`。这与上游的无前缀 tag 天然区分，也是发布工作流的触发条件。
- 版本号写在 `FlowVision.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`（Debug 与 Release 两处），`CURRENT_PROJECT_VERSION` 用作递增的 build 号。
- 0.x 表示 API 与界面仍在变动、且尚未具备签名分发条件；接入 Developer ID 后发布 `v1.0.0`。

## 两种发布模式

| 模式 | 前提 | 产物 | Gatekeeper |
|---|---|---|---|
| 签名 + 公证 | 付费 Apple Developer Program、Developer ID Application 证书、notarytool 凭据 | `Pixy-<版本>-universal.{zip,dmg}` | 首次启动无拦截，可设为默认图片应用 |
| 未签名版 | 无 | `Pixy-<版本>-universal-unsigned.{zip,dmg}` | 拦截，用户需放行一次 |

macOS 的 Developer ID 证书和公证**都要求付费开发者账号**，没有免费途径。因此 0.x 阶段使用未签名版，把版本、产物、校验和、Release 页面这条链路先跑通；拿到证书后无需改动版本体系，直接切到签名模式。

## 本地发布

签名模式：

```bash
export APPLE_TEAM_ID="你的 Team ID"
export NOTARY_PROFILE="pixy-notary"          # xcrun notarytool store-credentials 创建
scripts/release.sh
```

未签名模式：

```bash
scripts/release.sh --unsigned
```

产物落在 `dist/`（已 gitignore）：

- `Pixy-<版本>-universal{,-unsigned}.zip`
- `Pixy-<版本>-universal{,-unsigned}.dmg`
- `SHA256SUMS.txt`

脚本依次执行：公开仓库卫生检查 → 依赖来源检查 → FFmpegKit bootstrap → 构建 → 打包 →（签名模式）公证与 staple → 校验和清单。任何一步失败都会中止。

## CI 发布

推送 `v*` tag 触发 `.github/workflows/release.yml`。工作流根据 Secret 是否存在自动选模式。

**签名模式需要的 Secrets**（全部配置齐全才生效）：

| Secret | 用途 |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application 证书（.p12）的 base64 |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 导出密码 |
| `KEYCHAIN_PASSWORD` | CI 临时 keychain 的密码，任意随机值 |
| `APPLE_ID` | Apple ID 邮箱 |
| `APPLE_APP_PASSWORD` | App 专用密码（appleid.apple.com 生成） |
| `APPLE_TEAM_ID` | Team ID |

只要 `APPLE_CERTIFICATE_BASE64` 为空，工作流就走未签名模式，标题带「（未签名）」。
**不要**标记 `--prerelease`：GitHub 不把 pre-release 计入仓库的 `latestRelease`，仓库首页侧栏会显示成没有 release。未签名的风险由 release 说明承担。

导出证书：

```bash
security find-identity -v -p codesigning          # 确认有 "Developer ID Application: ..."
# 钥匙串访问 → 导出证书为 .p12 → 然后：
base64 -i developer-id.p12 | pbcopy              # 粘贴到 APPLE_CERTIFICATE_BASE64
```

## 发布步骤

1. 更新 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
2. 在 `CHANGELOG.md` 顶部追加条目。
3. 按 [release-smoke-checklist.md](release-smoke-checklist.md) 完成实机验收，记录 SHA-256、系统版本、签名身份。
4. 提交并推送 `main`。
5. 打 tag 并推送：`git tag -a v0.0.1 -m "Pixy 0.0.1" && git push origin v0.0.1`。
6. 等待工作流完成，核对 Release 页面的产物与本地 `SHA256SUMS.txt`。
7. 下载一次产物，在干净用户环境中验证首次启动。
8. 同步 Homebrew tap：`scripts/update-cask.sh`（见下节）。

## Homebrew 分发

Pixy 通过个人 tap [natinli/homebrew-pixy](https://github.com/natinli/homebrew-pixy) 提供
`brew install --cask natinli/pixy/pixy`。

**进不了官方 `homebrew/cask`**：官方库要求 cask 能过 Homebrew 自己的 Gatekeeper 检查，ad-hoc 签名的 `Pixy.app` 必然失败。`brew audit --cask` 目前有且只有两项失败，都是设计使然：

- `Signature verification failed for Pixy.app` —— 没有 Developer ID，这是未签名版的固有结果；
- `GitHub fork (not canonical repository)` —— `natinli/Pixy` 在 GitHub 意义上确实是 fork。

个人 tap 安装时不跑 audit，所以这两项不阻碍安装。`brew style` 是干净的。

**brew 并不会绕过 Gatekeeper。** 这一点值得说清楚，因为很容易想当然：Homebrew 给下载产物打上了 `com.apple.quarantine`（旧版的 `--no-quarantine` 选项已被移除），实测装好的 app 仍带 `0381;...` 隔离标记，`spctl --assess` 仍是 rejected。所以每个新版本的首次启动**照样要手动放行一次**。tap 省掉的是「下载 → 挂载 DMG → 拖进应用程序」和干净卸载，不是签名这一步。

每个 release 之后同步 cask：

```bash
scripts/update-cask.sh              # 版本号取 MARKETING_VERSION
scripts/update-cask.sh 0.1.0        # 或显式指定
scripts/update-cask.sh --no-push    # 只改本地 tap，不推送
```

脚本从 release 的 `SHA256SUMS.txt` 读校验和，改写 tap 里的 `Casks/pixy.rb` 并提交推送，重复执行是幂等的。tap 默认用 Homebrew 自己克隆的那份（`brew tap natinli/pixy` 之后才有），`PIXY_TAP_DIR` 可指向别的 checkout。

cask 里 `zap trash` 登记的是 `~/Library/Application Support/Pixy`。早期版本这里写的是 `FlowVision`——因为 fork 初期沿用了上游的数据目录名，同时装了上游 FlowVision 的用户执行 `--zap` 会把上游的搜索索引一起删掉。2026-11-04 已把数据目录、日志文件名和 `com.flowvision.*` 内部标识符全部改为 Pixy 自己的，这个副作用随之消失。

改动前留下的 `~/Library/Application Support/FlowVision` 不再被读写，也不在 zap 列表里——如果用户之前跑过旧的 fork 版本，那个目录需要手动删。索引是重建得回来的缓存，不做迁移。

## 已知限制

- 本机目前只有 Apple Development 身份，**没有 Developer ID Application 证书**，`pixy-notary` profile 也不存在。签名与公证链路尚未在真实证书下跑通过。
- 未签名包的默认图片应用体验受限，已在 [安装说明](../user/installation.md) 中明确告知用户。
