# 安全问题

请不要在公开 issue、Pull Request 或日志中发布私钥、证书、访问令牌、个人文件路径或包含个人信息的图片。

## 报告方式

优先使用 GitHub 仓库的 Security 页面提交私密漏洞报告。如果该功能在当前仓库设置中尚未启用，请先提交不包含漏洞细节的 issue，请求维护者提供私下沟通渠道。

请在报告中提供受影响版本、macOS/Xcode 环境、最小复现步骤和修复建议。维护者会在确认后更新受影响版本和修复状态。

## 发布安全

Pixy 当前**没有付费 Apple Developer Program 账号**，因此 0.x 版本是未签名、未公证的预发布包（仅 ad-hoc 签名）。用户需要按[安装说明](docs/user/installation.md)手动放行，这一点在发布页与文档中都明确标注，不存在"已公证"的宣称。

证书、notarytool 凭据和 GitHub Actions Secrets 只保存在本机 keychain 或 GitHub Secrets 中，不写入仓库。`scripts/check-public-hygiene.sh` 会在每次发布前扫描被跟踪文件，拦截开发机路径、Team ID 与凭据文件。

后续若具备 Developer ID 证书，发布包将切换为签名 + 公证，发布工作流会依据 `APPLE_CERTIFICATE_BASE64` Secret 是否配置自动选择模式。详见 [docs/dev/release.md](docs/dev/release.md)。

## 联网与隐私

Pixy 的全部功能在本机运行，**只有一个联网入口**：应用菜单「检查更新…」。只有用户点击它时，才会向 `https://api.github.com/repos/natinli/Pixy/releases/latest` 发一次 GET 请求（超时 10 秒，不重试），读取最新 release 的版本号与页面链接。

- 不带账号、令牌、cookie、设备或用户标识；请求头只设 `Accept`、`User-Agent: Pixy/<版本号>` 与固定的 `Accept-Language: en`（不会带上你的系统语言偏好；系统网络层仍会自动附带 `Host`、`Accept-Encoding`、`Connection` 这类协议层的通用头）；不使用持久缓存与凭据存储。与访问任何网站一样，GitHub 作为服务端能看到发起请求的 IP 地址，这一点无法避免，Pixy 不会额外附带任何标识。
- 没有启动时、定时或后台检查，没有统计或遥测，也没有自动下载、自动更新。
- 响应里的发布页链接只有是 `https://github.com` 下的地址才会作为「打开发布页」的目标，其它情况按失败处理。
- 全部联网代码只在 `FlowVision/Sources/Common/UpdateChecker.swift` 一个文件里；Debug 构建才有、用于本机测试的地址覆盖开关不会编译进发布包。
