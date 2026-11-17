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
