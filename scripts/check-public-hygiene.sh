#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

# 只检查会被公开提交的文件（git ls-files），不扫工作树：
# 这样 .gitignore 里的 LocalDev.xcconfig、dist/、.build/ 不会被误报，
# 同时“忘记 gitignore 就提交上去”的凭据文件仍然会被 find 段捕获。
#
# 早期版本调用 rg，但 rg 在 macOS 和 GitHub Actions runner 上默认都不存在；
# 由于 `if rg ...` 在 set -eu 下失败被视为假，扫描会被整段跳过并打印“通过”，
# 形成 fail-open 的发布门禁。这里改为只用系统自带工具，并采用 fail-closed 逻辑。

command -v git >/dev/null 2>&1 || {
    echo "公开仓库检查失败：缺少 git，无法枚举待发布文件。" >&2
    exit 1
}
command -v grep >/dev/null 2>&1 || {
    echo "公开仓库检查失败：缺少 grep，无法执行敏感信息扫描。" >&2
    exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "公开仓库检查失败：当前目录不是 git 工作树。" >&2
    exit 1
}

private_path='/Developer/pixy''-deps'
patterns="FPUF[[:alnum:]]{6,}|/Users/[^/[:space:]]+|\
$private_path|DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{6,}"

tracked_files=$(git ls-files)
if [ -z "$tracked_files" ]; then
    echo "公开仓库检查失败：没有找到任何被跟踪的文件。" >&2
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pixy-hygiene.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
list_file="$work_dir/files.txt"
findings_file="$work_dir/findings.txt"
printf '%s\n' "$tracked_files" > "$list_file"
: > "$findings_file"

# 逐文件扫描并显式区分退出码：0=命中，1=未命中，>1=出错。
# 不依赖 xargs 的退出码约定（BSD 与 GNU 对 1-125 的映射不同），
# 也不能让 grep 的 1 被 set -e 当成扫描失败。
while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
        scripts/check-public-hygiene.sh) continue ;;
        FlowVision/Resources/Localizable.xcstrings) continue ;;
    esac
    grep_rc=0
    grep -EnI -- "$patterns" "$file" >> "$findings_file" || grep_rc=$?
    if [ "$grep_rc" -gt 1 ]; then
        echo "公开仓库检查失败：扫描 $file 时出错（grep 退出码 $grep_rc）。" >&2
        exit 1
    fi
done < "$list_file"

if [ -s "$findings_file" ]; then
    cat "$findings_file" >&2
    echo "公开仓库检查失败：发现开发机路径、Team ID 或个人邮箱。" >&2
    exit 1
fi

for forbidden in '*.p12' '*.mobileprovision' '*.xcarchive' '*.dmg' '*.zip'; do
    case "$forbidden" in
        '*.p12')           pattern='\.p12$' ;;
        '*.mobileprovision') pattern='\.mobileprovision$' ;;
        '*.xcarchive')     pattern='\.xcarchive/' ;;
        '*.dmg')           pattern='\.dmg$' ;;
        '*.zip')           pattern='\.zip$' ;;
    esac
    if printf '%s\n' "$tracked_files" | grep -Eq -- "$pattern"; then
        echo "公开仓库检查失败：发现不应提交的发布产物或凭据文件（$forbidden）。" >&2
        exit 1
    fi
done

echo "公开仓库检查通过。"
