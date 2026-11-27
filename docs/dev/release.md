# 发布流程

本文件说明 Pixy 如何从源码产出可公开下载的 release。构建环境见 [构建与调试](build.md)，发布前的实机验收项见 [首发 Smoke Checklist](release-smoke-checklist.md)。

## 版本号

Pixy 使用**自己的版本线**，从 `0.0.1` 开始，与上游 FlowVision 的 `1.x` 版本号无关。

- 上游 `1.0` ~ `1.7.6` 的 tag 随 fork 一并带到了本仓库，属于历史 tag，**不要复用**。
- Pixy 的 release tag 一律带 `v` 前缀：`v0.0.1`、`v0.1.0`、`v1.0.0`。这与上游的无前缀 tag 天然区分，也是发布工作流的触发条件。
- 版本号写在 `FlowVision.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`（Debug 与 Release 两处），`CURRENT_PROJECT_VERSION` 用作递增的 build 号，只增不减。0.0.2 用了 8 位的发布日期 `20261117`，同日再发的 0.0.3、0.0.4 加了两位序号（`2026111702`、`2026111703`），位数变长之后 8 位日期在数值上反而更小，所以此后一律用 `YYYYMMDDNN`（`NN` 当天第几版，从 `01` 起，如 0.0.5 的 `2026112501`）。这条规则由 `scripts/release-prepare.sh` 自动执行：当前 build 号已是今天的就序号 +1，否则从 `01` 起；当前 build 号不是 10 位数字、日期晚于今天、序号已到 99 时拒绝。
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

先用 `scripts/release-prepare.sh` 做**本地准备**，再按它收尾打印的清单**手动**往下走。脚本只改本地的三个文件，不联网、不 commit、不 push、不打 tag、不构建发布包、不装机、不更新 tap。

```bash
scripts/release-prepare.sh 0.0.7 --dry-run   # 先看计划：只检查并打印，不写任何文件
scripts/release-prepare.sh 0.0.7             # 确认无误后实际改写
```

脚本做的事（也是它拒绝的条件）：

- **前置检查**，任何一项不满足都拒绝并说明原因、不改任何文件：版本号是 `X.Y.Z`（可带前导 `v`）且按数值严格大于 `project.pbxproj` 里 FlowVision 目标当前的 `MARKETING_VERSION`；工作区干净（不干净会列出脏文件，`--allow-dirty` 可放行并提醒只 add 这三个文件）；本地没有 tag `v<版本>`；CHANGELOG 有「## [Fork] 未发布」小节且其下有内容（标题只认围栏代码块之外的，代码块里举例用的同名标题不算）；checklist 有「## 记录」段；CHANGELOG / checklist 里还没有这个版本的小节；三个文件都是 LF 行尾；FlowVision 目标的两个配置里 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 各恰有一行、不带引号且两处值相同，并且 pbxproj 里其它目标 / 配置没有使用同样的值（将来新增要与 App 同步版本的目标时，脚本宁可拒绝也不会只改 App 漏掉它）。检查只看**本地** tag，不联网，远端是否已有同名 tag 它不知道。
- **改文件**：pbxproj 里那 4 行（测试目标 PixyTests 的 `1.0` / `1` 不动，改后回读校验）；CHANGELOG 把「未发布」标题换成 `## [Fork] <日期> — <版本>` 并补一句未签名说明（与 0.0.5、0.0.6 的发版提交一致，上方不再留空的「未发布」）；checklist 在「## 记录」段顶部插入本版骨架（tag、build、日期已填，其余留空待填）。写入先备份、原子替换，任何一步失败、或被 Ctrl-C / kill 打断，都会还原到脚本改动**之前**的内容（不是 git 的 HEAD：`--allow-dirty` 时你原有的手改不会丢）。
- **跑检查**：`check-public-hygiene.sh`、`check-localization.py`；不通过时改动保留、退出码 4，并打印怎么继续：先修复（两个检查是只读的，可以单独重跑）、**不要重跑本脚本**（版本号已经是新的，会因「没有严格大于当前版本」被拒绝）、想放弃就 `git checkout --` 那三个文件，同时照样附上后续手动步骤——检查通过之前不要提交、推送、打 tag。
- **收尾打印手动步骤**：构建验收、填 checklist、只 add 这三个文件提交、推送、打 tag、等工作流（含 runner 容量不足时的重跑）、核对 Release 页、同步 tap、本机升级前确认没在运行。命令以脚本打印的为准，本文不再重复一份，免得两处写法分叉。

```bash
scripts/test-release-prepare.sh              # 脚本自己的回归测试（本机命令，不进 CI）
```

测试在 `git clone` 出来的 `/tmp` 临时副本里覆盖正常发版、`--dry-run`、脏工作区、版本不递增、build 号规则（同日 +1、跨日回到 `01`、日期倒退、序号溢出）、缺小节、tag 已存在、检查失败（含失败后重跑被拒）、改写中途失败与被信号打断时的还原（含脏工作区里的用户手改）、文本边界（CRLF、无末尾换行、代码块里的同名标题、与 App 同值的其它目标）、多种 locale（含 UTF-8 与非 UTF-8）与系统自带 Python 3.9、仓库路径含空格和中文，并校验真实仓库没有被改动。

脚本只支持 macOS（用到 BSD 的 `date -j` 和系统自带的 `plutil`，别的系统会被明确拒绝），并且要兼容自带的 bash 3.2：该版本在 UTF-8 locale 下会把 `$变量名` 后紧跟的全角字符（`$version（`）读成变量名的一部分，报 `unbound variable` 而且退出码是 0；所以脚本里变量后接中文一律写成 `${变量名}`，测试里有静态检查守着。

手动步骤的含义（具体命令见脚本输出）：

1. 构建并验收未签名包（`scripts/release.sh --unsigned`，核对校验和、架构、签名、`spctl` 预期 `rejected`、Info.plist 版本），把结果填进 [release-smoke-checklist.md](release-smoke-checklist.md) 的新骨架。
2. 提交（只 add 脚本改的三个文件）并推送 `main`，打注解 tag `v<版本>` 并推送。
3. 等 Release 工作流；撞上 runner 容量不足就按下一节重跑，tag 不重推。
4. 核对 Release 页（Latest、非 pre-release、附件哈希），把 CI 附件的哈希补进 checklist——CI 重建的包与本地产物哈希不同，两组都要记；有干净用户环境时再下载一次产物验证首次启动（目前没有，checklist 里记为未覆盖）。
5. 同步 Homebrew tap：`scripts/update-cask.sh`（见下文）。
6. 本机用 brew 升级前确认 `/Applications/Pixy.app` 没在运行；升级后第一次启动要用户自己放行。

## Release 也会撞上 runner 配额

发布工作流同样跑在 `macos-15`（arm64）上。GitHub 的 macOS arm64 托管 runner 配额紧张时，作业会排队约 15 分钟后直接失败，注解是 `The job was not acquired by Runner of type hosted`——tag 已经推上去了，但产物没出来。

处理方式：等几分钟后在 Actions 页面点 `Re-run failed jobs`，或命令行 `gh run rerun <run-id> --failed -R natinli/Pixy`。tag 不需要重推，工作流会照常读那个 tag 构建。

**这个失败模式不能靠改工作流消除**：GitHub 不支持给 `runs-on` 配「拿不到就换一个池」的兜底，作业在分配阶段就死了，任何 `if: failure()` 的补偿作业也一样排不上队。工作流能做的只有降低撞上的概率和缩短撞上后的损失——`concurrency` 按 tag 串行，避免两次发布运行同时抢配额并争着 `gh release create`；`timeout-minutes: 40` 避免卡死后占满默认 6 小时；`ci-build.yml` 的 `paths-ignore` 让日常文档推送不再占用同一份配额。

**另一种秒级失败是镜像停用**：作业 1–3 秒内显示 `cancelled`，注解为 `The configuration 'macos-NN-arm64-…' is not supported`。这不是配额问题，重跑也没用——GitHub 下线了该 macOS 镜像。2026-11-17 发 0.0.2 时 `macos-14` 就是这样失效的，`ci-build.yml` 与 `release.yml` 已改为 `macos-15`。tag 触发的运行读的是 tag 所指提交里的工作流文件，所以改完 `runs-on` 后，还没产出 release 的 tag 要移到新提交上才能重新发布。

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
