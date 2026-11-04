# 安装

## 系统要求

- macOS 11.0（Big Sur）或更高版本
- HDR 显示需要 macOS 14.0+；OCR 功能需要 macOS 13.0+
- Apple Silicon（ARM）或 Intel 芯片

## 隐私与安全性

Pixy 的功能在本机运行，不需要联网账号。首次访问图片目录时，macOS 会按目录请求文件权限；只授予你需要浏览的位置即可。

## 方式一：Homebrew（推荐）

```bash
brew install --cask natinli/pixy/pixy
```

升级用 `brew upgrade --cask pixy`，卸载用 `brew uninstall --cask pixy`；加上 `--zap` 会一并删掉偏好设置、缓存和搜索索引，回到干净状态。

cask 来自个人 tap [natinli/homebrew-pixy](https://github.com/natinli/homebrew-pixy)。Pixy 没有进入官方 `homebrew/cask`，原因是官方库要求 cask 能通过 Gatekeeper 检查，而未签名的 Pixy 通不过——详见 [发布流程](../dev/release.md)。

> **Homebrew 安装后首次启动仍要放行一次。** Homebrew 会给下载的产物打上隔离标记（旧版的 `--no-quarantine` 选项已被移除），所以隔离属性照样存在。放行方式见下一节。

## 方式二：GitHub Releases

1. 打开 [Pixy Releases](https://github.com/natinli/Pixy/releases)。
2. 下载最新的 `.dmg` 或 `.zip`。发布包是 arm64 + x86_64 通用二进制，Apple Silicon 和 Intel Mac 通用。
3. 打开 `.dmg` 并将 Pixy 拖到「应用程序」，或将 `.zip` 中的 Pixy 拖到「应用程序」。
4. 从「应用程序」启动 Pixy。

### 当前版本未签名

Pixy 目前没有付费 Apple Developer Program 账号，因此 0.x 版本**未使用 Developer ID 签名，也没有经过 Apple 公证**。这不会影响功能，但 macOS 首次启动时会拦截。

**首次启动放行（二选一）**

方式 A，图形界面：

1. 双击 Pixy，出现「无法验证开发者」提示时点「完成」。
2. 打开「系统设置 → 隐私与安全性」，在页面底部找到被拦截的 Pixy，点「仍要打开」。
3. 再次启动 Pixy，在弹窗中点「打开」。

方式 B，终端（只对这一个 App 生效）：

```bash
xattr -dr com.apple.quarantine /Applications/Pixy.app
```

放行只需要做一次，之后正常启动。每个新版本下载后都需要重新放行一次。

**注意**：未签名的 Pixy **不建议**设为图片格式的默认打开应用。系统在部分情况下会重新校验签名并弹出提示，导致双击图片无法直接打开。

### 签名版本何时可用

具备 Developer ID 证书后，发布包会改为 Developer ID 签名 + Apple 公证。届时首次启动无需任何放行步骤，可以直接在 Finder 里设为默认图片查看器。版本说明里会标明是否为签名包。

如果 macOS 显示的签名团队或下载来源与 GitHub Releases 不一致，请先停止安装并在仓库提交问题。

### 关于 Homebrew

不要用 `brew install flowvision`——那是上游 FlowVision 自己的包，装出来是上游的 FlowVision，**不是 Pixy**，也不包含 Pixy 的侧栏与界面改动。Pixy 的 cask 名是 `pixy`，并且只在自己的 tap 里。

设置 `HOMEBREW_CASK_OPTS` 之类的全局选项不会让 Pixy 免于首次放行，原因见方式一里的说明。

## 方式三：从源码编译

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

未签名的源码构建主要用于开发和测试，可能被 Gatekeeper 拦截，放行方式同上。需要给其他用户分发时，请使用 `scripts/release.sh` 生成的 release 产物，而不是直接把本机编译结果传给别人。

## 安装后首次使用

1. 首次启动时按需允许 Pixy 访问图片目录。
2. 打开任意文件夹，或从 Finder 将文件夹拖到 Pixy 窗口。
3. 在「设置 → 通用」中选择启动时打开主页还是上次文件夹。

## 设为默认图片应用

> 只有在使用 **Developer ID 签名并公证** 的 release 包时才建议执行本节。未签名版本设为默认应用后，macOS 可能在系统重新校验签名时拦截双击打开，表现为图片打不开。

1. 在 Finder 中选中一张 JPEG 或 PNG 图片，按 `⌘I` 打开「显示简介」。
2. 在「打开方式」中选择 Pixy。
3. 点击「全部更改…」，确认后续同类图片都使用 Pixy。

如果「打开方式」里没有 Pixy，先从「应用程序」启动一次，再重新打开「显示简介」。如果系统仍提示安全性错误，请确认使用的是 GitHub Releases 中的签名、公证包；未签名版本的安全提示属于预期现象。
