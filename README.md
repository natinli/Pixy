<p align="center">
<h1 align="center">Pixy</h1>
<h3 align="center">Waterfall-style image viewer for macOS</h3>
</p>

<p align="center">
<a href="https://github.com/natinli/Pixy/releases"><img src="https://img.shields.io/github/release/natinli/Pixy.svg?color=blue" alt="release"></a>
<a href="README_zh.md">简体中文</a>
</p>

> Pixy is a macOS image and video browser based on [netdcy/FlowVision](https://github.com/netdcy/FlowVision). The fork keeps upstream attribution while maintaining its own release, documentation, and Finder-style navigation work. See [CHANGELOG.md](CHANGELOG.md) for the project history.

## Preview

### Light Mode
![preview](docs/preview_2.png)

### Dark Mode
![preview](docs/preview_1.png)

## Features

- **Four view modes**: justified layout, waterfall, grid, and list
- **Finder-style file management**: copy/cut/paste/rename/delete, directory tree, and breadcrumb path bar
- **Finder-style sidebar**: familiar macOS locations, tags, disclosure behavior, and dynamic selection feedback
- **Right-click gestures**: jump to neighboring image folders, the parent folder, or navigation history
- **Video playback**: inline playback controls, A-B loop, and continuous playback in lists
- **Full image view**: high-quality scaling, rotation/mirroring, EXIF/GPS information, OCR, and QR recognition
- **HDR display** (macOS 14.0+), camera RAW, WebP, and animated PNG support
- **Finder tags and XMP ratings**: tagging, filtering, and sorting
- **Performance**: incremental directory refresh and LRU memory management for large folders
- **Recursive mode**: browse an entire subtree in one window

## Installation

Pixy supports macOS 11.0 and later. Published releases are intended to be **Developer ID signed and Apple notarized**, so Finder can use Pixy as the default image viewer without asking users to bypass Gatekeeper. Download the latest `.dmg` or `.zip` from [GitHub Releases](https://github.com/natinli/Pixy/releases), then drag Pixy to Applications.

If a release is not available yet, build from source with [docs/dev/build.md](docs/dev/build.md). An unsigned source build is for development and may be blocked by Gatekeeper; it is not the release distribution path.

For the complete installation and first-launch guide, see [docs/user/installation.md](docs/user/installation.md).

## Quick Start

| Action | How |
|---|---|
| Open/close full image view | Double-click a thumbnail |
| Zoom | Scroll in image view; or hold a mouse button and scroll |
| Folder navigation | Right-click gestures: right/left = next/previous image folder, up = parent, down = back |
| Keyboard navigation | W = parent, A/D = previous/next, S = back |
| Search & filter | ⌘ + F |

Full usage documentation: [docs/user/usage.md](docs/user/usage.md).

Troubleshooting: [docs/user/faq.md](docs/user/faq.md).

## Documentation

| Document | Description |
|---|---|
| [docs/index.md](docs/index.md) | Documentation hub |
| [docs/user/](docs/user/installation.md) | Installation, usage, and FAQ |
| [docs/dev/](docs/dev/architecture.md) | Architecture, modules, build, and contribution guidance |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Dependency licenses and distribution notes |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

## Development

- Requirements: Xcode 15.2+ and macOS 11.0+ SDK
- Stack: AppKit and Swift, with locked Swift Package dependencies for SDWebImage, BTree, and Settings
- Optional video runtime: FFmpegKit 6.0 full-gpl macOS xcframework, downloaded and checksum-verified by the bootstrap script
- Build instructions: [docs/dev/build.md](docs/dev/build.md)

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening a pull request or reporting a security issue.

## License

Pixy is distributed under the GPL-3.0 license. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the complete distribution context.
