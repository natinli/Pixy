# 安全问题

请不要在公开 issue、Pull Request 或日志中发布私钥、证书、访问令牌、个人文件路径或包含个人信息的图片。

## 报告方式

优先使用 GitHub 仓库的 Security 页面提交私密漏洞报告。如果该功能在当前仓库设置中尚未启用，请先提交不包含漏洞细节的 issue，请求维护者提供私下沟通渠道。

请在报告中提供受影响版本、macOS/Xcode 环境、最小复现步骤和修复建议。维护者会在确认后更新受影响版本和修复状态。

## 发布安全

公开发布包应由 Developer ID 签名并完成 Apple 公证。证书、notarytool 凭据和 GitHub Actions Secrets 只保存在本机 keychain 或 GitHub Secrets 中，不写入仓库。
