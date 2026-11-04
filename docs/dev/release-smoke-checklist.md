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
