# 第三方依赖与发布说明

Pixy 本身使用 GPL-3.0 发布。以下依赖随源码或正式发布包一起使用；发布包必须保留其许可证和版权信息。

| 组件 | 版本 / revision | 许可证 | 来源 |
|---|---|---|---|
| BTree | `407fda73e18cc9df9130453ee36f73408c22408f`（`master`，见 `Package.resolved`） | MIT | [attaswift/BTree](https://github.com/attaswift/BTree) |
| Settings | 3.1.2，`f41475771f65379ca10852c95119a7f53f0de5a5` | MIT | [sindresorhus/Settings](https://github.com/sindresorhus/Settings) |
| SDWebImage | 5.21.0 | MIT | [SDWebImage/SDWebImage](https://github.com/SDWebImage/SDWebImage) |
| SDWebImageWebPCoder | 0.14.6 | MIT | [SDWebImage/SDWebImageWebPCoder](https://github.com/SDWebImage/SDWebImageWebPCoder) |
| libwebp | 1.5.0 | BSD 3-Clause | [webmproject/libwebp](https://github.com/webmproject/libwebp) |
| FFmpegKit full-gpl | 6.0 macOS xcframework | LGPL/GPL 组合许可，具体以包内 `Resources/LICENSE` 为准 | [FFmpegKit archive](https://github.com/netdcy/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-gpl-6.0-macos-xcframework.zip) |

## FFmpegKit 校验

引导脚本下载的 FFmpegKit archive SHA-256 为：

```text
412b1b57c91435b69d7a728162611bbabdb384020aee5b558ceedf3944d94d0d
```

脚本会在解压前验证该值。FFmpegKit 的 full-gpl 构建可能包含 GPL 组件；重新打包或替换 FFmpegKit 时，必须重新核对许可证、源代码对应关系和校验值。

## 应用图标

应用图标使用 [Icons8 Photo Gallery](https://icons8.com/icons/set/photo-gallery) 图标资源，并在发布说明中保留 Icons8 署名。若替换图标，请同步更新图标来源和许可证记录。

本文件只汇总版本和来源；各依赖的完整许可证文本以对应上游仓库和发布包内的许可证文件为准。
