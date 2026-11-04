# 会话日志

本日志由 Codex、Claude 或人工共同维护。每个会话条目标题必须标注执行者：`[Codex]`、`[Claude]` 或 `[人工]`。**条目按时间倒序排列：最新条目在最顶部。** 项目级日志记录完整细节；外层 nilo 仓库 `docs/session-log.md` 只记简要条目并指向这里。

## 2026-11-01

### [Claude] · 拆分 CI：文档改动不再占用 macOS runner 配额

- TL;DR：今天两次 CI 失败都是 `The job was not acquired by Runner of type hosted`——macOS arm64 runner 配额不足，排队约 15 分钟后放弃，不是代码问题。把检查与构建拆成两个工作流，纯文档提交不再排 macOS 队。

#### 诊断

- 两次失败（15:19、15:54）的注解一致：`The job was not acquired by Runner of type hosted even after multiple attempts`，配套提示 `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times`。近 30 次运行 9 成 5 败，失败里两次是这次的基础设施问题，其余是历史上的真实失败（全角括号变量名、发布工作流配置）。
- 结构性问题两条：`runs-on: macos-14`（arm64，最紧俏的池），以及**没有 concurrency**——连续推送的作业只会排队堆积，互相抢同一份稀缺配额。
- 更没道理的是：这个仓库绝大多数提交是文档，每推一次文档就排一个完整的 macOS 构建。失败的 `docs: 记录上游合并的判定与验证` 就是纯文档提交。

#### 处理

- `ci.yml` 改为「CI checks」，跑在 `ubuntu-latest`：卫生检查 + 依赖来源检查。**任何改动都跑**——敏感信息最常出现在文档与日志里，`docs/session-log.md` 之前就触发过一次隐私路径拦截，这部分不能因为「只改文档」而跳过。
- 新增 `ci-build.yml`（「CI build」，`macos-14`）：bootstrap + `xcodebuild` Release + 上传产物，用 `paths-ignore` 跳过 `docs/**`、`**.md`、`.trellis/**`。
- 两个工作流都加 `concurrency: {group, cancel-in-progress: true}` 与 `timeout-minutes`（检查 10 分钟、构建 45 分钟）。
- `docs/dev/build.md` 新增 CI 章节说明拆分理由与「配额失败怎么处理」，顺带修掉「未签名 Release 会标记 pre-release」这句过时说明；README 中英与 `CLAUDE.md` 的引用同步。

#### 验证

- `ruby -ryaml` 解析两个工作流通过。
- 拆分后首次推送：`CI checks` 45 秒成功（顺带证明两个脚本在 ubuntu 上可跑——只用 `git ls-files` + `grep` + `mktemp -d`，没有 BSD-only 构造），`CI build` 也拿到 runner 并成功。
- 本条 session-log 提交本身是纯文档改动，推上去后应当只触发 `CI checks`、不产生 `CI build`——这就是 `paths-ignore` 是否生效的实测。

### [Claude] · 合入上游 16 个提交（Trellis 任务 11-04-pixy-merge-upstream）

- TL;DR：把上游自 `1.7.6` 起的 16 个提交并入 main（合并提交 `0220d84`），只有 2 个文件真冲突，Pixy 的侧栏/两段式布局/工具栏融合全部保留。任务全程走 Trellis（prd/design/implement + 冲突判定依据预先写入 design.md）。

#### 判定：为什么 `DirTree.swift` 取本地

上游 `614f5da` 在 `treeReLocate` 里修「文件名含 `%` 被当 URL 编码再解一次」，改法是 `removingPercentEncoding ?? $0` + 把外部卷名与编码路径分开。Pixy 把这个函数整块重写成基于 URL 的实现，`normalizedURL` 对以 `/` 开头的路径走 `URL(fileURLWithPath:)`（不解码），对 `file://` 字符串才走 `URL(string:)`（此时解码才是对的），`removingPercentEncoding` 一条都不存在。上游那两个 hunk 全部落在被重写的函数体内，整块取本地。丢掉的不是修复，是被取代的旧实现。

#### 判定：为什么 `EventHandler.swift` 两侧合并

同一行被两边改：Pixy 把 `toggleSidebar` 的展开宽度 `270 → 238`，上游加了 RTL 换算。合成 `setPosition(isRTL ? bounds.width - dividerThickness - 238 : 238, ofDividerAt: 0)`，宽度和 RTL 都保留。

#### 验证

- `xcodebuild -configuration Debug` → `BUILD SUCCEEDED`。
- **逐行校验**（比人眼扫可靠）：统计上游自基点起新增的每一行是否存在于合并后代码，18 个上游改动文件里 16 个全中；`DirTree.swift` 缺 7/8、`EventHandler.swift` 缺 1/11，合计 8 行，全部来自上述两处有意取舍，无意外丢失。
- 数据丢失修复的 4 处 `source does not exist` 守卫在 `FileOperation.swift:491/549/795/853` 全部在位，该文件与上游版本逐字一致。
- 合并后与上游差距 `0 落后 / 38 领先`（`git rev-list --left-right --count upstream/main...HEAD`）。
- 运行时实测：构造 `percent%20name.jpg`、NFC `café`、NFD `café`、`plain.jpg` 四条用例放进同一目录，Debug 构建打开后四张全部正常加载；侧栏分组与两段式圆角布局无回归。
- 验证全程用 Debug 产物 `PixyDbg.app`，未触碰 `/Applications/Pixy.app`。

#### 备注

- 8 个自动合入文件里，`FileSystem.swift`、`LayoutManagement.swift`、`Common.swift` 的上游改动本质是重构（反复解包 `fileDB.db[...]!` 改成 `guard let dirModel`），不是行为修改；Pixy 的改动在别的区域，互不干扰。
- `ViewController.swift` 的上游改动把 `videoView` 变成可选（惰性创建），编译通过说明 Pixy 的装配没被挤出。

### [Claude] · 内部标识符去上游化（数据目录 / 日志 / 队列标签）

- TL;DR：把运行时还在用上游名字的三类标识符改成 Pixy 自己的。用户可见的只有数据目录和日志文件名；目录名、工程名、storyboard 模块字段经查证无害，刻意保留并写进文档。

#### 为什么只改这三类

盘点后把上游痕迹分成三类，只动第一类：

- **有实际后果**：`~/Library/Application Support/FlowVision` 被 `Common.swift`、`Log.swift`、`FinderTag.swift` 三处写死。同时装了上游 FlowVision 时，两个 App 会往同一个目录写 `EnhancedIndex.json` 和 `TempFileForSound.txt`，互相覆盖；cask 的 `--zap` 也会连带删掉上游数据。
- **看似问题实则无害**：storyboard / xib 里的 `customModule="FlowVision"`。查了实际二进制，Swift 模块名已是 `Pixy`（符号前缀 `$s4Pixy`，由 `PRODUCT_NAME` 决定），这些字段带 `customModuleProvider="target"`，运行时按当前 target 解析，是过时元数据。
- **不能动的**：`FlowVision/` 目录与 `FlowVision.xcodeproj`、scheme 名。这是唯一影响上游合并的一类：当前分叉点 `d16f20e`（上游 1.7.6），落后上游 36 个提交但只涉及 7 个文件，追平成本是 3 个冲突。改路径会让上游每个提交都变成路径冲突。

#### 处理

- `GlobalVariable.swift` 新增 `APP_SUPPORT_DIRECTORY_NAME = "Pixy"` 与 `LOG_FILE_NAME = "Pixy.log"`，三处硬编码改为引用常量，避免以后再次分叉。`FinderTag.swift` 里同名局部变量 `flowVisionDir` 一并改成 `appSupportDir`。
- 日志兜底路径 `~/.FlowVision.log` → `~/.Pixy.log`。
- GCD 队列标签 `com.flowvision.EnhancedIndex.{save,scan}`，以及三处 `NSPasteboard` 类型（excludePathRow / customTagRow / favorites.row）改为 `com.natinli.Pixy.*`。后三类只有 Instruments 和跨视图拖拽时可见。
- tap 的 `Casks/pixy.rb` 中 `zap trash` 由 `Application Support/FlowVision` 改为 `Application Support/Pixy`。
- `contributing-internal.md` 补上这批文件，并新增「刻意保留的上游命名」表，把目录名、`customModule`、`FlowVisionTitleFolder` 哨兵值、`netdcy.flowvision.jfif` UTI 各自保留的理由写清楚，避免下次重新讨论。
- `docs/dev/release.md` 里关于 `--zap` 副作用的那段按新事实改写。

#### 未做

- **不做数据迁移**。旧目录不读不写，也不会自动清理。标签索引是重建得回来的缓存，本机上该目录本来就只有 `.DS_Store` 和 0 字节的 `TempFileForSound.txt`，没有索引可迁。代价是跑过旧版 fork 的用户会留下一个孤立目录，已在 release.md 写明。
- **`Info.plist` 的 `netdcy.flowvision.jfif` UTI 未改**。这是上游反向域名命名空间下的标识符，改名为 `com.natinli.Pixy.jfif` 更合适，但要同时改 `LSItemContentTypes` 与 `UTTypeIdentifier` 两处，且会动到 LaunchServices 类型声明，留待单独确认。
- `FileOperation.swift` 的 `FlowVisionPromisedFiles-` 临时目录前缀在 `/tmp` 下不可见，未改。

#### 验证

- `xcodebuild -configuration Debug build` → `BUILD SUCCEEDED`。
- 启动 Debug 构建实测：`~/Library/Application Support/Pixy` 被创建；旧目录 `FlowVision` 的 mtime 仍是 9 月 14 日，确认不再被写入。调试实例随后被关掉。
- `git grep 'com\.flowvision'` 在源码中已无命中。

### [Claude] · 公开仓库设置收尾

- TL;DR：关掉空的 Wiki 与 Projects，开 Discussions，清掉指向自身的 Homepage，补齐 security/Dependabot 告警，并把这套设置写进 `contributing-internal.md`，避免以后被改回去。

#### 处理

- `has_wiki` 关：文档全在 `docs/`，wiki 从来没有内容，等于侧栏多一个空入口，而且和仓库内容容易分叉。全仓无任何指向 wiki 的链接，关掉不影响现有文档。
- `has_projects` 关：没用它排期。
- `has_discussions` 开：0 issue 的仓库，讨论区比 issue 门槛低。开启后默认分类（Announcements / General / Ideas / Polls / Q&A / Show and tell）已自动生成，确认可用。
- `homepage` 清空：原值就是 `https://github.com/natinli/Pixy` 本身，侧栏等于重复显示同一个链接。
- `delete_branch_on_merge`、`allow_update_branch` 开：单人仓库，合入后留分支只会堆积；开 update branch 让外部 PR 能一键跟上 `main`。
- `dependabot_security_updates` 开：`Package.resolved` 里的 SPM 依赖有漏洞时自动提 PR。
- `secret_scanning` 与 `secret_scanning_push_protection` 本就是开着的（公开仓库免费），与 `scripts/check-public-hygiene.sh` 形成双重兜底。
- 设置清单与理由写成 `contributing-internal.md` 的「GitHub 仓库设置」表。

#### 未完成

- `secret_scanning_validity_checks` 仍是 disabled。个人账号仓库上开不了，PATCH 返回 200 但值不变，不影响 secret scanning 本身。
- **Social preview 仍需手动上传**：GitHub 没有对应 API，只能在 Settings → Social preview 传 `docs/social-preview.png`。

### [Claude] · 新增个人 Homebrew tap 分发

- TL;DR：建了 `natinli/homebrew-pixy`，`brew install --cask natinli/pixy/pixy` 可用。原先的假设「brew 用 curl 下载所以不带隔离标记、能免掉 Gatekeeper 放行」被实测推翻，文档按实测结论改写。

#### 关键更正

- 最初的理由是「brew 用 curl 下载，不写 `com.apple.quarantine`，装完直接能开」。实测不成立：Homebrew 7.0.7 会给下载产物打隔离标记，装好的 `Pixy.app` 上 `xattr` 读到的仍是 `0381;6aeb3c97;;8AB73E39-…`，`spctl --assess` 仍是 `rejected`。`--no-quarantine` 选项在这个版本里已经没有。
- 结论如实写进 README、安装文档和 release.md：tap 省掉的是「下载 → 挂载 DMG → 拖拽」和干净卸载，**不是**签名这一步；每个新版本首次启动仍要放行一次。

#### 处理

- 新建 `natinli/homebrew-pixy`，`Casks/pixy.rb` 锁 `0.0.1` + sha256 `5bdfb42f…`，`livecheck` 用 `:github_latest`，`zap trash` 登记偏好、缓存、saved state 和 `~/Library/Application Support/FlowVision`。
- 踩到两条 Homebrew 7 的废弃告警并修掉：`verified:` 参数已废弃（改用默认 URL 校验）、`depends_on macos: ">= :big_sur"` 的字符串比较已废弃（改为 `depends_on :macos`）。
- `brew style` 干净。`brew audit --cask` 有两项**固有**失败且无法修：`Signature verification failed`（没有 Developer ID）、`GitHub fork (not canonical repository)`（`natinli/Pixy` 确实是 fork）。个人 tap 安装时不跑 audit。
- 新增 `scripts/update-cask.sh`：读 `SHA256SUMS.txt` 的校验和改写 cask 并提交推送，幂等，`--no-push` 可只改本地。`docs/dev/release.md` 增加 Homebrew 分发一节，发布步骤补第 8 步。
- 全仓把「未签名预发布」统一为「未签名」：`--prerelease` 已经移除，继续叫预发布自相矛盾。顺带修掉 `faq.md`、`build.md` 里指向 `#当前版本是未签名预发布` 的两个失效锚点。

#### 代价与被规避的风险

- 实测时用 `HOMEBREW_CASK_OPTS=--appdir=/tmp/...` 把 cask 装到临时目录，**没有动** `/Applications/Pixy.app`（用户正在用的那份）和 `~/Library` 下的真实偏好。安装后的 `/Applications` 与用户偏好均未改动。
- 没有执行 `brew uninstall --zap`：cask 的 zap 列表含 `~/Library/Application Support/FlowVision`，本机跑一次会删掉真实数据。zap 路径按磁盘实际存在的目录确定，未做删除验证。

#### 验证

- `brew install --cask`（显式全名与已 tap 后只写 `pixy` 两种路径）均成功，无告警。
- 装出的 app `CFBundleIdentifier` = `com.natinli.Pixy`，`CFBundleShortVersionString` = `0.0.1`。
- Homebrew 缓存里的 zip sha256 = `5bdfb42f…`，与 `SHA256SUMS.txt` 一致。
- `brew livecheck pixy` 输出 `0.0.1 ==> 0.0.1`；`brew style` 无 offense。
- `update-cask.sh` 在临时 clone 上验证了「版本/校验和写错 → 脚本改写并生成提交」的完整路径，以及对已同步状态的幂等跳过。

### [Claude] · v0.0.1 产物就地重建，并去掉 pre-release 标记

- TL;DR：用户要求版本号保持 `0.0.1`。删除旧 release 与 tag，在同一 tag 名上按当前 `main` 重建产物并重新发布，同时修掉「仓库首页看不到 release」的问题。

#### 问题

- 旧 `v0.0.1` 的 tag 指向 `3ef6356`，落后 `main` 5 个提交。下载到的包里「官方网站」仍指向 `flowvision.app`、版权仍是 `© 2024 netdcy`。
- 旧 release 标了 `--prerelease`。GitHub 不把 pre-release 计入仓库的 `latestRelease`，所以仓库首页侧栏显示成没有 release。

#### 处理

- `MARKETING_VERSION` 保持 `0.0.1`，`CURRENT_PROJECT_VERSION` 保持 `20261101`；把整理内容写进 CHANGELOG 的同一个 `0.0.1` 条目下（新增「2026-11-04 重新构建」小节）。
- 发布工作流去掉 `--prerelease`，标题改为「Pixy 0.0.1（未签名）」；未签名的风险改由 release 说明承担。`docs/dev/release.md` 记录了这条副作用。
- `gh release delete v0.0.1 --cleanup-tag` 删除旧 release 与远端 tag，本地重新在 `f1dba5f` 打同名 tag 并推送，CI 重新构建发布。

#### 验证（从 Release 页面重新下载后核对）

- `shasum -a 256 -c SHA256SUMS.txt`：zip 与 dmg 均 OK。
- `CFBundleShortVersionString` = `0.0.1`，`CFBundleVersion` = `20261101`。
- `NSHumanReadableCopyright` = `© 2024 netdcy · Pixy fork © 2026 natinli` —— 证明产物确实来自整理后的代码，不是旧 tag。
- 二进制字符串：`flowvision.app` 出现 0 次，`github.com/natinli/Pixy` 出现 4 次。
- `codesign -dv`：`Signature=adhoc`、`TeamIdentifier=not set`；`lipo -archs`：`x86_64 arm64`。
- Release 状态：`isPrerelease=false`，`latestRelease` 已指向它。

#### 已知影响

- 重写了一个已公开的 tag。该 tag 创建于 1 天前、下载量为 0，且用户明确要求沿用 `0.0.1`，因此选择就地替换而不是升版本号。
- release 说明与 README 现在一致指向「未签名」；`docs/social-preview.png` 已备好，但 GitHub 不提供上传 API，需在仓库 Settings → Social preview 手动上传。

### [Claude] · 开源前整理：清理、文档重整、README 与实机截图

- TL;DR：把仓库从「fork 过来改了 UI」整理成规范的二次开发公开项目：删掉上游遗留与死文件、修正会让新贡献者踩坑的过时文档、重写中英文 README、用当前代码重拍界面图。

#### ✅ 完成

**清理（提交 `06c8e7a`）**

- 删除 `docs/preview.jpg`：全仓库零引用。
- 删除 `.github/funding.yml`：内容是 `buy_me_a_coffee: netdcyn`，即**上游作者**的收款账户，fork 上保留会把捐赠导向上游。
- 删除 `.vscode/settings.json`：唯一内容是 `problems.visibility: false`，对贡献者有害。

**代码指向修正（提交 `e179db1`）**

- `OFFICIAL_WEBSITE`：`https://flowvision.app` → `https://github.com/natinli/Pixy`
- `FINDER_TAG_LEARN_MORE_URL`：`https://flowvision.app/tag` → 仓库内 `docs/user/usage.md`（上游那个专门页面 Pixy 没有等价物）
- `INFOPLIST_KEY_NSHumanReadableCopyright`：`© 2024 netdcy` → `© 2024 netdcy · Pixy fork © 2026 natinli`
- 核对两个常量的用途：只在 `AppDelegate.swift:1257` 和 `Tagging.swift:183` 用于 `open(url)`，不参与布局，无排版风险。

**文档重整（提交 `4815708`）**

- `docs/dev/modules.md`：文件数 53 → 56（实测 `Sources/**.swift`）；补 `WindowController+ToolbarBlend.swift`（133 行，大图模式透明标题栏 + 底部标题胶囊）。
- `docs/dev/modules.md` + `docs/dev/architecture.md`：删除「BTree、Settings 是仓库外本地包 `../BTree`、`../Settings`」——实际早已改为公开 Swift Package 并由 `Package.resolved` 锁定，按旧描述搭建环境会直接失败。
- `docs/dev/architecture.md`：Swift 行数改为约 3.36 万（实测 33,632），模块树补两个 fork 新增文件。
- `SECURITY.md`：发布安全段改为「当前未签名预发布 + 未来签名后的目标」，不再声称已公证。
- `docs/dev/contributing-internal.md`：删掉「fork 以文档体系 + 少量定制为边界，尽量不改上游源码」的过时定位，补上相对上游实际分叉的 13 个文件清单（DataModel、DirTree、CustomOutlineView 系、SidebarCard、ToolbarBlend 等），供上游合并时核对。
- `docs/index.md`：新增「按任务找文档」映射表（改侧栏 / 改布局 / 改大图 / 发版 …）。
- `docs/user/installation.md`：新增「关于 Homebrew」——Pixy 没有 cask，`brew install flowvision` 装的是上游原版、不含 Pixy 改动。
- `docs/user/usage.md`：补大图模式透明标题栏与底部「文件名 · 张数」胶囊。

**README（提交 `4815708`）**

- 中英文重写：以 Pixy 自身定位为主语，上游血缘移到「致谢」节；功能列表按导航/浏览/整理/性能/界面分组；补充徽章、目录结构、开发要求。
- 安装段如实标注「当前未签名预发布」，给出图形界面与 `xattr` 两种放行方式，并明确「不建议设为默认图片应用」。

**仓库元信息**

- description 由上游原句改为 Pixy 定位；homepage 由 `flowvision.app` 改为仓库地址；新增 7 个 topics（macos / appkit / swift / image-viewer / photo-management / video-player / finder）；启用 Issues。

**截图**

- 用脚本生成 24 张合成渐变图作为示例图库（不涉及任何真实照片），启动当前构建逐个截图，浅色/深色各一张，`screencapture -l <windowid>` 只抓目标窗口。
- 替换 `docs/preview_1.png`（深色）与 `docs/preview_2.png`（浅色），统一为 1234×734。
- 截图结束后退出测试实例、删除 `com.natinli.Pixy` 的临时 appearance 设置、清理示例图库。用户自用的 `/Applications/Pixy.app` 全程未触碰。

#### 验证

- `xcodebuild` Release 构建 `BUILD SUCCEEDED`（含上述源码改动）。
- `scripts/check-public-hygiene.sh`、`scripts/check-dependency-notices.sh` 均通过（在干净 PATH 下运行，确认不依赖 rg）。
- 全部 Markdown 相对链接检查：0 个断链。

#### 待跟进

- 本次未改动已发布的 `v0.0.1` Release；这些整理与截图变更需等下一个 tag 才会体现在发布包和仓库首页。
- 深色截图依赖应用自身的 appearance 设置，截完已删除该 defaults 键。

## 2026-11-01

### [Claude] · 建立 0.0.1 发布线，修复发布门禁 fail-open

- TL;DR：Pixy 从自己的 `0.0.1` 起建立版本线，新增免证书的未签名发布路径，并修掉一个会让敏感信息扫描静默失效的门禁漏洞。

#### ✅ 完成

**版本线**

- `MARKETING_VERSION` 由 `1.0.0` 改为 `0.0.1`（Debug/Release 两处），`CURRENT_PROJECT_VERSION` 由 `20261003` 改为 `20261101`。
- 决定：Pixy 用自有版本线，不复用上游 `1.0`~`1.7.6` 的历史 tag；release tag 一律带 `v` 前缀，与上游无前缀 tag 天然区分。规则写入新建的 [docs/dev/release.md](dev/release.md)。

**发布脚本**

- `scripts/release.sh` 增加 `--unsigned` 模式：不签名、不公证，用 ad-hoc 签名（`codesign --force --deep --sign -`）保证 Apple Silicon 可运行，产物名带 `-unsigned` 后缀与签名包区分。默认模式仍是签名 + 公证。
- 修掉一处真实 bug：收尾 `echo "版本：$VERSION（build …）"` 里全角括号被 shell 当作变量名的一部分，在 `set -u` 下报 `VERSION?: unbound variable`。改为 `${VERSION}` 显式界定。

**发布门禁（重要）**

- `scripts/check-public-hygiene.sh` 原实现调用 `rg`，但**本机和 GitHub Actions 的 macos-14 runner 都没有预装 ripgrep**；在 `set -eu` 下 `if rg ...` 失败被当作「未命中」分支，整个敏感信息扫描被静默跳过并打印「检查通过」——这是 fail-open，发布门禁形同虚设。
- 重写为只用系统自带工具：基于 `git ls-files` 逐文件 `grep`，显式区分 grep 的 0（命中）/1（未命中）/>1（出错）退出码，出错即中止。不依赖 `xargs` 退出码约定（BSD 与 GNU 对 1–125 的映射不同，实测 BSD 下会误判）。
- 改为只检查被跟踪文件：`.gitignore` 的 `LocalDev.xcconfig`（含真实 Team ID）、`dist/`、`.build/` 不再造成本地误报，但一旦误提交仍会被拦下。
- `scripts/check-dependency-notices.sh` 同样去掉 `rg` 依赖。

**CI**

- `.github/workflows/release.yml` 改为按 `APPLE_CERTIFICATE_BASE64` 是否存在自动选模式：有则签名 + 公证，无则 `--unsigned` 并发 pre-release 且附未签名说明。避免推 tag 后工作流直接失败。

#### 验证

- 门禁**做了破坏性验证**（在 `/tmp` 副本中，不污染仓库）：放入一个含本机用户主目录绝对路径的文件 → 退出码 1 并报出行号；`git add -f` 一个 `.dmg` → 退出码 1 报「发布产物」。确认修复后真的会拦截，而不是又一次静默通过。
- `sh -n` 通过三个脚本；`ruby -ryaml` 解析 `release.yml`、`ci.yml` 通过。
- `scripts/release.sh --unsigned` 全流程跑通，`FINAL_EXIT=0`：`BUILD SUCCEEDED` → ad-hoc 签名 → 打包 → 校验和。
- 产物核查：`CFBundleShortVersionString` = `0.0.1`、`CFBundleVersion` = `20261101`；`lipo -archs` = `x86_64 arm64`；`Contents/Frameworks` 含 ffmpegkit 与 7 个 libav* framework 及 libswift_Concurrency.dylib；`codesign -dv` = `Signature=adhoc`、`TeamIdentifier=not set`；`codesign --verify --deep --strict` 通过；DMG 可挂载，内含 `Pixy.app` + `/Applications` 软链；`shasum -a 256 -c` 两个产物均 OK。
- 确认未公证符合预期：`spctl --assess` = `rejected`，`stapler validate` 报无票据。已在 checklist 中明确这是预期结果，防止后续误宣称已公证。

#### 文档影响

- 新建 `docs/dev/release.md`（版本号规则、两种模式、CI Secrets 清单、打 tag 步骤、已知限制）。
- `README.md` / `README_zh.md` 安装节改为如实说明「当前未签名预发布」，删除「正式发布包已签名公证」这一与现状不符的承诺。
- `docs/user/installation.md` 增加放行步骤（系统设置路径与 `xattr` 两种方式）、「每个新版本需重新放行」、以及「未签名时暂不建议设为默认图片应用」。
- `docs/user/faq.md` 拆分未签名/已签名两种情形的报错处理，新增「双击图片无法用 Pixy 打开」条目。
- `docs/dev/build.md` 补两种发布模式说明；`docs/dev/release-smoke-checklist.md` 新增未签名预发布验收段并记录 0.0.1；`docs/index.md`、`CLAUDE.md`、`CHANGELOG.md` 同步。

#### 发布结果

- 已推送 `main`（`25d8c14..3ef6356`），打并推送 tag `v0.0.1`，CI 自动构建并发布：
  <https://github.com/natinli/Pixy/releases/tag/v0.0.1>
- Release 状态：`isPrerelease=true`，产物 3 个 —— `Pixy-0.0.1-universal-unsigned.dmg`（35.9 MB）、`.zip`（31.0 MB）、`SHA256SUMS.txt`。
- 工作流 `Release` 与 `CI` 均 success（Release 2m31s，CI 3m5s，macos-14 runner）。
- 从 Release 重新下载产物复核：版本 `0.0.1`/`20261101`、`lipo -archs` = `x86_64 arm64`、9 个 Frameworks 条目、`Signature=adhoc`、`TeamIdentifier=not set`、`codesign --verify --deep --strict` 通过、`shasum -a 256 -c` 两个产物均 OK。CI 产物与本地构建结论一致。

#### 过程中踩到并修掉的坑

- **门禁抓到了我自己**：第一次推 tag 后 `CI` 与 `Release` 都在 9–12 秒内失败，原因是 `check-public-hygiene.sh` 扫到了本文件里写的本机绝对路径示例。这反过来证明 fail-open 修复真的生效了（旧版本会静默通过）。已把示例改成文字描述。
- **同一个全角括号 bug 踩了两次**：workflow 里 `--title "Pixy $VERSION（未签名预发布）"` 与 `release.sh` 收尾 echo 是同一问题——全角括号的字节被 shell 并入变量名。首次发布的 Release 标题因此被写成 `Pixy ��未签名预发布）`，已用 `gh release edit` 修正，并把 workflow 改为 `${VERSION}`。
- **操作失误**：验证 `gh release create` 的参数互斥性时，命令被直接执行，在公开仓库创建了 `__nonexistent_tag__` 的 release 和 tag。已用 `gh release delete --cleanup-tag` 完全删除并核对（release 列表为空、tag 恢复为 39 个上游历史 tag）。教训：`gh release create` 没有 dry-run，验证参数不能用真实仓库当沙箱。

#### 待跟进

- 本机仍只有 Apple Development 身份，**没有 Developer ID Application 证书**，`pixy-notary` profile 不存在；签名 + 公证链路尚未在真实证书下跑通过。用户已决定暂不购买付费账号，0.x 阶段维持未签名预发布。
- GitHub 仓库 `natinli/Pixy` 目前**没有任何 Secret**，发布工作流走的是未签名分支。
- 干净用户环境的首次启动放行验证、Intel Mac 实机验证未做（无干净环境/无 Intel 机）。
- Homebrew 分发未做：上游 FlowVision 走官方 homebrew-cask（`brew install flowvision`），但该 cask 能进官方仓库的前提是**已签名公证 + 足够 notable**。Pixy 当前未签名且 0 star，短期内只能考虑自建 tap。

## 2026-10-13

### [Claude] · Finder 风格侧栏验收确认与任务归档

- TL;DR：用户确认 Finder 风格侧栏实际效果可用，Trellis 任务 `10-01-pixy-sidebar-design` 收尾归档。

#### ✅ 完成

- 用户现场确认侧栏效果，Trellis 任务 `10-01-pixy-sidebar-design`（P2，规划基线 `bcfa8db`）标记完成并归档。
- 核对实现侧：工作树干净、无未推送提交；侧栏相关代码落在 `8e69a07`（完整复刻）、`79d2856`（导航行为）、`25d8c14`（开源发布）三个提交。
- 清理本次任务在 `nilo/temp/` 下的构建与验收产物，释放约 4.9GB（5 个 DerivedData、2 个 release 构建、`PixySidebarReview.app`、`Pixy-2026-10-02.zip`、构建日志及一次性编辑脚本）。

#### 验证

- 实现侧静态核对：`projects/Pixy` 工作树干净，`git status` 无改动，`origin/main` 与 HEAD 一致。
- 视觉与交互验收以用户实机确认为准：浅色窗口此前已与 Finder 实际窗口截图对照；深色、失焦、RTL、分栏缩放及 AC2–AC5 的完整交互清单（三级展开、重复入口唯一选中、跨窗口收藏同步、键盘/滚动/拖放、外部打开跟随）未逐条留档，以用户“已经可以了”的确认作为验收结论。

#### 文档影响

- 本轮未改动 Pixy 代码，`docs/dev/modules.md`、`docs/dev/architecture.md`、`docs/user/usage.md`、`CHANGELOG.md` 沿用前序提交已同步的版本，无新增回写。

## 2026-10-03

### [Codex] · Pixy GitHub 开源发布准备

- TL;DR：把 Pixy 的构建、依赖、签名公证、安装和社区入口整理为公开可复现流程。

#### ✅ 完成

- BTree、Settings 改为公开 Swift Package，并由 `Package.resolved` 固定解析结果；移除工程中开发机绝对路径。
- 新增 FFmpegKit bootstrap 与复制脚本，固定下载地址、版本和 SHA-256；带视频运行库的通用 arm64/x86_64 Release 构建通过，8 个 framework 均进入 `Pixy.app`。
- 移除公开工程中的个人 Team ID 和默认开发签名，新增 `release.sh` 完成 Developer ID archive/export、DMG/ZIP、公证、staple、spctl 与 checksum；新增 PR/推送 CI 与 tag 发布 workflow。
- 更新公开 README、安装、构建、FAQ 和第三方许可证说明；新增 CONTRIBUTING、SECURITY、CODE_OF_CONDUCT 与首发 smoke checklist。
- 补齐 `NSAppleEventsUsageDescription`，保留图片/视频 UTI 声明并移除未使用的 Photos Library entitlement，安装文档明确默认图片应用依赖签名公证 release。

#### 验证

- `xcodebuild -list -project FlowVision.xcodeproj` 通过。
- Release 无签名构建通过；带 FFmpegKit 的干净 Release 构建通过，产物为通用 arm64/x86_64。
- `sh -n`、`plutil -lint`、`git diff --check`、`scripts/check-public-hygiene.sh` 通过。
- 全新临时 clone 等价副本 `/tmp/pixy-fresh-RrUtrP` 重新解析 `Package.resolved`，执行无 FFmpegKit 的 Release clean/build，输出 `BUILD SUCCEEDED`；依赖来源与公开卫生检查通过。构建日志移出副本后再执行卫生检查，避免把本机环境变量写入验证树。
- 复核发布脚本后改为分别提交 ZIP 与 DMG 公证，再执行 App/DMG staple，确保两种公开分发格式都有对应的公证记录。
- 只读核对 `natinli/Pixy`：仓库已公开、默认分支为 `main`、GPL-3.0；Issues 当前关闭，远端暂无 `v*` tag/Release，`main` 未启用分支保护。由于本轮未 push，新增 workflow 仍只存在本地。
- 对照上游 `netdcy/FlowVision` 的 `main` 与 1.7.6 Release：上游工程使用 Automatic Signing，实际包为 Developer ID 签名、已公证并 stapled。Pixy 工程恢复同样的 Automatic Signing 方式，Team ID 仅在本机/CI 注入，发布脚本改为 Automatic + Developer ID。
- 本机只发现 Apple Development 身份，没有 Developer ID Application 证书；`pixy-notary` 公证 profile 不存在。无签名 Release 构建已通过，真实公证包留待配置发布证书和凭据后验证。
- 用本机 Apple Development 身份尝试 Automatic Signing 失败：Xcode 对 macOS target 需要匹配的 `Mac Development` 证书，依赖包和 Pixy 均报告证书类型不匹配；未生成临时签名 App。
- 已创建被 `.gitignore` 忽略的 `LocalDev.xcconfig`，注入当前开发团队供 Xcode Automatic Signing 使用；无签名 CI 参数构建再次通过。该本机文件不进入公开仓库。
- Xcode Apple Accounts 现场确认当前只有 Personal Team，Manage Certificates 只提供 Apple Development，没有 Developer ID Application；无法在本机补齐上游 Release 所需的 Developer ID 公证链路。

#### 文档影响

- 已同步 `docs/dev/build.md`、`docs/dev/release-smoke-checklist.md`、`docs/user/installation.md`、`docs/user/faq.md`、`docs/index.md`、`CHANGELOG.md`、`THIRD_PARTY_NOTICES.md` 及仓库级贡献/安全文档。
- Developer ID 证书、notarytool 凭据、GitHub Secrets、实际公证包和 Finder 默认应用现场验收需要在发布机/仓库设置完成后补测。

## 2026-10-02

### [Codex] · Pixy 侧栏精简与 Finder 式目录展开

- TL;DR：侧栏移除不常用系统入口和 TimeMachine，默认不随当前目录自动展开层级，保留披露箭头供手动浏览。

#### ✅ 完成

- 个人收藏保留桌面、文稿、下载、用户主目录及已有自定义收藏；移除隔空投送、最近使用和应用程序。
- iCloud 分组只保留 iCloud 云盘；位置分组过滤共享、TimeMachine，仅保留本机、其他挂载卷和 OneDrive。
- `dirTreeAutoExpand` 默认关闭；侧栏目录点击只切换内容并选中目标，子目录通过披露箭头按需展开，避免当前路径长期驻留在侧栏。

#### 验证

- Release 构建通过；新进程 AX 检查确认入口列表已移除指定项目，启动时目录行保持折叠，点击桌面和子目录可正常访问，披露箭头可手动展开直接子目录。

#### 文档影响

- 已同步更新 `docs/user/usage.md`、`docs/dev/modules.md`、`docs/dev/architecture.md` 与 `CHANGELOG.md`。

### [Codex] · Pixy 侧栏选中态跟随导航入口

- TL;DR：侧栏点击保留 Finder 式灰色选中，内容区进入子文件夹后清除侧栏选中态。

#### ✅ 完成

- 在导航状态机中区分侧栏发起的目录切换与内容区／路径栏等其他入口。
- 非侧栏入口进入新目录后清除 `NSOutlineView` 选中行和 `activeSidebarEntryID`，避免灰色高亮停留在旧入口。

#### 验证

- Release 构建通过；新进程 AX 状态验证了点击桌面保留选中，内容区打开 `2025.9.20原图` 后侧栏选中态消失，截图确认左栏不再显示灰色背景。

### [Codex] · Pixy 滚动、目录层级与收起布局修复

- TL;DR：修复工具栏与缩略图滚动区重叠、目录点击后子分支长期驻留、侧栏收起后主区域留白三个问题。

#### ✅ 完成

- 主内容滚动区根据内容面板与 `window.contentLayoutRect` 的实时几何重设高度，滚动内容始终从工具栏下沿开始。
- 侧栏点击目录时展开到目标这一层，保留直接子目录入口；无关临时分支同步折叠。
- 侧栏收起时将分栏宽度置零并强制执行一次布局，内容面板填满可用宽度；重新展开恢复 238pt。

#### 验证

- Release 构建通过（仅保留既有编译警告），`git diff --check` 通过。
- 现场 AX/截图复核：滚动到中后段时内容仍位于工具栏下方；收起／重新展开侧栏时内容宽度即时重排，未出现右侧留白。
- 目录层级逻辑已按 `treeReLocate` 的祖先关系与折叠路径核对；目标层保留直接子目录入口，未对用户实际桌面目录执行全量扫描。

#### 文档影响

- 已同步更新 `docs/user/usage.md`、`docs/dev/modules.md`、`docs/dev/architecture.md` 与 `CHANGELOG.md`。

### [Codex] · Finder 侧栏现场复刻校准

- TL;DR：按本机 Finder 窗口重新校准侧栏顺序、入口和视觉密度，已补齐隔空投送、最近使用、应用程序、iCloud 云盘、共享、本机、挂载磁盘与 OneDrive；新 Release 包截图与 Finder 参考的分组布局一致。

#### ✅ 完成

- 个人收藏顺序与 Finder 对齐：隔空投送、最近使用、应用程序、桌面、文稿、下载、用户主目录；既有自定义收藏继续从原配置投影。
- 增加 iCloud 分组（iCloud 云盘、共享），位置分组按本机、Minimalist、TimeMachine、OneDrive 的 Finder 现场顺序投影；不同入口使用对应的系统线性图标。
- 固定入口复用 macOS CoreTypes 侧栏图标资源；桌面使用 Finder 同形的底部内嵌矩形，Mac mini 使用 `macmini` 四指示点图标，外置磁盘行补齐 Finder 推出按钮。
- OneDrive 位置行补充 Finder 同形的模板字形资源，并沿用系统动态颜色渲染，避免使用普通 `cloud` 符号造成品牌图标差异。
- 现场尺寸保持 Finder 基线：侧栏 238pt、正文 13pt/28pt、分组标题 11pt、16pt 图标、选择背景内缩与圆角、动态 sidebar 材质及隐藏但可滚动的滚动条。
- 启动路径定位只沿目标路径创建直接子节点，不再为侧栏预扫描用户主目录或 File Provider 后代目录。
- Release 双架构构建通过；25 条路径、虚拟入口和节点可选性断言通过；`git diff --check` 与本地化 JSON 校验通过。
- 已用新构建窗口截图与 Finder 实际窗口截图完成浅色视觉对照，截图证据保存在 `/tmp/pixy-current-window.png` 与 `/tmp/finder-window-current.png`。

#### 验证边界

- 当前 macOS 处于锁屏状态，Accessibility AX 树无法读取；窗口级截图已完成视觉比对，未将锁屏状态下的 AX 结果记作通过。深色、RTL、拖放和跨窗口交互仍需解锁后补做现场复核。

## 2026-10-01

### [Codex] · Finder 风格侧栏实现

- TL;DR：侧栏数据源、按真实路径跟随与收藏跨窗口刷新已实现；后续现场校准补充了 Finder 的 iCloud 与系统入口。

#### ✅ 完成

- 系统快捷入口、用户收藏、实际挂载卷和标签统一由共享树源构建；节点角色与入口身份隔离标题、分隔线及文件操作。
- 目录跟随按 URL 路径组件匹配，优先当前已定位的分支、最深收藏祖先、位置，启动恢复默认匹配最具体的快捷入口；虚拟标签域与真实目录匹配隔离，标签收藏复用标签角色；刷新按稳定身份恢复展开与选中。
- 侧栏上下键与鼠标共享可选性判断，跨组跳过标题、分隔线和失效入口；用户点击／展开建立分支后，成功定位才更新分支标识，启动保留空值并折叠无关临时分支，侧栏标签圆点采用系统语义色，「所有标签」使用双环图标。
- 收藏状态源发送主线程通知，各窗口订阅；原 UserDefaults 存储格式保持一致。
- plain 样式统一行几何，标题无箭头、根图标中心 25pt、正文起点 40pt，列宽固定为 viewport，侧栏初始宽 238pt；目录内容按 window.contentLayoutRect 避让工具栏，标题与首行间距 23pt、上一组末行与标题间距 37pt；28pt 正文行、蓝色线性图标、动态灰底选中、系统动态材质及 RTL 约束已接入；8pt 内容边界继续共享背景。
- Release 双架构构建通过（含最终增量构建）；从实际模型函数提取的 20 条路径规范化／祖先关系／虚拟域／节点可选性与入口排名断言通过，git diff --check 通过。
- 文档影响检查已完成：模块、架构、使用说明、CHANGELOG 回写到项目真源。

#### 待跟进

- 新包视觉、三级目录、标签、收藏跨窗口、导航历史、拖放／右键／键盘、失效路径、深色／失焦／RTL 及缩放实机检查由主会话执行，不能将构建结果视为这些场景已通过。


### [Codex] · 左侧栏 mockup 探索

- 用户确认收藏目录保留展开能力；PRD 已收敛，技术设计与实施计划已整理，等待最终规划摘要批准。文档影响检查：本轮仅规划，模块及使用说明在实现后回写。

- 用户选择 Finder 风格参考；补充细化 mockup，采用个人收藏／位置／标签分组、紧凑行距、蓝色线性图标及灰底选中态，目录展开行为待确认。

- 基于当前截图生成三份独立 mockup：分组快捷导航、聚焦当前目录、收藏优先。已查看生成结果，等待用户选择或组合方向。
- 规划记录位于外层 `.trellis/tasks/10-01-pixy-sidebar-design/prd.md`，任务保持 planning；业务代码及运行配置未修改。
- 文档影响检查：本轮是候选设计，仅记录项目日志；正式模块及用户说明在方案确定并实现后回写。

### [Codex] · 目录栏文件夹图标

- 左侧目录行显示文件夹图标、名称和展开箭头，采用既有单元格布局。
- 目录栏与内容区保留透明材质、隐藏滚动条及 8pt 单侧圆角。
- Release 构建与 git diff --check 通过；已重启 Pixy，窗口截图确认文件夹图标与文字排列。

### [Codex] · 透明侧边栏与 8pt 内容圆角

- 目录树及 scroll/clip 背景透明，隐藏横纵滚动条，保留滚动容器；地址区域前置固定留白。
- 侧边栏与内容圆角外侧共享 behindWindow/sidebar 材质；背景放在 NSSplitView 同级，并在布局时同步尺寸，铺满窗口全高。背景层不接收鼠标事件。
- 内容白面填充与面板裁剪统一使用 8pt 单侧圆角，支持 RTL，随面板尺寸更新；裁剪覆盖滚动内容。
- Release 双架构构建与 git diff --check 通过；新构建窗口截图确认材质全高铺满、上下圆角连续、地址区域右移及滚动条隐藏。
- 滚轮/触控板滚动、深色模式、RTL 和大图往返尚未完成实机复核。
- 本版改动提交到 Pixy 本地仓库。

## 2026-09-15

### [Codex] · 去除分栏间隙残留竖线，完成圆角收口

- v8 实机验证表明，移除内容面板自绘描边后仍存在一列亮色像素；像素值约为 `#f4f5f5`，与 storyboard 的 `OutlineViewBgColor` 一致，根因是 `NSSplitView` 分栏间隙露出了父级背景，而不是圆角 path 或 Dock。
- v9 将 `NSSplitView` 自身背景统一为 `NSColor.windowBackgroundColor`，并保留无描边的单侧 12px 填充圆角；新 Release 包重新启动后，竖线消失，底部 junction 只保留自然的白灰弧形过渡。用户现场确认“终于好了”。
- 构建通过，`git diff --check` 通过；代码未提交、未推送。

### [Codex] · 统一圆角外侧背景，修正材质色带

- 重新置前检查 v6 实机窗口后确认：圆角 path 已经连续，真正造成“圆角下面不干净”的是侧边栏 storyboard `NSVisualEffectView` 仍在绘制粉紫色材质，而内容 pane 弧外壳绘制的是中性窗口底色，两者在分界处形成亮竖带和色阶跳变。
- 保留 storyboard effect view 作为兼容占位但停止其绘制，在侧边栏 pane 下方加入与内容 pane 共用 `NSColor.windowBackgroundColor` 的不透明背景 view；内容 pane 仍由同一条 leading edge path 绘制填充和弧线。
- v7 Release 构建通过。实际全屏截图和窗口级截图均确认：上、下圆角只有一条连续边，弧外为统一中性灰；窗口底部紧接的深紫色与窗口边界重合，属于 Dock 上沿而非 Pixy 绘制。未提交、未推送。

## 2026-09-14

### [Codex] · 移除圆角 path 误画的底边暗线

- 用户最新复核仍指出圆角下方不干净。对比当前截图与 Chrome 参考图的逐行像素后确认：闭合内容 path 的 `stroke()` 同时描了整条底边；在 Dock 上沿之前形成一条横向突变，容易被误认为圆角外侧背景污染。
- 保留闭合 path 负责内容面填充，边框改为只绘制 leading 侧的竖线与上下两段 12pt 弧线，不再描绘顶部/底部水平边；NSSplitView 的 divider 仍只保留布局与命中区域。
- 全新 v5 Release 构建通过；窗口级截图确认应用自有圆角边界无底边暗线，全屏截图确认剩余紫色是 Dock 的系统叠层。未提交、未推送。

### [Codex] · 圆角外侧背景污染修正

- 用户反馈内容 pane 的圆角下方背景不干净。运行时对比确认：深紫色区域来自全屏截图中的 macOS Dock；Pixy 自身的弧外层此前仍使用半透明 `NSVisualEffectView`，在窗口底部会让外部颜色参与过渡。
- 将内容 pane 的弧外层改为不透明 `NSView`，直接绘制动态窗口背景色；内容白面仍由同一条 leading-edge path 绘制，scroll/clip/collection 背景继续保持透明。
- Release 构建通过；窗口级截图确认圆角外侧干净，全屏截图确认 Dock 仍是窗口外的独立叠层。未提交、未推送。

### [Claude] · 两段式 UI 重构（用户睡眠期间彻底修复并自查）

#### 最终形态（多轮迭代后）

- **两段式结构**：灰色外壳（窗口底色 = OutlineViewBgColor）+ 两张浮动圆角卡片
  - 侧边栏卡：内缩 6px、四角圆角 12、实心灰，目录树内容避让（scroll contentInsets）
  - 内容卡：内缩（上 52 留工具栏行、右/下/左 8）、四角圆角 12、白色，承载缩略图网格
  - 工具栏浮在外壳上（标题栏透明 + fullSizeContentView 常驻）
- **大图模式**：enableToolbarBlend/disableToolbarBlend 切换（不再破坏两段式结构——之前退出大图会移除 fullSizeContentView 导致 UI 变形，已修复）；底部标题胶囊方案 1（文件名实色 + 张数半透明，分色同行）；Finder 打开的会话关闭大图退出应用（isLaunchFromFile + NSApp.terminate）
- **路径条**：前置 .space 间隔，不再贴窗口边缘

#### 迭代中的弯路（记录避免重蹈）

1. 整窗透壁纸毛玻璃 → 用户否决（内容区发灰）→ 回退
2. pane 层白底 + 单角圆角 → 圆角junction 处理错（maskedCorners 单角 + insets 冲突）→ 改为浮动卡片四周留缝方案
3. disableToolbarBlend 恢复不透明标题栏 → 破坏两段式 → 改为常驻透明
4. 关键教训：NSSplitView pane 无法直接 inset；用 scrollView.layer.cornerRadius + masksToBounds + contentInsets 实现卡片化

#### 验证

- Release 构建通过；截图确认：侧边栏卡四角圆角可见、内容卡浮起、分界清晰、无壁纸渗透
- 大图往返后 UI 稳定（disableToolbarBlend 不再改窗口结构）
- Finder-quit 逻辑保留（isLaunchFromFile 检测在 closeLargeImage 最前）

#### 待跟进

- [ ] 深色模式目测验证（代码使用自适应色，预期正常）
- [ ] RTL 布局下侧边栏在右侧的表现
- [ ] push 到 GitHub

## 2026-09-13

### [Claude] · 两项 UX 优化

#### 完成

- **侧边栏毛玻璃**：storyboard 侧边栏 customView 插入 NSVisualEffectView（behindWindow + sidebar material，置于最底层）；CustomTableRowView.drawBackground 不再填充 OutlineViewBgColor 纯色改为透明，右键边框逻辑保留。明暗模式均生效。
- **Dock 图标联动（方案 A）**：closeLargeImage 开头检测 publicVar.isLaunchFromFile（Finder/外部打开图片的会话标记），命中则关窗口并 NSApp.terminate；常规浏览会话不受影响。windowWillClose 已有完整的保存/清理/terminate 链路，直接复用。
- 已知边界：customModule="FlowVision"、工程名/scheme、数据目录名保持不变（此前决策）。

#### 验证

- Release 构建通过；启动后侧边栏透出壁纸色调（vibrancy 生效），选中样式正常。
- 用户 Finder 双击图片实测：关闭大图后应用退出、Dock 图标消失，确认生效。

### [Claude] · 正式签名配置完成

#### 完成

- 完成本地签名验证；正式公开发布改用 Developer ID 证书和 Apple 公证流程。
- bundle id 使用 Pixy 的公开标识，开发机 Team ID 不写入仓库或公开文档。
- 公开源码构建默认关闭签名，发布签名由归档脚本和 CI 的受保护凭据注入。

#### 收益

- 签名身份跨构建稳定：TCC 隐私授权（访问文稿等）不再每次构建重新弹窗。
- build.md 签名一节从此可用默认命令构建（无需 CODE_SIGNING_ALLOWED=NO）。

### [Claude] · 修复菜单栏残留旧名

#### 完成

- 根因：应用菜单（关于/隐藏/退出 FlowVision）标题写死在 Main.storyboard 与两个 .xcstrings（101+51 处多语言文案）里，前两轮只改了代码与 Info.plist 未覆盖到。
- 处理：storyboard 中 UI 标题全部改为 Pixy（12 处 customModule="FlowVision" 为 TARGET 模块引用，**必须保留**，改了会白屏）；两个 xcstrings 全量替换 FlowVision→Pixy（JSON 校验通过）。
- 构建通过，编译产物 Main.storyboardc 已验证含 "About Pixy"/"Quit Pixy"。

#### 边界

- 源码中仍有少量 FlowVision：工程名/TARGET/scheme（用户决定保留）、数据目录 appendingPathComponent（避免数据迁移）、customModule 引用。

### [Claude] · 更换应用图标

#### 完成

- 应用图标替换为用户选定的 icons8 "Photo Gallery" 图标（96px 下载版放大至 1024px 写入 AppIcon.appiconset/icon.png）。
- 构建通过，Dock/应用已重启生效。

#### 边界

- 源图为 icons8 版权素材，免费许可需署名（"Icons by icons8"）；放大到 1024px 后大尺寸略糊。后续可换用 icons8 高清正版授权或原创概念稿。

### [Claude] · 仓库更名与依赖迁移

#### 完成

- GitHub 仓库更名：natinli/FlowVision → **natinli/Pixy**（gh repo rename），origin 已更新；upstream（netdcy/FlowVision）不变。
- 本地目录更名：`projects/FlowVision` → `projects/Pixy`；nilo 登记表与 .gitignore 同步更新。
- 构建依赖完成公开化整理：BTree、Settings 使用 Swift Package，FFmpegKit 使用项目脚本准备，工程不再依赖开发机绝对路径。
- 文档更新：build.md 依赖结构表、bootstrap 流程、签名公证和排障说明。

#### 验证与技术记录

- Release 构建通过（新路径实测）。
- 关键点：pbxproj 相对路径以**仓库目录**（projects/Pixy/）为基准；本仓库在 `~/Documents/nilo/projects/` 下，故到主目录需 `../../../../`（4 级）。路径深度写错时报 `the package at '...' cannot be accessed`，报错信息里会显示解析后的绝对路径，可用于定位差几级。
- Git 仓库更名后旧 URL 自动重定向，但本地 origin 与文档链接应手动更新。

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

### [Claude] · Xcode 26.3 实测构建通过

#### 完成

- 安装 Xcode 26.3（Build 17C529），`xcode-select` 已指向 /Applications/Xcode.app。
- 验证 Swift Package 依赖解析，并通过 bootstrap 脚本下载、校验 FFmpegKit 6.0 macOS xcframework（8 个 framework）。
- Release 构建成功：`xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`；产物为通用 arm64/x86_64 的 Pixy.app。

#### 验证与修正

- **修正 build.md 两处错误认知**：
  1. FFmpegKit 是**硬依赖**——工程 build phase 直接引用 8 个 xcframework，缺失时构建失败；原文档推测"缺失也能构建、仅运行期降级"是错的。dlopen 降级只发生在 xcframework 存在但无法加载的场景。
  2. 新增「签名」一节：无证书时 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` 可跳过签名构建（实测通过）；正式签名需 Xcode 登录 Apple ID 选 Team。
- 常见构建问题表补充两条实测遇到的错误及解法。

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
- 工程引用仓库外本地依赖，build.md 写明目录布置要求。
- 未改动任何上游源码。

#### 待跟进

- [x] 安装完整 Xcode 后实测构建命令（当日完成）。
- [x] 首次 push 到 origin（natinli/Pixy，d16f20e..b90472b 已推送）。
- [ ] 上游发布新版本时按 contributing-internal.md 的同步策略合并。
