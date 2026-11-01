#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

usage() {
    cat <<'EOF'
用法：scripts/release.sh [--unsigned]

默认（签名 + 公证）：
  需要 Developer ID Application 证书和 Apple Developer Program 账号。
  必须设置 APPLE_TEAM_ID 和 NOTARY_PROFILE。

--unsigned：
  不签名、不公证，仅做 ad-hoc 签名后打包。
  产物名带 -unsigned 后缀，Gatekeeper 会拦截，用户需手动放行。
  用于没有付费开发者账号时的预发布。
EOF
}

unsigned=0
for argument in "$@"; do
    case "$argument" in
        --unsigned) unsigned=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$argument" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$unsigned" -eq 0 ]; then
    : "${APPLE_TEAM_ID:?请设置 APPLE_TEAM_ID，或使用 --unsigned 生成未签名预发布包}"
    : "${NOTARY_PROFILE:?请设置 NOTARY_PROFILE，或使用 --unsigned 生成未签名预发布包}"
fi

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN_PATH:-}"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

scripts/check-public-hygiene.sh
scripts/check-dependency-notices.sh
scripts/bootstrap-dependencies.sh --with-ffmpeg

if [ "$unsigned" -eq 0 ]; then
    ARCHIVE_DIR="$BUILD_DIR/archive"
    EXPORT_DIR="$BUILD_DIR/export"
    ARCHIVE_PATH="$ARCHIVE_DIR/Pixy.xcarchive"
    EXPORT_OPTIONS="$BUILD_DIR/export-options.plist"
    rm -rf "$ARCHIVE_DIR" "$EXPORT_DIR"
    mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

    xcodebuild archive \
        -project FlowVision.xcodeproj \
        -scheme FlowVision \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGN_STYLE=Automatic \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
        CODE_SIGNING_ALLOWED=YES

    cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"

    APP_PATH="$EXPORT_DIR/Pixy.app"
    ARCHIVE_NAME_SUFFIX="universal"
else
    DERIVED_DATA="$BUILD_DIR/DerivedData-unsigned"
    rm -rf "$DERIVED_DATA"
    mkdir -p "$DERIVED_DATA"

    xcodebuild \
        -project FlowVision.xcodeproj \
        -scheme FlowVision \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY='' \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        build

    APP_PATH="$DERIVED_DATA/Build/Products/Release/Pixy.app"
    ARCHIVE_NAME_SUFFIX="universal-unsigned"
fi

[ -d "$APP_PATH" ] || { echo "未找到导出的 Pixy.app：$APP_PATH" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
ARCHIVE_NAME="Pixy-${VERSION}-${ARCHIVE_NAME_SUFFIX}"
ZIP_PATH="$DIST_DIR/${ARCHIVE_NAME}.zip"
DMG_PATH="$DIST_DIR/${ARCHIVE_NAME}.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

if [ "$unsigned" -eq 1 ]; then
    # ad-hoc 签名：让包在 Apple Silicon 上可直接运行（所有代码都必须至少有一个签名），
    # 但不会获得 Gatekeeper 信任——下载后仍会被拦截，需要用户手动放行。
    codesign --force --deep --sign - "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto "$APP_PATH" "$STAGING_DIR/Pixy.app"
ln -s /Applications "$STAGING_DIR/Applications"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create -volname "Pixy $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

if [ "$unsigned" -eq 0 ]; then
    submit_for_notarization() {
        artifact_path="$1"
        if [ -n "$NOTARY_KEYCHAIN_PATH" ]; then
            xcrun notarytool submit "$artifact_path" \
                --keychain-profile "$NOTARY_PROFILE" \
                --keychain "$NOTARY_KEYCHAIN_PATH" \
                --wait
        else
            xcrun notarytool submit "$artifact_path" \
                --keychain-profile "$NOTARY_PROFILE" \
                --wait
        fi
    }

    submit_for_notarization "$ZIP_PATH"
    submit_for_notarization "$DMG_PATH"

    xcrun stapler staple "$APP_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type execute --verbose=4 "$APP_PATH"
else
    echo "注意：这是未签名、未公证的预发布包，Gatekeeper 会拦截首次启动。" >&2
fi

(
    cd "$DIST_DIR"
    shasum -a 256 "${ARCHIVE_NAME}.zip" "${ARCHIVE_NAME}.dmg" > SHA256SUMS.txt
)

echo "版本：${VERSION}（build ${BUILD_NUMBER}）"
echo "发布产物已生成：$DIST_DIR"
