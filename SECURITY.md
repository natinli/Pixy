# 安全问题

请不要在公开 issue、Pull Request 或日志中发布私钥、证书、访问令牌、个人文件路径或包含个人信息的图片。

## 报告方式

优先使用 GitHub 仓库的 Security 页面提交私密漏洞报告。如果该功能在当前仓库设置中尚未启用，请先提交不包含漏洞细节的 issue，请求维护者提供私下沟通渠道。

请在报告中提供受影响版本、macOS/Xcode 环境、最小复现步骤和修复建议。维护者会在确认后更新受影响版本和修复状态。

## 发布安全

Pixy 当前**没有付费 Apple Developer Program 账号**，因此 0.x 版本是未签名、未公证的预发布包（仅 ad-hoc 签名）。用户需要按[安装说明](docs/user/installation.md)手动放行，这一点在发布页与文档中都明确标注，不存在"已公证"的宣称。

证书、notarytool 凭据和 GitHub Actions Secrets 只保存在本机 keychain 或 GitHub Secrets 中，不写入仓库。`scripts/check-public-hygiene.sh` 会在每次发布前扫描被跟踪文件，拦截开发机路径、Team ID 与凭据文件。

后续若具备 Developer ID 证书，发布包将切换为签名 + 公证，发布工作流会依据 `APPLE_CERTIFICATE_BASE64` Secret 是否配置自动选择模式。详见 [docs/dev/release.md](docs/dev/release.md)。
