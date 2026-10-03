#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

private_path='/Developer/pixy''-deps'
patterns="FPUF[[:alnum:]]{6,}|/Users/[^/[:space:]]+|$private_path|DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{6,}"
if rg -n --hidden --glob '!.git/**' --glob '!.build/**' --glob '!DerivedData/**' --glob '!build/**' --glob '!scripts/check-public-hygiene.sh' --glob '!FlowVision/Resources/Localizable.xcstrings' "$patterns" .; then
    echo "公开仓库检查失败：发现开发机路径、Team ID 或个人邮箱。" >&2
    exit 1
fi

for forbidden in '*.p12' '*.mobileprovision' '*.xcarchive' '*.dmg' '*.zip'; do
    if find . -path './.git' -prune -o -path './.build' -prune -o -name "$forbidden" -print | grep -q .; then
        echo "公开仓库检查失败：发现不应提交的发布产物或凭据文件（$forbidden）。" >&2
        exit 1
    fi
done

echo "公开仓库检查通过。"
