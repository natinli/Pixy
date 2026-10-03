#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FFMPEG_DIR="$ROOT_DIR/.build/dependencies/ffmpeg-kit"
DESTINATION="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
FFMPEG_FRAMEWORKS="ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale"

if [ ! -d "$FFMPEG_DIR" ]; then
    echo "warning: FFmpegKit 未准备，跳过视频运行库。运行 scripts/bootstrap-dependencies.sh --with-ffmpeg 可启用视频支持。"
    exit 0
fi

mkdir -p "$DESTINATION"
for framework_name in $FFMPEG_FRAMEWORKS; do
    framework_path="$FFMPEG_DIR/$framework_name.xcframework/macos-arm64_x86_64/$framework_name.framework"
    if [ ! -d "$framework_path" ]; then
        echo "error: FFmpegKit 缺少通用 macOS framework：$framework_path" >&2
        exit 1
    fi
    ditto "$framework_path" "$DESTINATION/$framework_name.framework"
done

echo "已复制 FFmpegKit frameworks 到 $DESTINATION"
