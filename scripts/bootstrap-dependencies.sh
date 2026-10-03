#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPENDENCY_DIR="$ROOT_DIR/.build/dependencies"
FFMPEG_VERSION="6.0"
FFMPEG_ARCHIVE="ffmpeg-kit-full-gpl-${FFMPEG_VERSION}-macos-xcframework.zip"
FFMPEG_URL="https://github.com/netdcy/ffmpeg-kit/releases/download/v${FFMPEG_VERSION}/${FFMPEG_ARCHIVE}"
FFMPEG_SHA256="412b1b57c91435b69d7a728162611bbabdb384020aee5b558ceedf3944d94d0d"
FFMPEG_DIR="$DEPENDENCY_DIR/ffmpeg-kit"
ARCHIVE_PATH="$DEPENDENCY_DIR/$FFMPEG_ARCHIVE"
FFMPEG_FRAMEWORKS="ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale"

usage() {
    cat <<'EOF'
用法：scripts/bootstrap-dependencies.sh [--with-ffmpeg] [--skip-ffmpeg]

默认准备 FFmpegKit；使用 --skip-ffmpeg 可生成不含视频运行库的开发构建。
BTree、Settings 和 SDWebImage 由 Xcode 的锁定 Swift Package 依赖自动解析。
EOF
}

with_ffmpeg=1
for argument in "$@"; do
    case "$argument" in
        --with-ffmpeg) with_ffmpeg=1 ;;
        --skip-ffmpeg) with_ffmpeg=0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$argument" >&2; usage >&2; exit 2 ;;
    esac
done

mkdir -p "$DEPENDENCY_DIR"

if [ "$with_ffmpeg" -eq 1 ]; then
    ready=1
    for framework_name in $FFMPEG_FRAMEWORKS; do
        if [ ! -f "$FFMPEG_DIR/$framework_name.xcframework/Info.plist" ]; then
            ready=0
            break
        fi
    done
    if [ "$ready" -eq 1 ]; then
        echo "FFmpegKit ${FFMPEG_VERSION} 已存在：$FFMPEG_DIR"
    else
        command -v curl >/dev/null 2>&1 || { echo "缺少 curl" >&2; exit 1; }
        command -v shasum >/dev/null 2>&1 || { echo "缺少 shasum" >&2; exit 1; }
        command -v unzip >/dev/null 2>&1 || { echo "缺少 unzip" >&2; exit 1; }

        echo "下载 FFmpegKit ${FFMPEG_VERSION}..."
        curl --fail --location --silent --show-error --retry 3 --output "$ARCHIVE_PATH" "$FFMPEG_URL"
        actual_sha256=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
        if [ "$actual_sha256" != "$FFMPEG_SHA256" ]; then
            echo "FFmpegKit 校验失败：期望 $FFMPEG_SHA256，实际 $actual_sha256" >&2
            rm -f "$ARCHIVE_PATH"
            exit 1
        fi

        rm -rf "$FFMPEG_DIR"
        mkdir -p "$FFMPEG_DIR"
        unzip -q "$ARCHIVE_PATH" -d "$FFMPEG_DIR"
        rm -f "$ARCHIVE_PATH"
        xattr -dr com.apple.quarantine "$FFMPEG_DIR" 2>/dev/null || true
        echo "FFmpegKit 已安装并通过 SHA-256 校验：$FFMPEG_DIR"
    fi
else
    echo "跳过 FFmpegKit；构建仍可运行图片浏览功能。"
fi
