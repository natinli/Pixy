#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

: "${APPLE_TEAM_ID:?请设置 APPLE_TEAM_ID}"
: "${NOTARY_PROFILE:?请设置 NOTARY_PROFILE}"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN_PATH:-}"
ARCHIVE_DIR="$ROOT_DIR/.build/archive"
EXPORT_DIR="$ROOT_DIR/.build/export"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$ARCHIVE_DIR/Pixy.xcarchive"
EXPORT_OPTIONS="$ROOT_DIR/.build/export-options.plist"

rm -rf "$ARCHIVE_DIR" "$EXPORT_DIR" "$DIST_DIR"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR" "$DIST_DIR"

scripts/check-public-hygiene.sh
scripts/check-dependency-notices.sh
scripts/bootstrap-dependencies.sh --with-ffmpeg

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
[ -d "$APP_PATH" ] || { echo "未找到导出的 Pixy.app" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
ARCHIVE_NAME="Pixy-${VERSION}-universal"
ZIP_PATH="$DIST_DIR/${ARCHIVE_NAME}.zip"
DMG_PATH="$DIST_DIR/${ARCHIVE_NAME}.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/Pixy.app"
ln -s /Applications "$STAGING_DIR/Applications"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create -volname "Pixy $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

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

(
    cd "$DIST_DIR"
    shasum -a 256 "${ARCHIVE_NAME}.zip" "${ARCHIVE_NAME}.dmg" > SHA256SUMS.txt
)

echo "发布产物已生成：$DIST_DIR"
