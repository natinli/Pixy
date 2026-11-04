#!/usr/bin/env bash
#
# 把某个 release 的版本号与校验和同步到 Homebrew tap 的 cask 里。
#
# 用法：
#   scripts/update-cask.sh              # 版本取 project.pbxproj 的 MARKETING_VERSION
#   scripts/update-cask.sh 0.1.0        # 显式指定
#   scripts/update-cask.sh --no-push    # 只改本地 tap，不 push
#
# tap 默认用 Homebrew 自己克隆的那份（装过 brew tap natinli/pixy 就有）。
# 想指向别的 checkout，设置 PIXY_TAP_DIR。

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

push=true
version=
for arg in "$@"; do
    case "$arg" in
        --no-push) push=false ;;
        -*) echo "未知选项：${arg}" >&2; exit 1 ;;
        *) version="$arg" ;;
    esac
done

if [ -z "$version" ]; then
    version=$(grep -m1 'MARKETING_VERSION' FlowVision.xcodeproj/project.pbxproj \
        | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d '[:space:]')
fi
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "版本号格式不对：${version}" >&2
    exit 1
fi

tap_dir=${PIXY_TAP_DIR:-"$(brew --repository)/Library/Taps/natinli/homebrew-pixy"}
cask_file="${tap_dir}/Casks/pixy.rb"
if [ ! -f "$cask_file" ]; then
    echo "找不到 tap 里的 cask：${cask_file}" >&2
    echo "先 brew tap natinli/pixy，或用 PIXY_TAP_DIR 指定 tap 的 checkout。" >&2
    exit 1
fi

asset="Pixy-${version}-universal-unsigned.zip"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "读取 v${version} 的校验和清单"
gh release download "v${version}" --repo natinli/Pixy \
    --pattern SHA256SUMS.txt --dir "$tmp" --clobber

sha=$(awk -v asset="$asset" '$2 == asset { print $1 }' "${tmp}/SHA256SUMS.txt")
if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "SHA256SUMS.txt 里没有 ${asset} 的条目。" >&2
    exit 1
fi

echo "版本 ${version}，${asset} 的 sha256：${sha}"

sed -i '' -E "s|^  version \".*\"$|  version \"${version}\"|" "$cask_file"
sed -i '' -E "s|^  sha256 \".*\"$|  sha256 \"${sha}\"|" "$cask_file"

if git -C "$tap_dir" diff --quiet -- Casks/pixy.rb; then
    echo "tap 已经是 ${version}，无需改动。"
    exit 0
fi

git -C "$tap_dir" add Casks/pixy.rb
git -C "$tap_dir" commit -q -m "chore: 更新到 Pixy ${version}"
echo "已提交：$(git -C "$tap_dir" log --oneline -1)"

if $push; then
    git -C "$tap_dir" push -q origin HEAD
    echo "已推送。用户更新方式：brew update && brew upgrade --cask pixy"
else
    echo "未推送（--no-push）。需要时手动 git -C \"${tap_dir}\" push origin HEAD"
fi
