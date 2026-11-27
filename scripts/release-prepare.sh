#!/usr/bin/env bash
#
# 发版前的本地准备：把「改版本号与 build 号、转 CHANGELOG、补 checklist 骨架、跑两个检查」串成一步。
#
# 用法：
#   scripts/release-prepare.sh <版本> [--dry-run] [--allow-dirty]
#
#   <版本>          X.Y.Z 三段数字（可带前导 v：v0.0.7 与 0.0.7 等价），必须严格大于 project.pbxproj
#                   里 FlowVision 目标当前的 MARKETING_VERSION（按数值比较，0.0.10 大于 0.0.9）
#   --dry-run       只做检查并打印计划，不写任何文件（两个检查脚本是只读的，dry-run 里也会照常运行）
#   --allow-dirty   允许工作区有无关的未提交改动（默认拒绝；放行后提交时只能 add 脚本改的那三个文件）
#   -h, --help      显示本说明
#
# 只做本地、可回退的文件改动：
#   FlowVision.xcodeproj/project.pbxproj      FlowVision 目标的 MARKETING_VERSION ×2、CURRENT_PROJECT_VERSION ×2
#   CHANGELOG.md                              「## [Fork] 未发布」换成「## [Fork] <日期> — <版本>」并补未签名说明
#   docs/dev/release-smoke-checklist.md       「## 记录」段顶部插入本版骨架
# 不联网、不 commit、不 push、不打 tag、不构建发布包、不装机、不更新 tap；收尾只打印接下来要手动执行的步骤。
# 改写中途任何一步失败，已改的文件会还原。
#
# build 号 = YYYYMMDDNN：今天的日期 + 当天第几版（从 01 起）。当前 build 号已是今天的就序号 +1，否则 01；
# 当前 build 号的日期晚于今天、不是 10 位数字、序号已到 99 都拒绝。
#
# 环境变量（仅供测试）：PIXY_RELEASE_DATE=YYYYMMDD 覆盖「今天」。
#
# 退出码：0 成功；1 被前置检查拒绝（未改任何文件）；2 命令行参数错误；
#         3 改写失败（已还原）；4 改动已写入但检查脚本未通过（改动保留，同时打印后续步骤与怎么修复 / 放弃）。
#
# 兼容 macOS 自带的 bash 3.2：不用关联数组、mapfile、${var,,}；日期用 BSD date。

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
EDIT="$SCRIPT_DIR/release-prepare-edit.py"

PBXPROJ_REL="FlowVision.xcodeproj/project.pbxproj"
CHANGELOG_REL="CHANGELOG.md"
CHECKLIST_REL="docs/dev/release-smoke-checklist.md"
FILES=("$PBXPROJ_REL" "$CHANGELOG_REL" "$CHECKLIST_REL")

usage() {
    # 打印文件头部的注释块（到第一个非注释行为止），去掉前缀
    sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed -e 's/^# \{0,1\}//' -e 's/^#$//'
}

# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------

dry_run=0
allow_dirty=0
have_version=0
version_arg=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --allow-dirty) allow_dirty=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "未知选项：$arg" >&2; usage >&2; exit 2 ;;
        *)
            if [ "$have_version" -eq 1 ]; then
                echo "只能给一个版本号（已有 \"$version_arg\"，又多了 \"$arg\"）" >&2
                exit 2
            fi
            have_version=1
            version_arg=$arg
            ;;
    esac
done
if [ "$have_version" -eq 0 ]; then
    echo "缺少版本号参数。" >&2
    usage >&2
    exit 2
fi

version=${version_arg#v}
version_re='^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$'
if ! [[ $version =~ $version_re ]]; then
    echo "版本号格式不对：\"$version_arg\"。需要 X.Y.Z 三段数字（可带前导 v，不带前导零，如 0.0.7 或 v0.0.7）。" >&2
    exit 2
fi

if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
    echo "拒绝：本脚本只支持 macOS（用到 BSD 的 date -j 和系统自带的 plutil）。" >&2
    exit 1
fi

today=${PIXY_RELEASE_DATE:-$(date +%Y%m%d)}
date_re='^[0-9]{8}$'
if ! [[ $today =~ $date_re ]] || [ "$(date -j -f %Y%m%d "$today" +%Y%m%d 2>/dev/null || true)" != "$today" ]; then
    echo "日期不合法：\"$today\"（PIXY_RELEASE_DATE 需要是真实存在的 YYYYMMDD）。" >&2
    exit 2
fi
today_iso="${today:0:4}-${today:4:2}-${today:6:2}"

# ---------------------------------------------------------------------------
# 收集问题：能一次说清的都一次说清，最后统一拒绝
# ---------------------------------------------------------------------------

problems=""
problem_count=0
problem() {  # problem <多行文本>：首行加「- 」，续行缩进
    local text=$1
    problems="${problems}  - $(printf '%s' "$text" | sed '2,$s/^/    /')"$'\n'
    problem_count=$((problem_count + 1))
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pixy-release-prepare.XXXXXX")
KEEP_WORK=0
EDIT_STATE=idle   # idle -> editing（已开始写文件，失败要还原）-> done

rollback() {
    local i f failed=0
    echo "改写没有完成，正在还原已改的文件……" >&2
    for i in 0 1 2; do
        f="$ROOT_DIR/${FILES[$i]}"
        if ! cmp -s "$WORK/bak.$i" "$f"; then
            { cat "$WORK/bak.$i" > "$f"; } 2>/dev/null || failed=1
        fi
        cmp -s "$WORK/bak.$i" "$f" || failed=1
    done
    if [ "$failed" -eq 0 ]; then
        echo "已还原：三个文件与改动前逐字节一致。修复上面报的原因后，可以直接重跑本脚本。" >&2
    else
        KEEP_WORK=1
        echo "还原失败！改动前的备份保留在 ${WORK}（bak.0 = pbxproj，bak.1 = CHANGELOG，bak.2 = checklist）。" >&2
        echo "请手动对照还原；工作区本来干净时也可以 git checkout -- ${FILES[0]} ${FILES[1]} ${FILES[2]}" >&2
    fi
}

cleanup() {
    local rc=$?
    trap - EXIT
    trap '' INT TERM HUP   # 回滚进行中再按 Ctrl-C 不能把还原打断在半路
    if [ "$EDIT_STATE" = "editing" ]; then
        rollback
        [ "$rc" -eq 0 ] && rc=3
    elif [ "$EDIT_STATE" = "done" ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
        # 三个文件已改完，之后（跑检查时）被打断或意外退出：不还原，但要说清现状
        echo "脚本在改动写入之后退出（退出码 ${rc}）：三个文件的改动仍在，没有还原；git diff --stat 可查看。要放弃：git checkout -- ${FILES[0]} ${FILES[1]} ${FILES[2]}（工作区本来就有未提交改动时先 git diff 看清再还原）。" >&2
    fi
    if [ "$KEEP_WORK" -eq 0 ]; then
        rm -rf "$WORK"
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ---------------------------------------------------------------------------
# 环境与仓库
# ---------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || { echo "拒绝：找不到 git。" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "拒绝：找不到 python3（改写文件要用）。" >&2; exit 1; }
command -v plutil >/dev/null 2>&1 || { echo "拒绝：找不到 plutil（校验 pbxproj 要用，macOS 自带）。" >&2; exit 1; }
[ -f "$EDIT" ] || { echo "拒绝：找不到改写助手 ${EDIT}。" >&2; exit 1; }

top=$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$ROOT_DIR" ]; then
    echo "拒绝：$ROOT_DIR 不是一个 git 仓库的根目录（本脚本要靠 git 判断工作区是否干净、tag 是否已存在）。" >&2
    exit 1
fi
cd "$ROOT_DIR"

for f in "${FILES[@]}"; do
    [ -f "$f" ] || problem "找不到 ${f}（要在仓库根下运行，且文件没有被删）。"
done

branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 前置检查
# ---------------------------------------------------------------------------

# 1. 工作区
dirty=$(git status --porcelain) || { echo "拒绝：git status 失败，无法判断工作区是否干净。" >&2; exit 1; }
dirty_target_files=""
if [ -n "$dirty" ]; then
    if [ "$allow_dirty" -eq 0 ]; then
        problem "$(printf '工作区不干净，拒绝在上面改版本号（0.0.6 发版时就出现过别的会话并行留下的无关改动）。未提交的内容：\n%s\n先提交或 stash，或确认无关后加 --allow-dirty。' "$dirty")"
    else
        dirty_target_files=$(git status --porcelain -- "${FILES[@]}")
    fi
fi

# 2. pbxproj：当前版本与 build 号
cur_version=""
cur_build=""
if [ -f "$PBXPROJ_REL" ]; then
    if pb_out=$(python3 -I "$EDIT" pbxproj read "$PBXPROJ_REL" 2>"$WORK/err"); then
        cur_version=${pb_out%% *}
        cur_build=${pb_out##* }
    else
        problem "$(cat "$WORK/err")"
    fi
fi

# 3. 版本号严格递增（数值比较）
version_gt() {  # version_gt NEW OLD：NEW 严格大于 OLD 时返回 0
    local i x y
    for i in 1 2 3; do
        x=$(printf '%s' "$1" | cut -d. -f"$i")
        y=$(printf '%s' "$2" | cut -d. -f"$i")
        x=$((10#$x))
        y=$((10#$y))
        [ "$x" -gt "$y" ] && return 0
        [ "$x" -lt "$y" ] && return 1
    done
    return 1
}
version_ok=0   # 当前版本合法且目标版本严格更大：pbxproj 的改写计划才有意义
if [ -n "$cur_version" ]; then
    if ! [[ $cur_version =~ $version_re ]]; then
        problem "pbxproj 里当前的 MARKETING_VERSION 是 \"$cur_version\"，不是 X.Y.Z 三段数字，无法比较。"
    elif ! version_gt "$version" "$cur_version"; then
        problem "版本号 $version 没有严格大于当前版本 ${cur_version}（pbxproj 的 MARKETING_VERSION）。版本只增不减，也不能重复。"
    else
        version_ok=1
    fi
fi

# 4. build 号：YYYYMMDDNN
new_build=""
if [ -n "$cur_build" ]; then
    build_re='^[0-9]{10}$'
    if ! [[ $cur_build =~ $build_re ]]; then
        problem "pbxproj 里当前的 CURRENT_PROJECT_VERSION 是 \"$cur_build\"，不是 10 位数字（YYYYMMDDNN）。历史上 8 位日期踩过「位数变短数值反而变小」的坑（见 release.md），先手工改正再运行。"
    else
        cur_day=${cur_build:0:8}
        cur_seq=$((10#${cur_build:8:2}))
        if [ $((10#$cur_day)) -gt $((10#$today)) ]; then
            problem "当前 build 号 $cur_build 的日期部分 $cur_day 晚于今天 ${today}：时钟倒退，或 build 号写错了。build 号必须只增不减，不能自动给出更小的号。"
        elif [ "$cur_day" = "$today" ]; then
            if [ "$cur_seq" -ge 99 ]; then
                problem "今天（${today}）的 build 序号已经到 ${cur_build}，再加一就超出两位序号了；等明天，或先手工处理 build 号规则。"
            else
                new_build=$(printf '%s%02d' "$today" $((cur_seq + 1)))
            fi
        else
            new_build="${today}01"
        fi
        if [ -n "$new_build" ] && [ $((10#$new_build)) -le $((10#$cur_build)) ]; then
            problem "内部校验失败：算出的 build 号 $new_build 不大于当前的 ${cur_build}。"
            new_build=""
        fi
    fi
fi

# 5. 目标版本不能已经存在（只能查本地：不联网）
if [ -n "$(git tag -l "v$version")" ]; then
    problem "本地已有 tag v${version}。"
fi

# 6. 三个文件能否改（结构、内容、重复），顺便得到 dry-run 要打印的计划
plan_pbxproj=""
plan_changelog=""
plan_checklist=""
if [ -f "$CHANGELOG_REL" ]; then
    if plan_changelog=$(python3 -I "$EDIT" changelog edit "$CHANGELOG_REL" --version "$version" --date "$today_iso" --dry-run 2>"$WORK/err"); then
        :
    else
        problem "$(cat "$WORK/err")"
    fi
fi
if [ "$version_ok" -eq 1 ] && [ -n "$new_build" ]; then
    if plan_pbxproj=$(python3 -I "$EDIT" pbxproj edit "$PBXPROJ_REL" --old-version "$cur_version" --old-build "$cur_build" \
        --new-version "$version" --new-build "$new_build" --dry-run 2>"$WORK/err"); then
        :
    else
        problem "$(cat "$WORK/err")"
    fi
fi
if [ -n "$cur_version" ] && [[ $cur_version =~ $version_re ]] && [ -n "$new_build" ]; then
    if [ -f "$CHECKLIST_REL" ]; then
        if plan_checklist=$(python3 -I "$EDIT" checklist edit "$CHECKLIST_REL" --version "$version" --build "$new_build" \
            --prev-version "$cur_version" --prev-build "$cur_build" --date "$today_iso" --dry-run 2>"$WORK/err"); then
            :
        else
            problem "$(cat "$WORK/err")"
        fi
    fi
fi

if [ "$problem_count" -gt 0 ]; then
    {
        echo "拒绝发版准备（$problem_count 个问题）："
        printf '%s' "$problems"
        echo "没有改动任何文件。"
    } >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 检查脚本与收尾说明
# ---------------------------------------------------------------------------

run_checks() {  # 两个检查都跑完再汇总，返回 0 全过 / 1 有失败
    local failed=0
    echo "== 发布前检查（只读）=="
    if ! sh "$ROOT_DIR/scripts/check-public-hygiene.sh"; then
        echo "未通过：scripts/check-public-hygiene.sh" >&2
        failed=1
    fi
    if ! python3 -X utf8 "$ROOT_DIR/scripts/check-localization.py"; then   # -X utf8：不依赖 locale（系统自带的 Python 3.9 在非 UTF-8 locale 下打印中文会抛异常）
        echo "未通过：scripts/check-localization.py" >&2
        failed=1
    fi
    return "$failed"
}

print_next_steps() {
    local tag="v$version"
    local push_branch=${branch:-main}
    cat <<EOF

== 接下来请手动执行（脚本不会代劳，以下命令只是打印）==
 1. 复核改动（应只有 3 个文件）：
      git diff --stat
 2. 构建并验收未签名包（约 4 分钟；产物在 dist/）：
      scripts/release.sh --unsigned
    产物核对要点（解压 ZIP 到一个临时目录后对其中的 Pixy.app 检查）：
      (cd dist && shasum -a 256 -c SHA256SUMS.txt)                                  # 全部 OK
      lipo -archs Pixy.app/Contents/MacOS/Pixy                                      # x86_64 arm64
      codesign -dv Pixy.app 2>&1 | grep -E 'Signature|TeamIdentifier'               # Signature=adhoc、TeamIdentifier=not set
      codesign --verify --deep --strict --verbose=2 Pixy.app                        # 通过
      spctl --assess --type execute Pixy.app                                        # rejected 是预期（未签名版）
      /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Pixy.app/Contents/Info.plist   # $version
      /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Pixy.app/Contents/Info.plist              # $new_build
 3. 把本地产物的哈希与验收结果填进 $CHECKLIST_REL
    里新增的「### ${version}（未签名版）」骨架（本地产物与 CI 附件的哈希不同，两组都要记）。
 4. 提交，只 add 这三个文件：
      git add ${FILES[0]} ${FILES[1]} ${FILES[2]}
      git commit -m "chore(release): $version"
 5. 推送：
      git push origin $push_branch
 6. 打 tag 并推送：
      git tag -a $tag -m "Pixy $version"
      git push origin $tag
 7. 等 Release 工作流（macos-15）：
      gh run list --workflow release.yml -R natinli/Pixy --limit 3
      gh run watch <run-id> -R natinli/Pixy
    失败且注解为 "The job was not acquired by Runner of type hosted" 是 runner 容量不足，重跑即可：
      gh run rerun <run-id> --failed -R natinli/Pixy
    tag 不要重推；也不要为了 runner 容量去改工作流（见 docs/dev/release.md）。
 8. 核对 Release 页：应为 Latest、非 pre-release，附件有 ZIP、DMG、SHA256SUMS.txt：
      gh release view $tag -R natinli/Pixy
    下载附件后 shasum -a 256 -c SHA256SUMS.txt，把 CI 附件的哈希补进 checklist 并另提交一次；
    有干净用户环境时再验证一次首次启动（没有就在 checklist 里记为未覆盖）。
 9. 同步 Homebrew tap：
      scripts/update-cask.sh $version
10. 本机升级前先确认 /Applications/Pixy.app 没在运行（pgrep -x Pixy 应无输出），再：
      brew update && brew upgrade --cask pixy
    升级后第一次启动需要你自己放行（系统设置 → 隐私与安全性 → 仍要打开，见 docs/user/installation.md）。

说明：
  - 本脚本没有联网，只检查了本地 tag；远端是否已有 $tag 没有验证（推送 tag 时已存在会被拒绝）。
  - 没有 commit、没有 push、没有打 tag：改动都留在工作区，不满意可以 git checkout -- 那三个文件
    （工作区本来就有未提交改动时先 git diff 看清再还原）。
EOF
    if [ -z "$branch" ]; then
        echo "  - 注意：当前 HEAD 是游离状态，没有分支名；上面第 5 步按 main 渲染，请按实际情况调整。"
    elif [ "$branch" != "main" ]; then
        echo "  - 注意：当前分支是 ${branch}，不是 main；发布通常从 main 进行，第 5 步已按当前分支渲染。"
    fi
}

# ---------------------------------------------------------------------------
# dry-run：只打印计划
# ---------------------------------------------------------------------------

echo "发版准备：Pixy $cur_version -> ${version}（build $cur_build -> ${new_build}），日期 $today_iso"

if [ "$allow_dirty" -eq 1 ] && [ -n "$dirty" ]; then
    echo
    echo "警告：--allow-dirty：工作区有未提交的改动。提交时只能 git add 下面这三个文件，不要 git add -A / git commit -a："
    printf '  %s\n' "${FILES[@]}"
    if [ -n "$dirty_target_files" ]; then
        echo "警告：这三个文件里已经有未提交的改动（脚本的改动会叠在它们上面，一起被提交）："
        printf '%s\n' "$dirty_target_files" | sed 's/^/  /'
    fi
fi

if [ "$dry_run" -eq 1 ]; then
    echo
    echo "== dry-run：下面是计划，没有写任何文件 =="
    printf '%s\n' "$plan_pbxproj"
    printf '%s\n' "$plan_changelog"
    printf '%s\n' "$plan_checklist"
    echo
    echo "（dry-run 也会运行下面两个检查；它们是只读的，检查的是当前尚未改动的工作区。）"
    if ! run_checks; then
        echo "dry-run 结束：检查未通过（没有写任何文件）。" >&2
        exit 4
    fi
    print_next_steps
    echo
    echo "dry-run 结束：没有写任何文件。"
    exit 0
fi

# ---------------------------------------------------------------------------
# 真正改写：先备份，任何一步失败都还原
# ---------------------------------------------------------------------------

for i in 0 1 2; do
    cp -p "$ROOT_DIR/${FILES[$i]}" "$WORK/bak.$i"
done
EDIT_STATE=editing

echo
echo "== 改写文件 =="
python3 -I "$EDIT" pbxproj edit "$PBXPROJ_REL" --old-version "$cur_version" --old-build "$cur_build" \
    --new-version "$version" --new-build "$new_build" || exit 3
python3 -I "$EDIT" changelog edit "$CHANGELOG_REL" --version "$version" --date "$today_iso" || exit 3
python3 -I "$EDIT" checklist edit "$CHECKLIST_REL" --version "$version" --build "$new_build" \
    --prev-version "$cur_version" --prev-build "$cur_build" --date "$today_iso" || exit 3
EDIT_STATE=done

echo
git --no-pager diff --stat -- "${FILES[@]}" || true

echo
if ! run_checks; then
    {
        echo
        echo "== 检查未通过：改动已写入，没有还原 =="
        echo " - 先按上面的报错修复。两个检查都是只读的，修复后可以单独重跑："
        echo "     sh scripts/check-public-hygiene.sh"
        echo "     python3 scripts/check-localization.py"
        echo " - 不要重跑本脚本：版本号已经是 ${version}，会被「没有严格大于当前版本」拒绝（工作区也已不干净）。"
        echo " - 想放弃这次改动重来：git checkout -- ${FILES[0]} ${FILES[1]} ${FILES[2]}"
        echo "   （工作区本来就有未提交改动时先 git diff 看清再还原）。"
        echo " - 检查通过之后照常往下走；后续步骤与全部通过时打印的相同，附在下面："
    }
    print_next_steps
    echo >&2
    echo "退出码 4：改动已写入，但上面的检查没有通过；修复并确认检查通过之前，不要提交、推送、打 tag。" >&2
    exit 4
fi

print_next_steps
