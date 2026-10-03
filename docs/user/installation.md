# 安装

## 系统要求

- macOS 11.0（Big Sur）或更高版本
- HDR 显示需要 macOS 14.0+；OCR 功能需要 macOS 13.0+
- Apple Silicon（ARM）或 Intel 芯片

## 隐私与安全性

Pixy 的功能在本机运行，不需要联网账号。首次访问图片目录时，macOS 会按目录请求文件权限；只授予你需要浏览的位置即可。

## 方式一：GitHub Releases（推荐）

1. 打开 [Pixy Releases](https://github.com/natinli/Pixy/releases)。
2. 下载最新的 `.dmg` 或 `.zip`，优先选择与你的 Mac 架构匹配的产物。
3. 打开 `.dmg` 并将 Pixy 拖到「应用程序」，或将 `.zip` 中的 Pixy 拖到「应用程序」。
4. 从「应用程序」启动 Pixy。

正式发布包使用 Developer ID 签名并完成 Apple 公证。这样 Finder 可以把 Pixy 设为 JPEG、PNG 等图片格式的默认打开应用，首次启动不需要用户去「隐私与安全性」中绕过 Gatekeeper。

如果 macOS 显示的签名团队或下载来源与 GitHub Releases 不一致，请先停止安装并在仓库提交问题。

## 方式二：从源码编译

见 [构建与调试](../dev/build.md)。需要完整 Xcode 15.2+：

```bash
scripts/bootstrap-dependencies.sh --with-ffmpeg
xcodebuild \
  -project FlowVision.xcodeproj \
  -scheme FlowVision \
  -configuration Release \
  -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY='' \
  build
```

未签名的源码构建主要用于开发和测试，可能被 Gatekeeper 拦截。不要把移除 quarantine 或点击「仍要打开」当作公开发布安装步骤；需要给其他用户分发时，请使用签名并公证的 release 工作流。

## 安装后首次使用

1. 首次启动时按需允许 Pixy 访问图片目录。
2. 打开任意文件夹，或从 Finder 将文件夹拖到 Pixy 窗口。
3. 在「设置 → 通用」中选择启动时打开主页还是上次文件夹。

## 设为默认图片应用

1. 在 Finder 中选中一张 JPEG 或 PNG 图片，按 `⌘I` 打开「显示简介」。
2. 在「打开方式」中选择 Pixy。
3. 点击「全部更改…」，确认后续同类图片都使用 Pixy。

如果「打开方式」里没有 Pixy，先从「应用程序」启动一次，再重新打开「显示简介」。如果系统仍提示安全性错误，请确认使用的是 GitHub Releases 中的已签名、公证包；源码构建的安全提示不代表默认应用配置失败。
