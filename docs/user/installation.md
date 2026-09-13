# 安装

## 系统要求

- macOS 11.0（Big Sur）或更高版本
- HDR 显示功能需要 macOS 14.0+；OCR 功能需要 macOS 13.0+
- Apple Silicon（ARM）或 Intel 芯片

## 隐私与安全性

- 开源软件，代码可审计
- 无任何网络请求，所有功能本地运行

## 方式一：Homebrew 安装（推荐）

首次安装：

```bash
brew install flowvision
```

版本升级：

```bash
brew update
brew upgrade flowvision
```

## 方式二：下载安装包

1. 前往上游 [Releases](https://github.com/netdcy/FlowVision/releases) 下载对应芯片的版本（上游发布的安装包名为 FlowVision，与本 fork 的展示名 Pixy 不冲突）：
   - Apple Silicon（M 系列）：`arm64` 版本
   - Intel：`x64` 版本
2. 打开 `.dmg`，将应用拖入「应用程序」文件夹。
3. 首次打开若提示「无法验证开发者」或「已损坏」：这是因为应用未经 Apple 公证，在「系统设置 → 隐私与安全性」中点击「仍要打开」，或执行：

```bash
xattr -rd com.apple.quarantine /Applications/Pixy.app
```

## 方式三：从源码编译

见 [构建与调试](../dev/build.md)。需要完整 Xcode 15.2+。

## 安装后首次使用

1. 首次启动会请求访问文件夹的权限（访问图片目录所必需），按需允许。
2. 打开任意文件夹即可开始浏览；从 Finder 拖文件夹到 Dock 图标也可打开。
3. 启动目录可在「设置 → 通用」中选择主页或上次文件夹。
