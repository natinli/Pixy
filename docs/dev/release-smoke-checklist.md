# Pixy 首发 Smoke Checklist

这份清单用于每次生成公开 release 前记录真实产物验证。勾选项必须附命令、系统/架构和产物 SHA-256；没有证书或干净用户环境时保留未完成状态。

## 已在源码构建验证

- [x] `xcodebuild -list -project FlowVision.xcodeproj` 通过。
- [x] Release 无签名构建通过，产物为 arm64/x86_64 通用 `Pixy.app`。
- [x] FFmpegKit bootstrap 下载包通过 SHA-256 校验。
- [x] 带 FFmpegKit 的 Release 构建通过，8 个 framework 位于 `Contents/Frameworks`。
- [x] `FlowVision/Info.plist` 声明 JPEG、PNG、GIF、HEIF、WebP 和其他图片/视频类型。
- [x] `FlowVision/FlowVision.entitlements` 已移除未使用的 Photos Library 权限；文件操作所需 Apple Events 与用户选定文件访问权限保留。
- [x] 公开仓库敏感信息检查：`scripts/check-public-hygiene.sh` 通过。

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

- Release tag：
- Commit：
- macOS / Xcode：
- 架构：
- DMG SHA-256：
- ZIP SHA-256：
- 签名身份：
- ZIP 公证提交 ID：
- DMG 公证提交 ID：
- 验证人：
- 日期：
