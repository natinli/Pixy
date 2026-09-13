<p align="center">
<h1 align="center">FlowVision</h1>
<h3 align="center">Waterfall-style Image Viewer for macOS</h3>
</p>

<p align="center">
<a href="https://github.com/natinli/FlowVision/releases"><img src="https://img.shields.io/github/release/netdcy/FlowVision.svg?color=blue" alt="release"></a>
English · <a href="README_zh.md">简体中文</a>
</p>

> This repository is a fork of [netdcy/FlowVision](https://github.com/netdcy/FlowVision), maintaining a Chinese documentation system and custom improvements on top of upstream. See [CHANGELOG.md](CHANGELOG.md) for version history.

## Preview

### Light Mode
![preview](https://netdcy.github.io/FlowVision/docs/preview_2.png)

### Dark Mode
![preview](https://netdcy.github.io/FlowVision/docs/preview_1.png)

## Features

- **Four view modes**: justified layout, waterfall, grid, and list — switch with one click
- **Finder-style file management**: copy/cut/paste/rename/delete, directory tree, breadcrumb path bar
- **Right-click gestures**: quickly jump to the next/previous folder with images, go to parent, or go back in history
- **Video playback**: inline autoplay, playback controls, A-B loop, continuous playback in list
- **Full image view**: high-quality scaling (reduces moiré), rotation/mirroring, EXIF/GPS info, OCR and QR code recognition
- **HDR display** (macOS 14.0+), camera RAW support, WebP/PNG animations
- **Finder tags and XMP ratings**: tagging, filtering, and sorting by tag or rating
- **Performance**: smooth browsing of directories with tens of thousands of images, LRU memory management, incremental refresh on directory changes
- **Recursive mode**: browse an entire subtree in one window

## Installation

Requires macOS 11.0+. Open source, no network requests.

**Homebrew (recommended)**

```bash
brew install flowvision
```

Upgrade:

```bash
brew update && brew upgrade flowvision
```

**Build from source**: see [docs/dev/build.md](docs/dev/build.md) (Chinese).

For detailed installation instructions: [docs/user/installation.md](docs/user/installation.md) (Chinese).

## Quick Start

| Action | How |
|---|---|
| Open/close full image view | Double-click a thumbnail |
| Zoom | Scroll wheel in image view; or hold right/left button and scroll |
| Folder navigation | Right-click gestures: right/left = next/previous image folder, up = parent, down = back |
| Keyboard navigation | W = parent, A/D = previous/next, S = back |
| Search & filter | ⌘ + F |

Full usage documentation (gestures, all shortcuts, video controls, tags and ratings): [docs/user/usage.md](docs/user/usage.md) (Chinese).

Troubleshooting: [docs/user/faq.md](docs/user/faq.md) (Chinese).

## Documentation

| Document | Description |
|---|---|
| [docs/index.md](docs/index.md) | Documentation hub (Chinese) |
| [docs/user/](docs/user/installation.md) | User docs: installation, usage, FAQ (Chinese) |
| [docs/dev/](docs/dev/architecture.md) | Developer docs: architecture, module reference, build, contributing (Chinese) |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CLAUDE.md](CLAUDE.md) | AI collaboration entry point (Chinese) |

## Development

- Requirements: Xcode 15.2+, see [docs/dev/build.md](docs/dev/build.md)
- Stack: pure AppKit (Swift), SPM dependencies SDWebImage(+WebP), BTree, Settings; FFmpegKit xcframework lazy-loaded
- Third-party libraries: [ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit) · [BTree](https://github.com/attaswift/BTree) · [Settings](https://github.com/sindresorhus/Settings)

## Support

If you find this app helpful, please consider supporting the upstream developer!

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/netdcyn)

<img src="https://flowvision.app/donate.jpg" alt="WeChat Donate" width="350"/>

## License

This project is licensed under the GPL. See [LICENSE](LICENSE) for the full text.
