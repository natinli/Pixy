# Pixy 首发 Smoke Checklist

这份清单用于每次生成公开 release 前记录真实产物验证。勾选项必须附命令、系统/架构和产物 SHA-256；没有证书或干净用户环境时保留未完成状态。

## 已在源码构建验证

- [x] `xcodebuild -list -project FlowVision.xcodeproj` 通过。
- [x] Release 无签名构建通过，产物为 arm64/x86_64 通用 `Pixy.app`。
- [x] FFmpegKit bootstrap 下载包通过 SHA-256 校验。
- [x] 带 FFmpegKit 的 Release 构建通过，8 个 framework 位于 `Contents/Frameworks`。
- [x] `FlowVision/Info.plist` 声明 JPEG、PNG、GIF、HEIF、WebP 和其他图片/视频类型。
- [x] `FlowVision/FlowVision.entitlements` 已移除未使用的 Photos Library 权限；文件操作所需 Apple Events 与用户选定文件访问权限保留。
- [x] 公开仓库敏感信息检查：`scripts/check-public-hygiene.sh` 通过（2026-11-01 起只扫描 `git ls-files` 跟踪文件，且扫描出错即失败）。

## 未签名版（`scripts/release.sh --unsigned`）必须验证

- [x] 产物为 arm64 + x86_64 通用二进制（`lipo -archs` 同时列出两者）。
- [x] `codesign -dv` 显示 `Signature=adhoc`、`TeamIdentifier=not set`，符合未签名预期。
- [x] `codesign --verify --deep --strict --verbose=2 Pixy.app` 通过（ad-hoc 签名自洽）。
- [x] DMG 能挂载，内含 `Pixy.app` 与指向 `/Applications` 的软链接。
- [x] `dist/SHA256SUMS.txt` 中的哈希与产物一致（`cd dist && shasum -a 256 -c SHA256SUMS.txt`）。
- [x] `spctl --assess` 结果为 `rejected`、DMG 无 staple 票据——**这是预期**，用于确认包确实未公证，不要在发布说明里声称已公证。
- [ ] 在未安装过 Pixy 的干净用户环境中，按安装文档的放行步骤能成功首次启动。
- [ ] 放行后能打开图片、文件夹和视频，视频依赖 FFmpegKit 正常加载。
- [ ] 在 Intel Mac 上启动验证（通用二进制最易在 Intel 侧暴露问题）。

## 每个签名公证 release 必须验证

- [ ] `codesign --verify --deep --strict --verbose=2 Pixy.app` 通过。
- [ ] `spctl --assess --type execute --verbose=4 Pixy.app` 通过。
- [ ] `xcrun stapler validate Pixy.app` 和 DMG 通过。
- [ ] DMG/ZIP 在 Apple Silicon 与 Intel Mac 启动并打开图片、文件夹和视频。
- [ ] Finder 中将 Pixy 设为 JPEG/PNG 默认应用后，双击图片、`open <image>`、重启后再次验证。
- [ ] 首次访问图片目录的权限提示符合预期；无额外系统设置绕过步骤。
- [ ] 侧栏、标题栏滚动保护带、子目录进入后的灰色选中态、收起侧栏后的内容宽度完成回归。
- [ ] ZIP 与 DMG 都有独立的公证提交记录。
- [ ] `dist/SHA256SUMS.txt` 与上传到 GitHub Release 的文件一致。

## 记录

### 0.0.5（未签名版）

- Release tag：`v0.0.5`；build `2026112501`（当日第一版，build 号规则见 release.md）
- macOS / Xcode：macOS 15.7.9 / Xcode 26.3（17C529）
- 架构：arm64 + x86_64；签名 ad-hoc，`codesign --verify --deep --strict` 通过；`spctl --assess` 为 rejected、DMG 无 staple 票据（预期）；DMG 含 `Pixy.app` 与指向 `/Applications` 的软链接；`Contents/Frameworks` 含 8 个 FFmpeg 框架与 `libswift_Concurrency.dylib`
- 本地产物（上面的签名、架构、DMG 结构检查针对它；Release 页附件由 CI 重建，哈希不同，以 Release 的 `SHA256SUMS.txt` 为准）：
  - ZIP `5ffc5b3a043048a6696f6d2c95e1b79a357ac7fd11183e264aa15b18e7a7eeee`
  - DMG `ca32aa6e61671a425609c0c4ebeb67ba9f14cfa6c910eeed09c878176c4cf21f`
- Release 页附件（CI 构建，已下载并 `shasum -c SHA256SUMS.txt` 全部 OK；Latest、非 pre-release）：
  - ZIP `c2477920ce9817e4cb6a4cf67ece96e8ccd13ffc5bce96ccfe64aaa4fe0e9f1d`
  - DMG `57019ef5affa961ec310e4558b4b6c91b52dfb05b413f0a13a03c201612c42d9`
- 发布过程：tag 推送后第一次运行构建成功，但「Publish GitHub Release」撞上 GitHub 的 502（当时 Actions/Webhooks 有故障，并让第一次推 tag 没触发工作流，重建 tag 对象后才触发）；随后重跑 4 次都因 macOS arm64 runner 容量不足（`The job was not acquired`）排队 15 分钟后取消，第 6 次成功。tap 提交 `9b78f3b`。
- 本版内容的界面验证（Debug 构建 `com.natinli.PixyDbg`，与发布包同一份源码；发布包的 bundle id 与本机正在使用的 Pixy 相同，且本机 PNG 默认应用就是 Pixy，**未在界面上启动发布包**）：
  - 侧栏位置分组（磁盘、OrbStack、OneDrive 的显示与顺序，电脑名）；设置 → 查看 → 文件操作两个开关的布局（中/英/德）、勾选跨重启保留、关闭时双击仍进大图；>5000 张目录新增文件后位置保持；x86_64（Rosetta）与强制 RTL 的补验见下一段。
  - `xcodebuild test` 21 例通过；`check-localization.py`、`check-public-hygiene.sh` 通过。
  - 未在界面上覆盖：「删除时不再询问」的真实删除（需要 Finder 自动化授权，条件由单元测试覆盖）；「双击用默认应用打开」开启态只有间接证据。
- 未覆盖：真 Intel 机、macOS 11–13 实机、干净用户环境首次启动
- 日期：2026-11-25

### 补验记录（2026-11-25，源码 HEAD，非发布产物）

针对 0.0.2–0.0.4 一直写「未覆盖」的几项做的补验。对象是 Debug 构建（`com.natinli.PixyDbg`，`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` 以显示真实磁盘），不是发布包；macOS 15.7.9（arm64）/ Xcode 26.3。

- **x86_64（Rosetta 2）**：`ARCHS=x86_64` 单架构构建（`lipo -archs` 为 `x86_64`），用 `arch -x86_64` 启动。侧栏四组与位置分组正常；打开 `/tmp` 目录后在目录里新增 12 张 PNG，目录监听自动刷新并显示缩略图；双击进入大图、Esc 返回均正常。**这只证明 x86_64 切片能在 Rosetta 下运行，不等于真 Intel 机**：未测视频与 FFmpeg 框架、GPU 路径与性能。「在 Intel Mac 上启动验证」仍保持未勾选。
- **RTL（阿拉伯语）**：单用 `-AppleLanguages '(ar)'` 只会换文案、**布局不会镜像**（本地化验证够用，RTL 布局验证不够）；需要再加 `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`。强制 RTL 后：侧栏在右、窗口按钮与工具栏镜像、路径条从右往左、缩略图从右侧起排、卷行的推出按钮在行首侧；侧栏收起后内容区填满、再展开恢复（上游修过的 RTL 空白问题未复现）。未测：RTL 下大图方向键与手势、视频、设置窗口。
- **macOS 11 声明**：pbxproj 部署目标 `11.0`，产物 `LC_BUILD_VERSION minos 11.0`（SDK 26.2），Info.plist `LSMinimumSystemVersion 11.0`；编译器按 11.0 检查 API 可用性，高版本 API 必须带 `#available`。这是编译期保证，**运行时在 macOS 11/12 上从未验证**（没有开虚拟机）。README / 安装文档的「macOS 11.0+」按现状保留，勾选项不勾。
- 仍未覆盖：真 Intel 机、macOS 11–13 实机、干净用户环境首次启动。

### 0.0.4（未签名版）

- Release tag：`v0.0.4`；build `2026111703`（同日第三版）
- macOS / Xcode：macOS 15.7.9 / Xcode 26.3（17C529）
- 架构：arm64 + x86_64；签名 ad-hoc，`codesign --verify --deep --strict` 通过；`spctl --assess` 为 rejected（预期）；DMG 结构正确
- 本地产物（Release 页附件由 CI 重建，哈希以 Release 的 `SHA256SUMS.txt` 为准）：
  - ZIP `2f31f2885a8d661ee05b8a7dfb739bfaadb3f2f20eb9bbad10010200b65d4f89`
  - DMG `8a5de10fbc7bd01bc7bd3f5c34f320b442de2423929f26024bb121b936fd2d2d`
- 本版仅侧栏多语言文案（提交 `b022305`）。界面验证由该提交的执行会话在 Debug 构建上完成：de / ja / ru 侧栏标题正确，zh-Hans 回归不变；本次发版未再启动发布包。
- 未覆盖：RTL、Intel Mac、干净用户环境首次启动
- 日期：2026-11-17

### 0.0.3（未签名版）

- Release tag：`v0.0.3`；build `2026111702`（同日第二版，见 release.md 版本号规则）
- macOS / Xcode：macOS 15.7.9 / Xcode 26.3（17C529）
- 架构：arm64 + x86_64；签名 ad-hoc，`codesign --verify --deep --strict` 通过；`spctl --assess` 为 rejected（预期）；DMG 结构正确
- 本地产物（Release 页附件由 CI 重建，哈希以 Release 的 `SHA256SUMS.txt` 为准）：
  - ZIP `99820f0726106aa66d318812c5bf081a9f9fa823925e2c2b7f9c7da2b1c8af8d`
  - DMG `2461baa72dd23ed6946ad7fafe1aa1cbed761298caa437c6e332af9fb0a9ae89`
- 新功能界面验证（AI 在 Debug 构建 `com.natinli.PixyDbg` 上操作，与发布包同一份源码；Release 包 bundle id 与用户正在运行的 Pixy 相同，未在界面上启动以免共用偏好）：
  - 缩放锚定：300 张目录有选中项（`-`、`=`×2、`0`）选中项始终可见且保持选中；无选中项时顶部那张保持在顶部；在顶部缩放仍在顶部；缩放后立即切目录，新目录从顶部开始。6000 张目录连续 5 次缩放锚点始终可见、无空白。
  - 快速搜索：Q 显示用法提示；无匹配显示「（无匹配）」；匹配时选中首项；⌘F 搜索框内输入 q 不触发；编辑菜单项在搜索栏打开与大图模式下置灰、平时可点并进入快搜；`f` 单键切侧栏不受影响；中文、英文正确，德文回落英文。
  - 未在界面覆盖：「切换自定义配置」触发的缩放（代码顺序已调整，仅构建验证）；`m`/`n`/`r` 单键（会改动用户「下载」文件夹或重命名，未按）。
- 未覆盖：RTL、Intel Mac、干净用户环境首次启动
- 公证提交 ID：无（未公证）
- 日期：2026-11-17

### 0.0.2（未签名版）

- Release tag：`v0.0.2`
- macOS / Xcode：macOS 15.7.9 / Xcode 26.3（17C529）
- 架构：arm64 + x86_64（`lipo -archs` 已核对）
- 签名身份：ad-hoc；`codesign --verify --deep --strict` 通过；`spctl --assess` 为 rejected（预期）
- 本地产物（`scripts/release.sh --unsigned`，用于验收；Release 页附件由 CI 重新构建，哈希以 Release 的 `SHA256SUMS.txt` 为准）：
  - ZIP `0d04d7c323cb23a4f6748db999aa4ae9851a967bb7c21f96a99a227a659838d1`
  - DMG `9444429773b0c5936f8ca22552eae1e2b894d24e474ce8a7dde97d0fdb5c4025`
- DMG 内容：`Pixy.app` + `/Applications` 软链接；`Contents/Frameworks` 含 8 个 FFmpegKit framework 与 `libswift_Concurrency.dylib`
- 界面回归（侧栏三级目录、标签、收藏、导航历史、右键/键盘、深色/失焦、缩略图缩放）：用户在本地产物上自行点检后指示继续，未逐项回报；AI 未获界面操作授权，未独立验证
- 未覆盖：RTL、Intel Mac、干净用户环境首次启动
- 公证提交 ID：无（未公证）
- 日期：2026-11-17

### 0.0.1（未签名版）

- Release tag：`v0.0.1`
- Commit：
- macOS / Xcode：macOS（本机）/ Xcode 26.3（17C529）
- 架构：arm64 + x86_64
- DMG SHA-256：见 `dist/SHA256SUMS.txt`（每次构建重新生成）
- ZIP SHA-256：见 `dist/SHA256SUMS.txt`
- 签名身份：ad-hoc（`codesign -s -`）
- 公证提交 ID：无（未公证）
- 验证人：
- 日期：2026-11-01

### 签名版（待具备 Developer ID 后填写）

- Release tag：
- Commit：
- macOS / Xcode：
- 架构：
- DMG SHA-256：
- ZIP SHA-256：
- 签名身份：Developer ID Application
- ZIP 公证提交 ID：
- DMG 公证提交 ID：
- 验证人：
- 日期：
