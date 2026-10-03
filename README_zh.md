<p align="center">
<h1 align="center">Pixy</h1>
<h3 align="center">为 macOS 设计的瀑布流式图片与视频浏览器</h3>
</p>

<p align="center">
<a href="https://github.com/natinli/Pixy/releases"><img src="https://img.shields.io/github/release/natinli/Pixy.svg?color=blue" alt="release"></a>
<a href="README.md">English</a> · 简体中文
</p>

> Pixy 基于 [netdcy/FlowVision](https://github.com/netdcy/FlowVision)，保留上游署名，同时独立维护发布、文档和 Finder 式导航改动。版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 预览

### 浅色模式
![preview](docs/preview_2.png)

### 深色模式
![preview](docs/preview_1.png)

## 功能特性

- **四种视图**：自适应布局（justified）、瀑布流、网格、列表
- **Finder 式文件管理**：复制、剪切、粘贴、重命名、删除、目录树和面包屑路径条
- **Finder 式左侧栏**：常用 macOS 位置、标签、展开箭头和动态选中反馈
- **右键手势**：跳转相邻图片文件夹、上级目录或导航历史
- **视频播放**：内联播放控制、AB 循环和列表连续播放
- **大图查看**：高质量缩放、旋转/镜像、EXIF/GPS 信息、OCR 与二维码识别
- **HDR 显示**（macOS 14.0+）、相机 RAW、WebP 与 PNG 动画
- **Finder 标签与 XMP 星级**：打标、过滤、排序
- **性能**：目录增量刷新与 LRU 内存回收，适合大型目录
- **递归模式**：一个窗口浏览整个子树

## 安装

Pixy 支持 macOS 11.0 及以上版本。正式发布包计划使用 **Developer ID 签名并完成 Apple 公证**，这样 Finder 可以把 Pixy 设为默认图片查看器，用户无需绕过 Gatekeeper。发布包可从 [GitHub Releases](https://github.com/natinli/Pixy/releases) 下载 `.dmg` 或 `.zip`，再将 Pixy 拖入「应用程序」。

如果暂时还没有正式发布包，可按 [docs/dev/build.md](docs/dev/build.md) 从源码编译。未签名源码构建用于开发，可能触发 Gatekeeper 提示，不作为公开发布路径。

完整安装与首次启动说明见 [docs/user/installation.md](docs/user/installation.md)。

## 快速上手

| 操作 | 方式 |
|---|---|
| 打开/关闭大图 | 双击缩略图 |
| 缩放 | 大图中滚轮，或按住鼠标键滚动 |
| 文件夹导航 | 右键手势：右/左=相邻图片文件夹，上=上级，下=返回历史 |
| 目录导航（键盘） | W=上级，A/D=左/右，S=返回 |
| 搜索过滤 | ⌘ + F |

完整操作说明：[docs/user/usage.md](docs/user/usage.md)。

遇到问题：[docs/user/faq.md](docs/user/faq.md)。

## 文档

| 文档 | 说明 |
|---|---|
| [docs/index.md](docs/index.md) | 文档中心总入口 |
| [docs/user/](docs/user/installation.md) | 安装、使用和常见问题 |
| [docs/dev/](docs/dev/architecture.md) | 架构、模块、构建和贡献指南 |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | 依赖许可证与发布说明 |
| [CHANGELOG.md](CHANGELOG.md) | 版本历史 |

## 开发

- 环境：Xcode 15.2+ 和 macOS 11.0+ SDK
- 技术栈：AppKit、Swift；SDWebImage、BTree、Settings 使用锁定版本的 Swift Package
- 可选视频运行库：FFmpegKit 6.0 full-gpl macOS xcframework，由引导脚本下载并校验 SHA-256
- 构建说明：[docs/dev/build.md](docs/dev/build.md)

## 参与贡献

提交 Pull Request 或报告安全问题前，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 协议

Pixy 使用 GPL-3.0 协议发布。完整文本及第三方依赖说明见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
