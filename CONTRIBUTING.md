# 贡献指南

感谢你为 Pixy 提交改进。提交前请先搜索现有 issue，确认问题仍能在最新代码或 release 中复现。

## 开发流程

1. Fork 仓库并创建主题分支。
2. 阅读 [docs/dev/build.md](docs/dev/build.md)，使用锁定的 Swift Package 构建。
3. 运行 `scripts/bootstrap-dependencies.sh --skip-ffmpeg` 做快速源码构建；涉及视频时使用 `--with-ffmpeg`。
4. 修改用户可见行为时同步更新 `docs/user/` 和 `CHANGELOG.md`；修改构建或依赖时同步更新 `docs/dev/build.md` 与 `THIRD_PARTY_NOTICES.md`。
5. 在 Pull Request 中说明复现步骤、行为变化和验证命令。

## 代码约定

Pixy 是 AppKit/Swift 工程，功能代码按现有 ViewController extension 组织。避免无关重构；改动应保持 macOS 11.0 的部署目标。提交信息使用简短中文描述，例如 `fix: 修复侧栏导航状态`。

## Pull Request

- 保持改动范围单一，附上必要的截图或日志。
- 不提交证书、私钥、个人路径、`LocalDev.xcconfig`、构建产物或 FFmpegKit 下载缓存。
- CI 必须通过；如果本机无法运行完整冒烟，请在 PR 中说明限制。
