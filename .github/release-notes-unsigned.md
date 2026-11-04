## ⚠️ 这个版本没有签名，也没有公证

Pixy 目前没有付费 Apple Developer Program 账号，因此本包只做了 ad-hoc 签名。macOS 会在首次启动时拦截它，需要手动放行一次。

### 首次启动放行（二选一）

**图形界面**：双击 Pixy 被拦截后点「完成」，打开「系统设置 → 隐私与安全性」，在页面底部点「仍要打开」，再次启动并在弹窗中点「打开」。

**终端**（只对这一个 App 生效）：

```bash
xattr -dr com.apple.quarantine /Applications/Pixy.app
```

放行只需一次，但**每个新版本下载后都要重新放行**。

### 请注意

- 未签名版本**不建议**设为图片格式的默认打开应用：macOS 重新校验签名时，双击图片会打不开。
- 功能完整，包括视频播放（FFmpegKit 已内置）。
- 产物是 arm64 + x86_64 通用二进制，Apple Silicon 与 Intel 通用。

### 校验下载

```bash
shasum -a 256 -c SHA256SUMS.txt
```

完整安装说明见 [docs/user/installation.md](https://github.com/natinli/Pixy/blob/main/docs/user/installation.md)。
