#!/usr/bin/env bash
# scripts/release-prepare.sh 的本机回归测试（不进 CI；需要 macOS 的 plutil、BSD sed/date）。
#
# 每个场景都在 `git clone` 出来的临时副本里跑（/tmp 下，结束时清理），用 PIXY_RELEASE_DATE 固定日期；
# 真实仓库只被克隆（只读）：开始前后各取一次指纹（git status、HEAD、全部 ref、stash、三个关键文件的哈希），
# 不一致就失败。不联网：git 与网络/安装类命令（gh、brew、curl、xcodebuild……）都换成记录调用的垫片，
# 断言被测脚本只用了只读的 git 子命令、一次网络/安装类命令都没调用。
#
# 夹具：克隆后把 FlowVision 目标改成 0.0.9 / build 2025010101（日期取得足够早，用真实时钟也不会撞车），
# CHANGELOG 换成一个确定内容的「未发布」小节，把工作区里的两个脚本拷进副本并提交，之后每个场景再从这个基础副本克隆。
#
# 用法：scripts/test-release-prepare.sh        有失败时退出码为 1。
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SELF="$SCRIPT_DIR/$(basename "$0")"
REPO=$(cd "$SCRIPT_DIR/.." && pwd -P)
RP="$SCRIPT_DIR/release-prepare.sh"
RPE="$SCRIPT_DIR/release-prepare-edit.py"
GIT=$(command -v git)
PB=FlowVision.xcodeproj/project.pbxproj
CL=CHANGELOG.md
CK=docs/dev/release-smoke-checklist.md
TAB=$'\t'

FIX_VER=0.0.9
FIX_BUILD=2025010101
D1=20250101   # 夹具 build 号所在的日子
D2=20250102   # 次日

command -v plutil >/dev/null 2>&1 || { echo "需要 macOS 的 plutil" >&2; exit 1; }
[ -f "$RP" ] && [ -f "$RPE" ] || { echo "找不到被测脚本" >&2; exit 1; }

TMP=$(mktemp -d /tmp/release-prepare-test.XXXXXX)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
WDIR="$TMP/wd"   # 被测脚本的 TMPDIR：结束时应当是空的（所有场景——成功、拒绝、还原、检查失败——都要清掉自己的工作目录）
mkdir -p "$WDIR"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
has()   { case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1（输出里没有「$2」）" ;; esac; }
hasnt() { case "$OUT" in *"$2"*) bad "$1（输出里不该有「$2」）" ;; *) ok "$1" ;; esac; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望「$3」，实际「$2」）"; fi; }
rc_is() {
    if [ "$RC" -eq "$2" ]; then ok "$1（退出码 ${RC}）"; else bad "$1：退出码应为 $2，实际 $RC"; printf '%s\n' "$OUT" | sed 's/^/      | /' | tail -30; fi
}

# ---------------------------------------------------------------------------
# 垫片：记录 git 调用并放行；网络/安装类命令一律记录后失败
# ---------------------------------------------------------------------------
SHIM="$TMP/shim"
GITLOG="$TMP/git-calls.log"
NETLOG="$TMP/net-calls.log"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$GITLOG"
exec "$GIT" "\$@"
EOF
for tool in gh brew curl wget xcodebuild hdiutil ssh open scp; do
    cat > "$SHIM/$tool" <<EOF
#!/bin/sh
printf '%s %s\n' "$tool" "\$*" >> "$NETLOG"
exit 99
EOF
done
chmod +x "$SHIM"/*

# 记录到的 git 子命令（去掉 -C <路径> 与选项）；tag 连同第一个参数
git_subcommands() {
    awk '{ i = 1
           while (i <= NF) { if ($i == "-C") { i += 2; continue } if ($i ~ /^-/) { i++; continue } break }
           if ($i == "tag") print $i " " $(i + 1); else print $i }' "$GITLOG" | sort -u
}
only_readonly_git() { ! git_subcommands | grep -vxE 'diff|ls-files|rev-parse|status|symbolic-ref|tag -l'; }

# ---------------------------------------------------------------------------
# 真实仓库指纹
# ---------------------------------------------------------------------------
real_fingerprint() {
    {
        "$GIT" -C "$REPO" status --porcelain
        "$GIT" -C "$REPO" rev-parse HEAD
        "$GIT" -C "$REPO" for-each-ref
        "$GIT" -C "$REPO" stash list
        shasum "$REPO/$PB" "$REPO/$CL" "$REPO/$CK"
    } 2>&1 | shasum | cut -d' ' -f1
}
REAL_BEFORE=$(real_fingerprint)

# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------
BASE="$TMP/base"
git_in() { local d=$1; shift; "$GIT" -C "$d" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
git_c() { git_in "$C" "$@"; }
commit_c() { git_c add -A && git_c commit -q -m "${1:-fixture}"; }

"$GIT" clone -q "$REPO" "$BASE" || { echo "克隆真实仓库失败" >&2; exit 1; }

cur_v=$(grep -E 'MARKETING_VERSION = ' "$BASE/$PB" | grep -v 'MARKETING_VERSION = 1.0;' | head -1 | sed -E 's/.*= ([^;]+);.*/\1/')
cur_b=$(grep -E 'CURRENT_PROJECT_VERSION = ' "$BASE/$PB" | grep -v 'CURRENT_PROJECT_VERSION = 1;' | head -1 | sed -E 's/.*= ([^;]+);.*/\1/')
[ -n "$cur_v" ] && [ -n "$cur_b" ] || { echo "夹具：认不出 pbxproj 里 Pixy 目标的版本与 build 号" >&2; exit 1; }
sed -i '' -e "s/MARKETING_VERSION = $cur_v;/MARKETING_VERSION = $FIX_VER;/" \
          -e "s/CURRENT_PROJECT_VERSION = $cur_b;/CURRENT_PROJECT_VERSION = $FIX_BUILD;/" "$BASE/$PB"
[ "$(grep -c "MARKETING_VERSION = $FIX_VER;" "$BASE/$PB")" = 2 ] && [ "$(grep -c "CURRENT_PROJECT_VERSION = $FIX_BUILD;" "$BASE/$PB")" = 2 ] \
    || { echo "夹具：改写 pbxproj 的版本后各应恰有 2 处" >&2; exit 1; }

python3 -I - "$BASE/$CL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out, skip = [], False
for line in lines:
    if line.rstrip() == "## [Fork] 未发布":
        skip = True
        continue
    if skip and line.startswith("## "):
        skip = False
    if not skip:
        out.append(line)
first = next(i for i, line in enumerate(out) if line.startswith("## [Fork]"))
out[first:first] = ["## [Fork] 未发布", "", "### 测试夹具：这一段只在测试里出现", "", "夹具内容。", ""]
open(p, "w", encoding="utf-8").write("\n".join(out))
PY
cp "$RP" "$RPE" "$BASE/scripts/"
chmod +x "$BASE/scripts/release-prepare.sh" "$BASE/scripts/release-prepare-edit.py"
git_in "$BASE" add -A && git_in "$BASE" commit -q -m fixture || { echo "夹具提交失败" >&2; exit 1; }
BRANCH=$(git_in "$BASE" symbolic-ref --short HEAD)

# 新场景：从基础副本克隆；C = 副本路径
RUN_DATE=$D2
RUN_CWD=""
RUN_ENV=""      # 额外的环境变量赋值（空格分隔，如 LC_ALL=en_US.UTF-8），只用于 locale 测试
RUN_PYBIN=""    # 非空：放在 PATH 最前，用来换一个 python3（如系统自带的 3.9）或别的命令（如假装不是 Darwin 的 uname）
new_case() {
    C="$TMP/case-$1"
    "$GIT" clone -q "$BASE" "$C"
    RUN_DATE=$D2
    RUN_CWD=""
    RUN_ENV=""
    RUN_PYBIN=""
}

# 在 C 里用 /bin/bash（macOS 的 3.2）跑副本里的脚本；OUT = 合并输出，RC = 退出码
run_rp() {
    : > "$GITLOG"
    : > "$NETLOG"
    OUT=$(cd "${RUN_CWD:-$C}" && env ${RUN_ENV:-} TMPDIR="$WDIR" PIXY_RELEASE_DATE="$RUN_DATE" PATH="$SHIM:${RUN_PYBIN:+$RUN_PYBIN:}$PATH" /bin/bash "$C/scripts/release-prepare.sh" "$@" 2>&1)
    RC=$?
}
run_rp_real_clock() {
    : > "$GITLOG"
    : > "$NETLOG"
    OUT=$(cd "$C" && env -u PIXY_RELEASE_DATE TMPDIR="$WDIR" PATH="$SHIM:$PATH" /bin/bash "$C/scripts/release-prepare.sh" "$@" 2>&1)
    RC=$?
}

# 副本的完整状态指纹：status（含被忽略的）、HEAD、三个关键文件
tree_state() {
    {
        git_c status --porcelain --ignored
        git_c rev-parse HEAD
        (cd "$C" && shasum "$PB" "$CL" "$CK" 2>/dev/null)
    } | shasum | cut -d' ' -f1
}
unchanged_since() { [ "$(tree_state)" = "$1" ]; }

# 夹具里 pbxproj 的当前 build 号改成 $1 并提交
set_build() { sed -i '' "s/CURRENT_PROJECT_VERSION = $FIX_BUILD;/CURRENT_PROJECT_VERSION = $1;/" "$C/$PB"; commit_c "set build $1"; }
set_version() { sed -i '' "s/MARKETING_VERSION = $FIX_VER;/MARKETING_VERSION = $1;/" "$C/$PB"; commit_c "set version $1"; }

cl_mutate() {
    python3 -I - "$C/$CL" "$1" <<'PY'
import sys
p, mode = sys.argv[1:3]
lines = open(p, encoding="utf-8").read().split("\n")
H = "## [Fork] 未发布"
i = lines.index(H)
end = next(k for k in range(i + 1, len(lines)) if lines[k].startswith("## "))
if mode == "rename":
    lines[i] = "## [Fork] 草稿"
elif mode == "empty":
    lines[i + 1:end] = ["", ""]
elif mode == "dup":
    lines[end:end] = [H, "", "第二个未发布小节。", ""]
elif mode == "has-version":
    lines[end:end] = ["## [Fork] 2025-01-01 — 0.0.10", "", "已有同版本小节。", ""]
else:
    sys.exit("unknown mode " + mode)
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
    commit_c "changelog $1"
}

hash3() { (cd "$C" && shasum "$PB" "$CL" "$CK" | cut -d' ' -f1 | tr '\n' ' '); }
# 模拟用户在跑脚本之前就已有的未提交改动：pbxproj 里一行无关设置、CHANGELOG 末尾一行、一个无关的未跟踪文件
user_dirty() {
    python3 -I - "$C" <<'PY'
import sys
root = sys.argv[1]
p = root + "/FlowVision.xcodeproj/project.pbxproj"
s = open(p, encoding="utf-8", newline="").read()
assert "GCC_OPTIMIZATION_LEVEL = 0;" in s
open(p, "w", encoding="utf-8", newline="").write(s.replace("GCC_OPTIMIZATION_LEVEL = 0;", "GCC_OPTIMIZATION_LEVEL = s;", 1))
c = root + "/CHANGELOG.md"
t = open(c, encoding="utf-8", newline="").read()
open(c, "w", encoding="utf-8", newline="").write(t + "\n用户手写的未提交行\n")
open(root + "/stray.txt", "w").write("stray\n")
PY
}
# 文本边界：把副本里的三个文件改成某种形态并提交
mutate() {
    python3 -I - "$C" "$1" "$FIX_VER" "$FIX_BUILD" <<'PY'
import sys
root, mode, ver, build = sys.argv[1:5]
CL = root + "/CHANGELOG.md"; CK = root + "/docs/dev/release-smoke-checklist.md"; PB = root + "/FlowVision.xcodeproj/project.pbxproj"
def rd(p): return open(p, encoding="utf-8", newline="").read()
def wr(p, s): open(p, "w", encoding="utf-8", newline="").write(s)
if mode == "crlf-cl": wr(CL, rd(CL).replace("\n", "\r\n"))
elif mode == "crlf-ck": wr(CK, rd(CK).replace("\n", "\r\n"))
elif mode == "crlf-pb": wr(PB, rd(PB).replace("\n", "\r\n"))
elif mode == "noeol-cl": wr(CL, rd(CL).rstrip("\n"))
elif mode == "noeol-ck": wr(CK, rd(CK).rstrip("\n"))
elif mode == "unreleased-last-noeol": wr(CL, "# 变更记录\n\n## [Fork] 未发布\n\n- 只有这一条")
elif mode == "unreleased-immediate-next": wr(CL, rd(CL).replace("## [Fork] 未发布\n", "## [Fork] 未发布\n- 紧贴标题的正文\n", 1))
elif mode == "fence-only":
    wr(CL, "# 变更记录\n\n示例：\n\n```markdown\n## [Fork] 未发布\n\n- 示例\n```\n\n## [Fork] 2025-01-01 — 0.0.9\n\n仍为**未签名**版本。\n")
elif mode == "fence-before":
    wr(CL, rd(CL).replace("## [Fork] 未发布\n", "```\n## [Fork] 未发布\n```\n\n## [Fork] 未发布\n", 1))
elif mode == "fence-hash-in-section":
    wr(CL, rd(CL).replace("## [Fork] 未发布\n\n", "## [Fork] 未发布\n\n```bash\n## 注释\nls\n```\n\n", 1))
elif mode == "blockquote": wr(CL, "# x\n\n> ## [Fork] 未发布\n> - 引用里的\n\n## [Fork] 2025-01-01 — 0.0.9\n\n正文\n")
elif mode == "ck-fence": wr(CK, rd(CK).replace("## 记录\n", "```\n## 记录\n```\n\n## 记录\n", 1))
elif mode == "ck-nogap": wr(CK, rd(CK).replace("## 记录\n\n", "## 记录\n", 1))
elif mode == "ck-last":
    s = rd(CK); i = s.index("## 记录"); wr(CK, s[:i] + "## 记录\n")
elif mode == "ck-last-noeol":
    s = rd(CK); i = s.index("## 记录"); wr(CK, s[:i] + "## 记录")
elif mode == "pb-quoted": wr(PB, rd(PB).replace("MARKETING_VERSION = %s;" % ver, 'MARKETING_VERSION = "%s";' % ver, 1))
elif mode == "pb-nosemi": wr(PB, rd(PB).replace("MARKETING_VERSION = %s;" % ver, "MARKETING_VERSION = %s" % ver, 1))
elif mode == "pb-third":      # 把测试目标 PixyTests 也改成与 App 同值（模拟将来新增的、与 App 同值的目标）
    s = rd(PB).replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = %s;" % ver).replace("CURRENT_PROJECT_VERSION = 1;", "CURRENT_PROJECT_VERSION = %s;" % build); wr(PB, s)
elif mode == "pb-third-ver-only": wr(PB, rd(PB).replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = %s;" % ver))
elif mode == "pb-third-build-only": wr(PB, rd(PB).replace("CURRENT_PROJECT_VERSION = 1;", "CURRENT_PROJECT_VERSION = %s;" % build))
else: sys.exit("unknown mode " + mode)
PY
    commit_c "mutate $1"
}
# 注意不能用 grep -q：它找到就提前退出，locale -a 会吃 SIGPIPE，pipefail 下整条管道失败，会把存在的 locale 误判成不存在
has_locale() { locale -a 2>/dev/null | grep -x "$1" >/dev/null; }

# ===========================================================================
echo "== 0. 语法与兼容性 =="
check "bash -n release-prepare.sh" bash -n "$RP"
check "bash -n test-release-prepare.sh" bash -n "$SELF"
check "助手能通过 Python 语法解析" python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$RPE"
check "三个脚本都有可执行位" sh -c '[ -x "$1" ] && [ -x "$2" ] && [ -x "$3" ]' _ "$RP" "$RPE" "$SELF"
BASH4_RE='declare -A|local -A|mapfile|readarray|[$][{][A-Za-z_]+(,,|\^\^)'
no_bash4() { local hits; hits=$(grep -nE "$BASH4_RE" "$RP" | grep -vE '^[0-9]+:[[:space:]]*#' || true); [ -z "$hits" ]; }
check "没有 bash 4+ 专有写法（关联数组 / mapfile / readarray / 小写大写转换），注释除外" no_bash4
BASH_VER=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')
ok "测试用 /bin/bash 版本 $BASH_VER 运行被测脚本（macOS 自带为 3.2）"
# bash 3.2 在 UTF-8 locale 下，会把「美元符加变量名」后面紧跟的多字节字符（如全角括号、句号）读成变量名的一部分：
# 报 unbound variable，而且退出码是 0（脚本悄悄什么都没做）。必须写成 ${name}。
no_dollar_name_before_nonascii() {
    python3 -I - "$@" <<'PY'
import re, sys
bad = False
for path in sys.argv[1:]:
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.search(r"[$][A-Za-z_][A-Za-z_0-9]*(?=[^\x00-\x7f])", line):
            print("%s:%d: %s" % (path, n, line.strip()))
            bad = True
sys.exit(1 if bad else 0)
PY
}
check "被测脚本与本测试脚本里没有「美元符加变量名后紧跟非 ASCII 字符」的写法（要写成花括号形式）" no_dollar_name_before_nonascii "$RP" "$SELF"
check "夹具仓库本身通过 check-public-hygiene.sh" sh -c 'cd "$1" && sh scripts/check-public-hygiene.sh' _ "$BASE"
check "夹具仓库本身通过 check-localization.py" sh -c 'cd "$1" && python3 scripts/check-localization.py' _ "$BASE"
check "夹具 pbxproj 通过 plutil -lint" plutil -lint "$BASE/$PB"

# ===========================================================================
echo "== 1. 正常发版（0.0.9 -> 0.0.10，次日） =="
new_case normal
S_HEAD=$(git_c rev-parse HEAD)
S_TAGS=$(git_c tag | shasum)
S_REFS=$(git_c for-each-ref | shasum)
OLD_FIRST=$(git_c show "HEAD:$CK" | awk '/^## 记录$/ {f = 1; next} f && /^### / {print; exit}')
run_rp 0.0.10
rc_is "退出码 0" 0
# pbxproj
eq "pbxproj：恰好 4 行被改（numstat 4/4）" "$(git_c diff --numstat -- "$PB")" "4${TAB}4${TAB}$PB"
want_changed=$(printf '%s\n' \
    "2 +CURRENT_PROJECT_VERSION = 2025010201;" "2 +MARKETING_VERSION = 0.0.10;" \
    "2 -CURRENT_PROJECT_VERSION = $FIX_BUILD;" "2 -MARKETING_VERSION = $FIX_VER;")
got_changed=$(git_c diff -U0 -- "$PB" | grep -E "^[-+]${TAB}" | sed -E 's/^([-+])[[:space:]]+/\1/' | LC_ALL=C sort | uniq -c | sed -E 's/^ +//')
eq "pbxproj：改的恰是 FlowVision 目标的 2 个版本 + 2 个 build 行" "$got_changed" "$want_changed"
eq "pbxproj：旧版本值 0 处" "$(grep -c "MARKETING_VERSION = $FIX_VER;" "$C/$PB")" 0
eq "pbxproj：旧 build 号 0 处" "$(grep -c "CURRENT_PROJECT_VERSION = $FIX_BUILD;" "$C/$PB")" 0
eq "pbxproj：新版本值恰 2 处" "$(grep -c 'MARKETING_VERSION = 0.0.10;' "$C/$PB")" 2
eq "pbxproj：新 build 号恰 2 处（今天 20250102 + 01）" "$(grep -c 'CURRENT_PROJECT_VERSION = 2025010201;' "$C/$PB")" 2
eq "pbxproj：测试目标 PixyTests 的 MARKETING_VERSION = 1.0 不变（2 处）" "$(grep -c 'MARKETING_VERSION = 1.0;' "$C/$PB")" 2
eq "pbxproj：测试目标 PixyTests 的 CURRENT_PROJECT_VERSION = 1 不变（2 处）" "$(grep -c 'CURRENT_PROJECT_VERSION = 1;' "$C/$PB")" 2
check "pbxproj：plutil -lint 通过" plutil -lint "$C/$PB"
# CHANGELOG
eq "CHANGELOG：numstat 3 增 1 删（换标题 + 空行 + 未签名说明）" "$(git_c diff --numstat -- "$CL")" "3${TAB}1${TAB}$CL"
eq "CHANGELOG：新标题恰 1 个" "$(grep -c '^## \[Fork\] 2025-01-02 — 0.0.10$' "$C/$CL")" 1
eq "CHANGELOG：「## [Fork] 未发布」标题 0 个（不在上方再留空的，沿用 0.0.5 / 0.0.6 的惯例）" "$(grep -c '^## \[Fork\] 未发布' "$C/$CL")" 0
H_LINE=$(grep -n '^## \[Fork\] 2025-01-02 — 0.0.10$' "$C/$CL" | cut -d: -f1)
eq "CHANGELOG：标题下一行是空行" "$(sed -n "$((H_LINE + 1))p" "$C/$CL")" ""
eq "CHANGELOG：再下一行是未签名说明" "$(sed -n "$((H_LINE + 2))p" "$C/$CL")" "仍为**未签名**版本，升级后首次启动需再放行一次（[安装说明](docs/user/installation.md)）。"
eq "CHANGELOG：说明之后仍是空行，再接原来的第一个小节" "$(sed -n "$((H_LINE + 3)),$((H_LINE + 4))p" "$C/$CL" | tr '\n' '|')" "|### 测试夹具：这一段只在测试里出现|"
# checklist
eq "checklist：纯新增 17 行、0 行删除" "$(git_c diff --numstat -- "$CK")" "17${TAB}0${TAB}$CK"
K_LINE=$(grep -n '^## 记录$' "$C/$CK" | cut -d: -f1)
eq "checklist：「## 记录」后紧跟空行" "$(sed -n "$((K_LINE + 1))p" "$C/$CK")" ""
eq "checklist：骨架标题在「## 记录」段顶部" "$(sed -n "$((K_LINE + 2))p" "$C/$CK")" "### 0.0.10（未签名版）"
has_line() { grep -qxF -- "$2" "$1"; }
check "checklist：tag、build 号、上一版号已填" has_line "$C/$CK" '- Release tag：`v0.0.10`；build `2025010201`（当日第一版，build 号规则见 release.md，大于 0.0.9 的 `2025010101`）'
check "checklist：日期已填" has_line "$C/$CK" "- 日期：2025-01-02"
for field in "- macOS / Xcode：" "- 架构：" "- 发布过程：" "- 本版内容：" "- 界面验证范围：" "- 未覆盖："; do
    check "checklist：留空字段「${field}」" has_line "$C/$CK" "$field"
done
eq "checklist：本地产物与 CI 附件各有 ZIP / DMG 位（共 2 个 ZIP、2 个 DMG 空位）" "$(sed -n "$((K_LINE + 2)),$((K_LINE + 18))p" "$C/$CK" | grep -cE '^  - (ZIP|DMG) ``$')" 4
OLD_FIRST_LINE=$(grep -nxF -- "$OLD_FIRST" "$C/$CK" | head -1 | cut -d: -f1)
if [ -n "$OLD_FIRST_LINE" ] && [ "$OLD_FIRST_LINE" -gt $((K_LINE + 17)) ]; then ok "checklist：原来的第一个版本条目（${OLD_FIRST}）被顺延到骨架之后"; else bad "checklist：原来的第一个版本条目应在骨架之后（${OLD_FIRST_LINE}）"; fi
# 工作区与 git 状态
eq "git status：恰好 3 个文件被修改" "$(git_c status --porcelain | tr '\n' '|')" " M CHANGELOG.md| M FlowVision.xcodeproj/project.pbxproj| M docs/dev/release-smoke-checklist.md|"
eq "没有新 commit（HEAD 不变）" "$(git_c rev-parse HEAD)" "$S_HEAD"
eq "没有新 tag" "$(git_c tag | shasum)" "$S_TAGS"
eq "没有任何 ref 变化（分支、远端跟踪、stash 都没动）" "$(git_c for-each-ref | shasum)" "$S_REFS"
eq "没有 stash" "$(git_c stash list)" ""
check "没有构建产物目录（dist / .build）" sh -c '[ ! -e "$1/dist" ] && [ ! -e "$1/.build" ]' _ "$C"
check "没有残留的临时文件" sh -c '[ -z "$(find "$1" -name "*.tmp" -not -path "*/.git/*")" ]' _ "$C"
check "只用了只读的 git 子命令（diff/ls-files/rev-parse/status/symbolic-ref/tag -l）：$(git_subcommands | tr '\n' ' ')" only_readonly_git
eq "没有调用 gh / brew / curl / xcodebuild 等网络或安装类命令" "$(cat "$NETLOG")" ""
# 输出
has "输出：运行了卫生检查并通过" "公开仓库检查通过"
has "输出：运行了本地化检查并通过" "本地化检查通过"
has "输出：版本与 build 号" "Pixy $FIX_VER -> 0.0.10（build $FIX_BUILD -> 2025010201）"
has "输出：构建验收" "scripts/release.sh --unsigned"
has "输出：核对校验和" "shasum -a 256 -c SHA256SUMS.txt"
has "输出：核对架构" "lipo -archs"
has "输出：核对签名" "codesign -dv"
has "输出：spctl 预期 rejected" "rejected 是预期"
has "输出：核对 Info.plist 版本" "Print :CFBundleShortVersionString"
has "输出：只 add 这三个文件" "git add FlowVision.xcodeproj/project.pbxproj CHANGELOG.md docs/dev/release-smoke-checklist.md"
has "输出：提交信息" 'git commit -m "chore(release): 0.0.10"'
has "输出：推送分支" "git push origin $BRANCH"
has "输出：打 tag" 'git tag -a v0.0.10 -m "Pixy 0.0.10"'
has "输出：推送 tag" "git push origin v0.0.10"
has "输出：等 Release 工作流" "gh run watch"
has "输出：runner 容量不足的识别与重跑" "The job was not acquired"
has "输出：重跑命令" "gh run rerun <run-id> --failed -R natinli/Pixy"
has "输出：tag 不重推、不为容量改工作流" "不要为了 runner 容量去改工作流"
has "输出：核对 Release 页" "gh release view v0.0.10 -R natinli/Pixy"
has "输出：同步 tap" "scripts/update-cask.sh 0.0.10"
has "输出：升级前确认没在运行" "pgrep -x Pixy"
has "输出：brew 升级" "brew upgrade --cask pixy"
has "输出：首次启动需用户自己放行" "升级后第一次启动需要你自己放行"
has "输出：本地产物与 CI 附件哈希不同" "本地产物与 CI 附件的哈希不同"
has "输出：只检查了本地 tag、没联网" "没有联网，只检查了本地 tag"
hasnt "输出：不含开发机用户目录路径" "/Use""rs/"
# 同一副本立刻再来一次：工作区已经不干净，必须拒绝
S_AFTER=$(tree_state)
run_rp 0.0.11
rc_is "改完之后紧接着再发一版：工作区不干净，拒绝" 1
has "再发：列出脏文件 CHANGELOG.md" "CHANGELOG.md"
check "再发：被拒后文件未再变" unchanged_since "$S_AFTER"

# ===========================================================================
echo "== 2. --dry-run =="
new_case dry
S0=$(tree_state)
S_HEAD=$(git_c rev-parse HEAD)
run_rp --dry-run v0.0.10
rc_is "dry-run（版本带前导 v）" 0
check "文件与 git 状态前后完全一致" unchanged_since "$S0"
eq "没有 commit" "$(git_c rev-parse HEAD)" "$S_HEAD"
has "输出：说明是 dry-run、没写文件" "dry-run：下面是计划，没有写任何文件"
has "输出：版本变化（前导 v 被剥掉）" "$FIX_VER -> 0.0.10"
has "输出：build 号变化" "$FIX_BUILD -> 2025010201"
has "输出：CHANGELOG 标题变化（旧）" "## [Fork] 未发布"
has "输出：CHANGELOG 标题变化（新）" "## [Fork] 2025-01-02 — 0.0.10"
has "输出：未签名说明" "仍为**未签名**版本"
has "输出：checklist 骨架" "### 0.0.10（未签名版）"
has "输出：骨架里的 tag 与 build" 'Release tag：`v0.0.10`；build `2025010201`'
has "输出：说明检查脚本也会照常运行" "dry-run 也会运行下面两个检查"
has "输出：检查已运行" "公开仓库检查通过"
has "输出：收尾也打印了手动步骤" "git tag -a v0.0.10"
has "输出：dry-run 结束声明" "dry-run 结束：没有写任何文件"
eq "没有调用网络 / 安装类命令" "$(cat "$NETLOG")" ""
check "只用了只读的 git 子命令" only_readonly_git
RUN_CWD=/
run_rp --dry-run 0.0.10
rc_is "从别的工作目录（/）运行也能定位仓库根" 0
check "（从 / 运行）状态仍不变" unchanged_since "$S0"
RUN_CWD=""
run_rp_real_clock --dry-run 0.0.10
rc_is "不设 PIXY_RELEASE_DATE（用真实时钟）" 0
has "真实时钟：build 号 = 今天 + 01" "$FIX_BUILD -> $(date +%Y%m%d)01"
check "（真实时钟）状态仍不变" unchanged_since "$S0"
echo x > "$C/stray.txt"
S1=$(tree_state)
run_rp --dry-run 0.0.10
rc_is "工作区不干净时 dry-run 同样拒绝" 1
check "（拒绝后）状态不变" unchanged_since "$S1"

# ===========================================================================
echo "== 3. 工作区不干净 / --allow-dirty =="
new_case dirty
echo stray > "$C/stray.txt"
echo "改动" >> "$C/docs/index.md"
S0=$(tree_state)
run_rp 0.0.10
rc_is "默认拒绝" 1
has "列出未跟踪文件 stray.txt" "stray.txt"
has "列出已修改文件 docs/index.md" "docs/index.md"
has "提示 --allow-dirty" "--allow-dirty"
has "说明没有改动任何文件" "没有改动任何文件"
check "被拒后文件与状态不变" unchanged_since "$S0"
run_rp --allow-dirty 0.0.10
rc_is "--allow-dirty 放行" 0
has "醒目警告" "警告：--allow-dirty"
has "警告：只能 add 这三个文件" "只能 git add 下面这三个文件"
check "无关的未跟踪文件原样保留" test "$(cat "$C/stray.txt")" = stray
check "无关的已修改文件原样保留" test -n "$(git_c diff -- docs/index.md)"
eq "pbxproj 仍恰好改 4 行" "$(git_c diff --numstat -- "$PB")" "4${TAB}4${TAB}$PB"
eq "git status：3 个目标文件 + 2 个无关文件" "$(git_c status --porcelain | LC_ALL=C sort | tr '\n' '|')" " M CHANGELOG.md| M FlowVision.xcodeproj/project.pbxproj| M docs/dev/release-smoke-checklist.md| M docs/index.md|?? stray.txt|"
hasnt "目标文件本身没有未提交改动时不发多余警告" "这三个文件里已经有未提交的改动"
new_case dirty-target
printf '\n夹具：CHANGELOG 里手写的、尚未提交的一行\n' >> "$C/$CL"
run_rp --allow-dirty 0.0.10
rc_is "--allow-dirty 且目标文件本身已被改过" 0
has "额外警告：这三个文件里已有未提交的改动" "这三个文件里已经有未提交的改动"
has "额外警告指出是 CHANGELOG.md" " M CHANGELOG.md"
check "手写的那一行仍在" grep -q '夹具：CHANGELOG 里手写的、尚未提交的一行' "$C/$CL"
eq "转换后标题仍恰好 1 个" "$(grep -c '^## \[Fork\] 2025-01-02 — 0.0.10$' "$C/$CL")" 1

# ===========================================================================
echo "== 4. 版本号：递增与格式 =="
new_case version
S0=$(tree_state)
for v in 0.0.9 v0.0.9 0.0.8 0.0.0; do
    run_rp --dry-run "$v"
    rc_is "版本 $v 不大于当前 ${FIX_VER}：拒绝" 1
    has "（${v}）说明原因" "没有严格大于当前版本 $FIX_VER"
done
for v in 0.0.10 0.1.0 1.0.0 v1.2.3 0.0.99 12.34.56; do
    run_rp --dry-run "$v"
    rc_is "版本 $v 大于当前：dry-run 通过" 0
done
check "拒绝与 dry-run 之后状态仍不变" unchanged_since "$S0"
new_case version-10
set_version 0.0.10
S0=$(tree_state)
run_rp --dry-run 0.0.9
rc_is "当前 0.0.10，目标 0.0.9：按数值比较拒绝（字符串比较会错放行）" 1
run_rp --dry-run 0.0.10
rc_is "当前 0.0.10，目标 0.0.10：拒绝" 1
run_rp --dry-run 0.0.11
rc_is "当前 0.0.10，目标 0.0.11：通过" 0
run_rp --dry-run 0.1.0
rc_is "当前 0.0.10，目标 0.1.0：通过" 0
check "（以上）状态不变" unchanged_since "$S0"
new_case version-format
S0=$(tree_state)
for v in 1.2 1.2.3.4 abc "" 0.0.x 0.0.07 1.2.3-rc1 v vv0.0.10 " 0.0.10" 0.0.10x 99999999999.0.0; do
    run_rp "$v"
    rc_is "非法版本「${v}」：拒绝" 2
done
has "（最后一个）说明格式要求" "版本号格式不对"
run_rp
rc_is "不给版本号：拒绝" 2
run_rp --force 0.0.10
rc_is "未知选项：拒绝" 2
run_rp -1.0.0
rc_is "负号开头被当成未知选项：拒绝" 2
run_rp 0.0.10 0.0.11
rc_is "给两个版本号：拒绝" 2
run_rp --help
rc_is "--help" 0
has "--help 打印用法" "scripts/release-prepare.sh <版本> [--dry-run] [--allow-dirty]"
check "（以上）状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 5. build 号 =="
new_case build-sameday
RUN_DATE=$D1
run_rp 0.0.10
rc_is "同日第二版" 0
eq "build 号序号 +1（2025010102）" "$(grep -c 'CURRENT_PROJECT_VERSION = 2025010102;' "$C/$PB")" 2
has "checklist 骨架写「当日第二版」" "当日第二版"
check "checklist 里的 build 与大于的上一版" grep -qF 'build `2025010102`（当日第二版，build 号规则见 release.md，大于 0.0.9 的 `2025010101`）' "$C/$CK"
check "CHANGELOG 标题用 DATE 的日期" grep -qx '## \[Fork\] 2025-01-01 — 0.0.10' "$C/$CL"
new_case build-carry
set_build 2025010109
RUN_DATE=$D1
run_rp 0.0.10
rc_is "序号 09 -> 10（避开八进制陷阱）" 0
eq "build 号 2025010110" "$(grep -c 'CURRENT_PROJECT_VERSION = 2025010110;' "$C/$PB")" 2
new_case build-crossday
set_build 2025010105
run_rp 0.0.10
rc_is "跨日" 0
eq "次日回到 01（2025010201）" "$(grep -c 'CURRENT_PROJECT_VERSION = 2025010201;' "$C/$PB")" 2
has "checklist 骨架写「当日第一版」" "当日第一版"
new_case build-future
RUN_DATE=20241231
S0=$(tree_state)
run_rp 0.0.10
rc_is "当前 build 日期晚于今天：拒绝" 1
has "说明原因" "晚于今天"
check "状态不变" unchanged_since "$S0"
new_case build-overflow
set_build 2025010199
RUN_DATE=$D1
S0=$(tree_state)
run_rp 0.0.10
rc_is "当天序号已到 99：拒绝" 1
has "说明原因" "超出两位序号"
check "状态不变" unchanged_since "$S0"
RUN_DATE=$D2
run_rp --dry-run 0.0.10
rc_is "但次日可以继续（99 -> 次日 01）" 0
has "次日 build 号 2025010201" "2025010201"
new_case build-8digit
set_build 20250101
S0=$(tree_state)
run_rp 0.0.10
rc_is "当前 build 号只有 8 位：拒绝" 1
has "说明需要 10 位（8 位日期曾因位数倒退出过问题）" "10 位数字"
check "状态不变" unchanged_since "$S0"
new_case build-date-env
S0=$(tree_state)
for d in 2025-01-02 20251340 20250230 2025010 abc; do
    RUN_DATE=$d
    run_rp 0.0.10
    rc_is "PIXY_RELEASE_DATE=$d 不合法：拒绝" 2
done
check "状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 6. 未发布小节 / tag / checklist =="
new_case no-unreleased
cl_mutate rename
S0=$(tree_state)
run_rp 0.0.10
rc_is "没有「未发布」小节：拒绝" 1
has "说明原因" "找不到「## [Fork] 未发布」小节"
check "状态不变" unchanged_since "$S0"
new_case empty-unreleased
cl_mutate empty
S0=$(tree_state)
run_rp 0.0.10
rc_is "「未发布」下只有空行：拒绝" 1
has "说明没有东西可发" "没有任何内容"
check "状态不变" unchanged_since "$S0"
new_case dup-unreleased
cl_mutate dup
S0=$(tree_state)
run_rp 0.0.10
rc_is "两个「未发布」标题：拒绝" 1
has "说明原因" "无法确定该转换哪一个"
check "状态不变" unchanged_since "$S0"
new_case changelog-has-version
cl_mutate has-version
S0=$(tree_state)
run_rp 0.0.10
rc_is "CHANGELOG 里已有该版本小节：拒绝" 1
has "说明原因" "已经有版本 0.0.10 的小节"
check "状态不变" unchanged_since "$S0"
new_case tag-exists
git_c tag v0.0.10
S0=$(tree_state)
run_rp 0.0.10
rc_is "本地已有 tag v0.0.10：拒绝" 1
has "说明原因" "本地已有 tag v0.0.10"
eq "tag 仍在（没被动过）" "$(git_c tag -l v0.0.10)" v0.0.10
check "状态不变" unchanged_since "$S0"
run_rp 0.0.11
rc_is "同一副本里没有 tag 的 0.0.11 可以正常发版" 0
new_case checklist-no-section
sed -i '' 's/^## 记录$/## 日志/' "$C/$CK"
commit_c "no section"
S0=$(tree_state)
run_rp 0.0.10
rc_is "checklist 缺「## 记录」段：拒绝" 1
has "说明原因" "找不到「## 记录」段"
check "状态不变" unchanged_since "$S0"
new_case checklist-has-version
awk '{ print } /^## 记录$/ { print ""; print "### 0.0.10（未签名版）" }' "$C/$CK" > "$C/ck.tmp" && mv "$C/ck.tmp" "$C/$CK"
commit_c "has version"
S0=$(tree_state)
run_rp 0.0.10
rc_is "checklist 里已有该版本骨架：拒绝" 1
has "说明原因" "里已经有「### 0.0.10（未签名版）」"
check "状态不变" unchanged_since "$S0"
new_case missing-file
git_c rm -q "$CL"
git_c commit -q -m "rm changelog"
S0=$(tree_state)
run_rp 0.0.10
rc_is "CHANGELOG.md 不存在：拒绝" 1
has "说明原因" "找不到 CHANGELOG.md"
check "状态不变" unchanged_since "$S0"
new_case multi
git_c tag v0.0.10
cl_mutate rename
sed -i '' 's/^## 记录$/## 日志/' "$C/$CK"
commit_c "multi"
S0=$(tree_state)
run_rp 0.0.10
rc_is "三个问题同时存在：一次性全部列出" 1
has "汇总个数" "（3 个问题）"
has "含 tag 问题" "本地已有 tag v0.0.10"
has "含 CHANGELOG 问题" "找不到「## [Fork] 未发布」小节"
has "含 checklist 问题" "找不到「## 记录」段"
check "状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 7. pbxproj 结构异常 =="
new_case pb-mismatch
n=$(grep -n "MARKETING_VERSION = $FIX_VER;" "$C/$PB" | sed -n 2p | cut -d: -f1)
sed -i '' "${n}s/$FIX_VER/0.0.8/" "$C/$PB"
commit_c "mismatch"
S0=$(tree_state)
run_rp 0.0.10
rc_is "Debug / Release 的 MARKETING_VERSION 不一致：拒绝" 1
has "说明原因" "MARKETING_VERSION 不一致"
check "状态不变" unchanged_since "$S0"
new_case pb-missing-build
n=$(grep -n "CURRENT_PROJECT_VERSION = $FIX_BUILD;" "$C/$PB" | sed -n 2p | cut -d: -f1)
sed -i '' "${n}d" "$C/$PB"
commit_c "missing build"
S0=$(tree_state)
run_rp 0.0.10
rc_is "某个配置缺 CURRENT_PROJECT_VERSION：拒绝" 1
has "说明原因" "CURRENT_PROJECT_VERSION 应当恰有 1 行"
check "状态不变" unchanged_since "$S0"
new_case pb-broken
printf '}\n' >> "$C/$PB"
commit_c "broken"
S0=$(tree_state)
run_rp 0.0.10
rc_is "pbxproj 本身不是合法 plist：拒绝" 1
has "说明 plutil 校验未通过" "plutil"
check "状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 8. 检查脚本失败 =="
new_case hygiene-fails
printf '#!/bin/sh\necho "桩：卫生检查失败" >&2\nexit 1\n' > "$C/scripts/check-public-hygiene.sh"
commit_c "hygiene stub"
run_rp 0.0.10
rc_is "卫生检查失败" 4
has "明确说改动已写入、没有还原" "检查未通过：改动已写入，没有还原"
has "指出是哪个检查" "未通过：scripts/check-public-hygiene.sh"
has "另一个检查照常运行" "本地化检查通过"
eq "改动被保留（pbxproj 已是新版本）" "$(grep -c 'MARKETING_VERSION = 0.0.10;' "$C/$PB")" 2
has "告诉用户修复后可以单独重跑两个只读检查" "sh scripts/check-public-hygiene.sh"
has "告诉用户不要重跑本脚本、并说明原因" "不要重跑本脚本：版本号已经是 0.0.10"
has "告诉用户怎么放弃这次改动" "git checkout -- FlowVision.xcodeproj/project.pbxproj CHANGELOG.md docs/dev/release-smoke-checklist.md"
has "后续手动步骤照样打印（不然用户没处找）" "接下来请手动执行"
has "最后一行强调：通过之前不要提交、推送、打 tag" "修复并确认检查通过之前，不要提交、推送、打 tag"
S_AFTER=$(tree_state)
run_rp 0.0.10
rc_is "照说明被拒的情形：检查失败后又重跑同一版本" 1
has "（重跑）因版本不再递增被拒" "没有严格大于当前版本 0.0.10"
hasnt "（重跑）不再冒出「内部校验失败」这种噪声" "内部校验失败"
check "（重跑）被拒后文件未再变" unchanged_since "$S_AFTER"
new_case localization-fails
printf 'import sys\nprint("桩：本地化检查失败", file=sys.stderr)\nsys.exit(1)\n' > "$C/scripts/check-localization.py"
commit_c "localization stub"
run_rp 0.0.10
rc_is "本地化检查失败" 4
has "指出是哪个检查" "未通过：scripts/check-localization.py"
has "卫生检查照常运行并通过" "公开仓库检查通过"
eq "改动被保留" "$(grep -c 'CURRENT_PROJECT_VERSION = 2025010201;' "$C/$PB")" 2
new_case dry-check-fails
printf '#!/bin/sh\nexit 1\n' > "$C/scripts/check-public-hygiene.sh"
commit_c "hygiene stub"
S0=$(tree_state)
run_rp --dry-run 0.0.10
rc_is "dry-run 时检查失败：同样非零" 4
has "说明没有写任何文件" "检查未通过（没有写任何文件）"
check "状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 9. 改写中途失败：已改的文件要还原 =="
if [ "$(id -u)" = 0 ]; then
    ok "（跳过）以 root 运行，目录权限制造不出写入失败"
else
    new_case rollback-checklist
    chmod a-w "$C/docs/dev"
    run_rp 0.0.10
    chmod u+w "$C/docs/dev"
    rc_is "第 3 步（checklist）写入失败" 3
    has "提示还原" "正在还原已改的文件"
    has "还原成功" "已还原：三个文件与改动前逐字节一致"
    eq "pbxproj 已还原（git status 干净）" "$(git_c status --porcelain)" ""
    check "没有残留临时文件" sh -c '[ -z "$(find "$1" -name "*.tmp" -not -path "*/.git/*")" ]' _ "$C"
    eq "pbxproj 里没有新版本" "$(grep -c 'MARKETING_VERSION = 0.0.10;' "$C/$PB")" 0
    new_case rollback-changelog
    chmod a-w "$C"
    run_rp 0.0.10
    chmod u+w "$C"
    rc_is "第 2 步（CHANGELOG）写入失败" 3
    has "还原成功" "已还原：三个文件与改动前逐字节一致"
    eq "第 1 步已写的 pbxproj 被还原（git status 干净）" "$(git_c status --porcelain)" ""
    eq "pbxproj 里没有新版本" "$(grep -c 'MARKETING_VERSION = 0.0.10;' "$C/$PB")" 0
    check "没有残留临时文件" sh -c '[ -z "$(find "$1" -name "*.tmp" -not -path "*/.git/*")" ]' _ "$C"
    # 失败修复后可以重来
    run_rp 0.0.10
    rc_is "修好权限后重新运行成功" 0

    # --allow-dirty：回滚必须还原到「脚本改动前」的内容（含用户手改），而不是 git 的 HEAD
    new_case rollback-dirty-checklist
    user_dirty
    H0=$(hash3)
    chmod a-w "$C/docs/dev"
    run_rp --allow-dirty 0.0.10
    chmod u+w "$C/docs/dev"
    rc_is "脏工作区、第 3 步（checklist）写入失败" 3
    has "还原成功" "已还原：三个文件与改动前逐字节一致"
    has "还原后提示可以直接重跑" "修复上面报的原因后，可以直接重跑本脚本"
    eq "三个文件与脚本运行前逐字节一致（用户在 pbxproj / CHANGELOG 里的手改还在）" "$(hash3)" "$H0"
    check "用户手改的 pbxproj 行仍在" grep -q 'GCC_OPTIMIZATION_LEVEL = s;' "$C/$PB"
    check "用户手写的 CHANGELOG 行仍在" grep -q '用户手写的未提交行' "$C/$CL"
    check "无关的未跟踪文件仍在" test -f "$C/stray.txt"
    new_case rollback-dirty-changelog
    user_dirty
    H0=$(hash3)
    chmod a-w "$C"
    run_rp --allow-dirty 0.0.10
    chmod u+w "$C"
    rc_is "脏工作区、第 2 步（CHANGELOG）写入失败" 3
    eq "三个文件与脚本运行前逐字节一致（第 1 步已写的 pbxproj 被还原到手改后的内容，而不是 HEAD）" "$(hash3)" "$H0"
    check "用户手改的 pbxproj 行仍在" grep -q 'GCC_OPTIMIZATION_LEVEL = s;' "$C/$PB"
    check "用户手写的 CHANGELOG 行仍在" grep -q '用户手写的未提交行' "$C/$CL"
fi

# 写入进行中被信号打断（Ctrl-C / kill / 终端关闭）：已改的文件要还原，退出码 = 128 + 信号编号，工作目录被清掉
PY3=$(command -v python3)
mkdir -p "$TMP/slowbin"
cat > "$TMP/slowbin/python3" <<EOF
#!/bin/sh
# 在真正写 checklist（第 3 步）时睡 20 秒，给测试留出「pbxproj 与 CHANGELOG 已改、checklist 还没改」的窗口
case "\$*" in *"checklist edit"*) case "\$*" in *--dry-run*) ;; *) sleep 20 ;; esac ;; esac
exec "$PY3" "\$@"
EOF
chmod +x "$TMP/slowbin/python3"
cat > "$TMP/sigrun.sh" <<'EOF'
#!/bin/bash
# sigrun.sh <仓库副本> <信号名> <脚本日期> <TMPDIR> <PATH 前缀> <窗口> <额外参数>：后台跑被测脚本（独立进程组），
# 等到指定窗口出现——mid：pbxproj / CHANGELOG 已改、checklist 还没改；after：三个文件都改完、正在跑检查——
# 再对整个进程组发信号（模拟终端里的 Ctrl-C），打印窗口是否出现与最终退出码。
dir=$1; sig=$2; day=$3; wd=$4; pre=$5; win=$6; extra=$7
cd "$dir" || exit 1
set -m
env TMPDIR="$wd" PIXY_RELEASE_DATE="$day" PATH="$pre:$PATH" /bin/bash "$dir/scripts/release-prepare.sh" ${extra:+$extra} 0.0.10 > "$dir/../sig.out" 2>&1 &
pid=$!
seen=0
for i in $(seq 1 150); do
    if [ "$win" = after ]; then
        if grep -q '公开仓库检查通过' "$dir/../sig.out" 2>/dev/null; then seen=1; break; fi
    elif grep -q 'MARKETING_VERSION = 0.0.10;' FlowVision.xcodeproj/project.pbxproj 2>/dev/null && ! grep -q '^## \[Fork\] 未发布' CHANGELOG.md 2>/dev/null; then seen=1; break; fi
    sleep 0.2
done
echo "WINDOW=$seen"
kill -"$sig" -- "-$pid"
wait "$pid"
echo "RC=$?"
EOF
chmod +x "$TMP/sigrun.sh"
# 从后台作业（`cmd &`）里启动本测试时，非交互 shell 会让整棵进程树忽略 SIGINT，被测脚本的 trap 对它无效：此时 SIGINT 用例没有意义，跳过
sigint_ignored() { [ "$(/bin/bash -c 'kill -INT $$; sleep 0.3; echo survived' 2>/dev/null)" = survived ]; }
for pair in INT:130 TERM:143 HUP:129; do
    sig=${pair%%:*}; want=${pair##*:}
    if [ "$sig" = INT ] && sigint_ignored; then
        ok "（跳过）当前环境忽略 SIGINT（本测试是从后台作业里启动的），SIGINT 用例无意义"
        continue
    fi
    new_case "signal-$sig"
    user_dirty
    H0=$(hash3)
    OUT=$(/bin/bash "$TMP/sigrun.sh" "$C" "$sig" "$D2" "$WDIR" "$SHIM:$TMP/slowbin" mid --allow-dirty 2>&1)
    has "SIG${sig}：打断时确实处在「前两个文件已改、第三个还没改」的窗口里" "WINDOW=1"
    has "SIG${sig}：退出码 $want" "RC=$want"
    eq "SIG${sig}：三个文件还原到脚本运行前的内容（含用户手改）" "$(hash3)" "$H0"
    eq "SIG${sig}：没有残留的临时文件" "$(find "$C" -name '*.tmp' -not -path '*/.git/*' | wc -l | tr -d ' ')" 0
    case "$(cat "$TMP/sig.out" 2>/dev/null)" in *"已还原：三个文件与改动前逐字节一致"*) ok "SIG${sig}：输出里说明已还原" ;; *) bad "SIG${sig}：输出里没有「已还原」" ;; esac
done

# 三个文件都已改完、正在跑检查时被打断：不还原（改动本来就是要的），但必须说清现状与怎么放弃
new_case signal-after-write
printf 'import time\ntime.sleep(20)\n' > "$C/scripts/check-localization.py"
commit_c "slow localization check"
OUT=$(/bin/bash "$TMP/sigrun.sh" "$C" TERM "$D2" "$WDIR" "$SHIM" after "" 2>&1)
has "写入之后被 SIGTERM 打断：确实停在跑检查的阶段" "WINDOW=1"
has "退出码 143" "RC=143"
eq "三个文件的改动仍在（没有还原）" "$(git_c status --porcelain | wc -l | tr -d ' ')" 3
eq "pbxproj 仍是新版本" "$(grep -c 'MARKETING_VERSION = 0.0.10;' "$C/$PB")" 2
case "$(cat "$TMP/sig.out" 2>/dev/null)" in
    *"脚本在改动写入之后退出（退出码 143）"*"git checkout --"*) ok "输出里说明改动仍在、没有还原，并给出怎么放弃" ;;
    *) bad "输出里没有说明「写入之后退出、没有还原」与放弃办法" ;;
esac
case "$(cat "$TMP/sig.out" 2>/dev/null)" in *"正在还原已改的文件"*) bad "写入之后被打断时不该还原" ;; *) ok "写入之后被打断时没有触发还原" ;; esac

# ===========================================================================
echo "== 10. 不在 git 仓库根目录 =="
mkdir -p "$TMP/nogit/scripts"
cp "$RP" "$RPE" "$TMP/nogit/scripts/"
OUT=$(cd "$TMP/nogit" && TMPDIR="$WDIR" PIXY_RELEASE_DATE=$D2 /bin/bash "$TMP/nogit/scripts/release-prepare.sh" 0.0.10 2>&1); RC=$?
rc_is "不在任何 git 仓库里：拒绝" 1
has "说明原因" "不是一个 git 仓库的根目录"
new_case subdir
mkdir -p "$C/sub/scripts"
cp "$RP" "$RPE" "$C/sub/scripts/"
S0=$(tree_state)
OUT=$(cd "$C/sub" && TMPDIR="$WDIR" PIXY_RELEASE_DATE=$D2 /bin/bash "$C/sub/scripts/release-prepare.sh" 0.0.10 2>&1); RC=$?
rc_is "在仓库的子目录里（不是仓库根）：拒绝" 1
has "说明原因" "不是一个 git 仓库的根目录"
check "状态不变" unchanged_since "$S0"

# ===========================================================================
echo "== 11. 文本改写的边界 =="
refused() {  # refused <模式> <退出码> <原因片段>：改成该形态后运行，应被拒绝且文件完全不变
    new_case "mut-$1"
    mutate "$1"
    S0=$(tree_state)
    run_rp 0.0.10
    rc_is "$1：拒绝" "$2"
    has "$1：说明原因" "$3"
    check "$1：状态不变" unchanged_since "$S0"
}
refused crlf-cl 1 "含 CR 行尾"
refused crlf-ck 1 "含 CR 行尾"
refused crlf-pb 1 "含 CR 行尾"
refused pb-quoted 1 "写成不带引号的单个值"
refused pb-nosemi 1 "plutil -lint 未通过"
refused blockquote 1 "找不到「## [Fork] 未发布」小节"
# 代码块（围栏）里举例用的同名标题不是真标题
refused fence-only 1 "找不到「## [Fork] 未发布」小节"
new_case mut-fence-before
mutate fence-before
run_rp 0.0.10
rc_is "代码块里有一个同名标题、真标题在后面：改真的" 0
eq "围栏里的示例标题原样保留（仍是 1 个「## [Fork] 未发布」，在围栏内）" "$(grep -c '^## \[Fork\] 未发布$' "$C/$CL")" 1
eq "真标题被转换（恰 1 个新标题）" "$(grep -c '^## \[Fork\] 2025-01-02 — 0.0.10$' "$C/$CL")" 1
eq "围栏本身没被动：标题仍夹在两行围栏之间" "$(grep -B1 -A1 '^## \[Fork\] 未发布$' "$C/$CL" | tr '\n' '|')" '```|## [Fork] 未发布|```|'
new_case mut-fence-in-section
mutate fence-hash-in-section
run_rp 0.0.10
rc_is "「未发布」小节里的代码块含「## 」开头的行：不当成下一节标题" 0
eq "代码块原样保留" "$(grep -c '^## 注释$' "$C/$CL")" 1
new_case mut-ck-fence
mutate ck-fence
run_rp 0.0.10
rc_is "checklist 代码块里有同名「## 记录」：改真的" 0
eq "骨架插在真「## 记录」之后" "$(awk '/^## 记录$/ {n++} n == 2 && /^### 0.0.10（未签名版）$/ {print "ok"; exit}' "$C/$CK")" ok
eq "围栏里的「## 记录」仍在" "$(grep -c '^## 记录$' "$C/$CK")" 2
# 文件末尾无换行、「未发布」是最后一节、标题后紧贴正文、「## 记录」后无空行 / 是最后一段
new_case mut-noeol-cl
mutate noeol-cl
run_rp 0.0.10
rc_is "CHANGELOG 末尾没有换行" 0
eq "末尾仍没有换行（不多不少）" "$(tail -c1 "$C/$CL" | od -An -c | tr -d ' ')" "$(git_c show "HEAD:$CL" | tail -c1 | od -An -c | tr -d ' ')"
new_case mut-noeol-ck
mutate noeol-ck
run_rp 0.0.10
rc_is "checklist 末尾没有换行" 0
eq "末尾仍没有换行（不多不少）" "$(tail -c1 "$C/$CK" | od -An -c | tr -d ' ')" "$(git_c show "HEAD:$CK" | tail -c1 | od -An -c | tr -d ' ')"
new_case mut-unreleased-last
mutate unreleased-last-noeol
run_rp 0.0.10
rc_is "「未发布」是文件最后一节且末尾无换行" 0
eq "新标题在第 3 行" "$(sed -n 3p "$C/$CL")" "## [Fork] 2025-01-02 — 0.0.10"
eq "末尾没有换行、正文还在" "$(tail -n 1 "$C/$CL")" "- 只有这一条"
check "末尾确实没有换行" sh -c '[ "$(tail -c1 "$1" | od -An -c | tr -d " ")" != "\\n" ]' _ "$C/$CL"
new_case mut-unreleased-immediate
mutate unreleased-immediate-next
run_rp 0.0.10
rc_is "标题下紧贴正文（没有空行）" 0
H_LINE=$(grep -n '^## \[Fork\] 2025-01-02 — 0.0.10$' "$C/$CL" | cut -d: -f1)
eq "说明与正文之间补了空行" "$(sed -n "$((H_LINE + 3)),$((H_LINE + 4))p" "$C/$CL" | tr '\n' '|')" "|- 紧贴标题的正文|"
new_case mut-ck-nogap
mutate ck-nogap
run_rp 0.0.10
rc_is "「## 记录」后面没有空行" 0
K_LINE=$(grep -n '^## 记录$' "$C/$CK" | cut -d: -f1)
eq "标题后补出空行、再接骨架" "$(sed -n "$((K_LINE + 1)),$((K_LINE + 2))p" "$C/$CK" | tr '\n' '|')" "|### 0.0.10（未签名版）|"
for m in ck-last ck-last-noeol; do
    new_case "mut-$m"
    mutate "$m"
    run_rp 0.0.10
    rc_is "${m}：「## 记录」是最后一段" 0
    check "${m}：骨架在标题之后" sh -c 'grep -A2 "^## 记录$" "$1" | grep -q "^### 0.0.10（未签名版）$"' _ "$C/$CK"
done
# 将来新增与 App 同值的目标：拒绝，而不是只改 App 漏掉它
for m in pb-third pb-third-ver-only pb-third-build-only; do
    refused "$m" 1 "还有别的目标 / 配置使用了与它相同的值"
done
new_case mut-third-lines
mutate pb-third
run_rp 0.0.10
has "pb-third：指出相同值出现在哪些行" "还出现在第"
has "pb-third：说明漏改的风险与下一步" "先确认它们该不该一起升级"
# 版本不递增时不再冒出「内部校验失败」这种噪声
new_case no-noise
run_rp 0.0.9
rc_is "目标版本等于当前版本" 1
hasnt "不再冒出「内部校验失败」" "内部校验失败"
has "只报版本没有递增（1 个问题）" "（1 个问题）"

# ===========================================================================
echo "== 12. locale、Python 版本与仓库路径 =="
# 回归：bash 3.2 在 UTF-8 locale（Terminal 的默认）下读「美元符加变量名」后的全角字符会报 unbound variable 且退出码为 0。
# 同一个完整发版流程在多种 locale 下都要成功；系统自带的 Python 3.9 在非 UTF-8 locale 下默认编码不是 UTF-8，也要覆盖。
locale_run() {  # locale_run <标签> <locale> [python 目录]
    new_case "locale-$1"
    RUN_ENV="LC_ALL=$2"
    RUN_PYBIN=${3:-}
    run_rp 0.0.10
    rc_is "$1：LC_ALL=$2 完整发版" 0
    eq "$1：恰好 3 个文件被修改" "$(git_c status --porcelain | wc -l | tr -d ' ')" 3
    eq "$1：pbxproj 恰好改 4 行" "$(git_c diff --numstat -- "$PB")" "4${TAB}4${TAB}$PB"
    hasnt "$1：没有 unbound variable" "unbound variable"
    hasnt "$1：没有 Python 异常" "Traceback"
    has "$1：两个检查都跑了并通过" "本地化检查通过"
    has "$1：手动步骤清单完整" "brew upgrade --cask pixy"
    RUN_ENV=""
    RUN_PYBIN=""
}
for loc in C en_US.UTF-8 zh_CN.UTF-8 en_US.ISO8859-1 en_US.US-ASCII; do
    if [ "$loc" = C ] || has_locale "$loc"; then
        locale_run "py-default/$loc" "$loc"
    else
        ok "（跳过）本机没有 locale $loc"
    fi
done
if [ -x /usr/bin/python3 ]; then
    mkdir -p "$TMP/pybin"
    ln -sf /usr/bin/python3 "$TMP/pybin/python3"
    PYVER=$("$TMP/pybin/python3" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")
    for loc in C en_US.UTF-8 en_US.ISO8859-1 en_US.US-ASCII; do
        if [ "$loc" = C ] || has_locale "$loc"; then
            locale_run "py-system-$PYVER/$loc" "$loc" "$TMP/pybin"
        else
            ok "（跳过）本机没有 locale $loc"
        fi
    done
else
    ok "（跳过）没有 /usr/bin/python3"
fi
# 仓库路径含空格与中文
C="$TMP/带 空格 仓库"
"$GIT" clone -q "$BASE" "$C"
RUN_DATE=$D2; RUN_CWD=""; RUN_ENV=""; RUN_PYBIN=""
run_rp --dry-run 0.0.10
rc_is "路径含空格与中文：dry-run" 0
run_rp 0.0.10
rc_is "路径含空格与中文：完整发版" 0
eq "路径含空格与中文：恰好 3 个文件被修改" "$(git_c status --porcelain | wc -l | tr -d ' ')" 3
eq "路径含空格与中文：pbxproj 恰好改 4 行" "$(git_c diff --numstat -- "$PB")" "4${TAB}4${TAB}$PB"
# 不是 macOS：明确拒绝（BSD date -j 与 plutil 都没有），而不是在日期解析处报个误导人的「日期不合法」
new_case not-macos
mkdir -p "$TMP/linuxbin"
printf '#!/bin/sh\necho Linux\n' > "$TMP/linuxbin/uname"
chmod +x "$TMP/linuxbin/uname"
S0=$(tree_state)
RUN_PYBIN="$TMP/linuxbin"
run_rp --dry-run 0.0.10
RUN_PYBIN=""
rc_is "uname 不是 Darwin：拒绝" 1
has "说明只支持 macOS" "只支持 macOS"
check "状态不变" unchanged_since "$S0"
# 通过符号链接调用：找不到助手时要干净地拒绝（不能带着错误的仓库根往下走）
new_case symlink
ln -s "$C/scripts/release-prepare.sh" "$TMP/link-release-prepare.sh"
OUT=$(cd "$TMP" && PIXY_RELEASE_DATE=$D2 TMPDIR="$WDIR" /bin/bash "$TMP/link-release-prepare.sh" --dry-run 0.0.10 2>&1); RC=$?
rc_is "通过符号链接调用：拒绝而不是误改别处" 1

# ===========================================================================
echo "== 13. 脚本的工作目录没有残留 =="
eq "所有场景（成功、拒绝、还原、检查失败、被信号打断）结束后，被测脚本的 TMPDIR 里没有残留" "$(ls -A "$WDIR" | wc -l | tr -d ' ')" 0

# ===========================================================================
echo "== 14. 真实仓库未被改动 =="
REAL_AFTER=$(real_fingerprint)
eq "真实仓库的 git status / HEAD / ref / stash / 三个关键文件哈希前后一致（若另有进程在改它，可忽略并重跑）" "$REAL_AFTER" "$REAL_BEFORE"

echo
echo "通过 ${PASS}，失败 ${FAIL}（共 $((PASS + FAIL)) 个断言）"
[ "$FAIL" -eq 0 ]
