#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

check_contains() {
    file=$1
    value=$2
    if ! rg -F -q -- "$value" "$file"; then
        echo "依赖来源检查失败：$file 缺少 $value" >&2
        exit 1
    fi
}

check_contains FlowVision.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved '407fda73e18cc9df9130453ee36f73408c22408f'
check_contains FlowVision.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 'f41475771f65379ca10852c95119a7f53f0de5a5'
check_contains THIRD_PARTY_NOTICES.md '412b1b57c91435b69d7a728162611bbabdb384020aee5b558ceedf3944d94d0d'
check_contains THIRD_PARTY_NOTICES.md 'FFmpegKit full-gpl'
check_contains THIRD_PARTY_NOTICES.md 'Icons8'

printf '%s\n' '第三方依赖来源与许可证检查通过。'
