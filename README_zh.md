<p align="center">
<h1 align="center">FlowVision</h1>
<h3 align="center">为 macOS 设计的瀑布流式图片浏览器</h3>
</p>

<p align="center">
<a href="https://github.com/natinli/FlowVision/releases"><img src="https://img.shields.io/github/release/netdcy/FlowVision.svg?color=blue" alt="release"></a>
<a href="README.md">English</a> · 简体中文
</p>

> 本仓库是 [netdcy/FlowVision](https://github.com/netdcy/FlowVision) 的 fork，在上游基础上维护中文文档体系并做定制改进。版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 预览

### 浅色模式
![preview](https://netdcy.github.io/FlowVision/docs/preview_2.png)

### 深色模式
![preview](https://netdcy.github.io/FlowVision/docs/preview_1.png)

## 功能特性

- **四种视图**：自适应布局（justified）、瀑布流、网格、列表，一键切换
- **Finder 式文件管理**：复制/剪切/粘贴/重命名/删除、目录树、面包屑路径条
- **右键手势**：快速跳转上一个/下一个含图片的文件夹、上级目录、历史返回
- **视频播放**：内联自动播放、控制条、AB 循环、列表连续播放
- **大图查看**：高质量缩放（减轻摩尔纹）、旋转/镜像、EXIF/GPS 信息、OCR 与二维码识别
- **HDR 显示**（macOS 14.0+）、相机 RAW 支持、WebP/PNG 动画
- **Finder 标签与 XMP 星级**：打标、过滤、按标签/评级排序
- **性能**：万张级目录流畅浏览、LRU 内存回收、目录变更监听增量刷新
- **递归模式**：一个窗口浏览整个子树

## 安装

系统要求：macOS 11.0+。开源软件，无网络请求。

**Homebrew 安装（推荐）**

```bash
brew install flowvision
```

升级：

```bash
brew update && brew upgrade flowvision
```

**从源码编译**：见 [docs/dev/build.md](docs/dev/build.md)。

详细安装说明与常见安装问题：[docs/user/installation.md](docs/user/installation.md)。

## 快速上手

| 操作 | 方式 |
|---|---|
| 打开/关闭大图 | 双击缩略图 |
| 缩放 | 大图中滚轮；或按住右键/左键滚动滚轮 |
| 文件夹跳转 | 右键手势：右/左=下/上一个图片文件夹，上=上级，下=返回历史 |
| 目录导航（键盘） | W=上级，A/D=左/右，S=返回 |
| 搜索过滤 | ⌘ + F |

完整操作说明（手势、全部快捷键、视频控制、标签评级）：[docs/user/usage.md](docs/user/usage.md)。

遇到问题：[docs/user/faq.md](docs/user/faq.md)。

## 文档

| 文档 | 说明 |
|---|---|
| [docs/index.md](docs/index.md) | 文档中心总入口 |
| [docs/user/](docs/user/installation.md) | 用户文档：安装、使用、FAQ |
| [docs/dev/](docs/dev/architecture.md) | 开发文档：架构、模块详解、构建、修改指南 |
| [CHANGELOG.md](CHANGELOG.md) | 版本历史 |
| [CLAUDE.md](CLAUDE.md) | AI 协作入口 |

## 开发

- 环境：Xcode 15.2+，详见 [docs/dev/build.md](docs/dev/build.md)
- 技术栈：纯 AppKit（Swift），SPM 依赖 SDWebImage(+WebP)、BTree、Settings；FFmpegKit xcframework 懒加载
- 第三方库：[ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit) · [BTree](https://github.com/attaswift/BTree) · [Settings](https://github.com/sindresorhus/Settings)

## 支持

如果你感觉这个应用有帮助，欢迎支持上游开发者！

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/netdcyn)

<img src="https://flowvision.app/donate.jpg" alt="WeChat Donate" width="350"/>

## 协议

本项目使用 GPL 许可证，完整文本见 [LICENSE](LICENSE)。
