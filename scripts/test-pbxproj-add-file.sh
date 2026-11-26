#!/usr/bin/env bash
# scripts/pbxproj-add-file.py 的本机回归测试（不进 CI，需要 macOS 的 plutil）。
#
# 所有改动都发生在 /tmp 下的 pbxproj 副本上；真实工程只读：测试结束时校验它的 sha1 没变。
# 用法：scripts/test-pbxproj-add-file.sh        有失败时退出码为 1。
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
ADD="$SCRIPT_DIR/pbxproj-add-file.py"
REAL="$REPO/FlowVision.xcodeproj/project.pbxproj"
TAB=$'\t'

command -v plutil >/dev/null 2>&1 || { echo "需要 macOS 的 plutil（结构校验用它独立解析 pbxproj）" >&2; exit 1; }
[ -f "$REAL" ] || { echo "找不到 $REAL" >&2; exit 1; }

TMP=$(mktemp -d /tmp/pbxproj-add-file-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
REAL_SHA_BEFORE=$(shasum "$REAL" | cut -d' ' -f1)

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
assert()      { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
assert_fails() { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

# 新建一个独立用例目录：W = 假仓库根，P = 它里面的 pbxproj 副本，$W/original.pbxproj = 改动前的快照
new_case() {
    W="$TMP/$1"
    mkdir -p "$W/FlowVision.xcodeproj" "$W/FlowVision/Sources/Common" "$W/PixyTests"
    P="$W/FlowVision.xcodeproj/project.pbxproj"
    cp "$REAL" "$P"
    cp "$P" "$W/original.pbxproj"
    : > "$W/FlowVision/Sources/Common/__T0Probe.swift"
    : > "$W/PixyTests/__T0ProbeTests.swift"
}

padd() { python3 -I "$ADD" "$@"; }

# 用 plutil（独立于脚本内置解析器）把 pbxproj 转成 JSON，断言：文件引用恰 1 个、恰在期望的组里、
# 构建项恰 1 个、恰在期望目标的 Sources 阶段里（因此也不在另一个目标里）
structure_ok() {  # structure_ok <pbxproj> <文件名> <组 path> <目标名>
    plutil -convert json -o - "$1" | python3 -I -c '
import json, sys
name, group_path, target = sys.argv[1:4]
objs = json.load(sys.stdin)["objects"]
refs = [k for k, v in objs.items() if v.get("isa") == "PBXFileReference" and v.get("path") == name]
assert len(refs) == 1, "文件引用数量 %d" % len(refs)
groups = [k for k, v in objs.items() if v.get("isa") == "PBXGroup" and refs[0] in v.get("children", [])]
assert len(groups) == 1 and objs[groups[0]].get("path") == group_path, "所属组不对 %s" % groups
bfs = [k for k, v in objs.items() if v.get("isa") == "PBXBuildFile" and v.get("fileRef") == refs[0]]
assert len(bfs) == 1, "构建项数量 %d" % len(bfs)
phases = [k for k, v in objs.items() if v.get("isa") == "PBXSourcesBuildPhase" and bfs[0] in v["files"]]
assert len(phases) == 1, "编译阶段数量 %d" % len(phases)
targets = [v["name"] for v in objs.values() if v.get("isa") == "PBXNativeTarget" and phases[0] in v["buildPhases"]]
assert targets == [target], "目标 %s" % targets
' "$2" "$3" "$4"
}

# 改动前后相比：恰好新增 N 行、没有删除或改写任何行
only_added_lines() {  # only_added_lines <快照> <现文件> <N>
    local d added removed
    d=$(diff "$1" "$2")
    added=$(printf '%s\n' "$d" | grep -c '^>')
    removed=$(printf '%s\n' "$d" | grep -c '^<')
    [ "$added" = "$3" ] && [ "$removed" = "0" ]
}

# 一元定义行（\t\t<ID> ...）里没有重复 ID
no_duplicate_ids() {
    local dup
    dup=$(grep -oE "^${TAB}${TAB}[0-9A-F]{24} " "$1" | sort | uniq -d)
    [ -z "$dup" ]
}

# 以猴子补丁的方式让脚本内部某一步失败，验证「后校验失败则不落盘」
# mode: break-brace（新内容括号失衡）| drop-edit（少写一处，括号仍平衡但结构不对）| lint-tmp（临时文件的 plutil 失败）
fault_run() {  # fault_run <mode> <脚本参数...>
    local mode=$1; shift
    python3 -I - "$ADD" "$mode" "$@" <<'PY'
import importlib.util, sys
sys.dont_write_bytecode = True  # 不要在 scripts/ 下留 __pycache__
script, mode, *argv = sys.argv[1:]
spec = importlib.util.spec_from_file_location("pbxadd", script)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
if mode == "break-brace":
    orig = m.apply_edits
    m.apply_edits = lambda text, edits: orig(text, edits).replace("/* End PBXGroup section */", "}\n/* End PBXGroup section */", 1)
elif mode == "drop-edit":
    orig = m.apply_edits
    m.apply_edits = lambda text, edits: orig(text, edits[:-1])
elif mode == "lint-tmp":
    orig_lint = m.plutil_lint
    def lint(path):
        if str(path).endswith(".tmp"):
            raise m.RegisterError("plutil -lint 未通过：模拟的失败")
        return orig_lint(path)
    m.plutil_lint = lint
else:
    sys.exit("unknown mode " + mode)
sys.exit(m.main(argv))
PY
}

echo "== 语法 =="
assert "bash -n 本脚本" bash -n "$0"
assert "注册脚本能通过 Python 语法解析" python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$ADD"

echo "== 1. app 目标登记 =="
new_case app
out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "退出码 0" || { bad "退出码 0（实际 $rc）：$out"; }
assert "四处各恰好新增 1 行（共 4 行、0 行被改动）" only_added_lines "$W/original.pbxproj" "$P" 4
assert "plutil -lint 通过" plutil -lint "$P"
assert "文件引用/构建项/组/编译阶段各 1 处，且在 Common 组、FlowVision 目标" structure_ok "$P" __T0Probe.swift Common FlowVision
assert "没有重复 ID" no_duplicate_ids "$P"
assert "没有残留临时文件" test "$(ls -A "$W/FlowVision.xcodeproj")" = "project.pbxproj"
assert "文件权限与原文件一致" test "$(stat -f %Lp "$P")" = "$(stat -f %Lp "$REAL")"
APP_AFTER="$W/after-first.pbxproj"
cp "$P" "$APP_AFTER"

echo "== 2. 幂等 =="
out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "重复登记退出码 0" || bad "重复登记退出码 0（实际 $rc）"
case "$out" in *未改动*) ok "提示「已登记…未改动」" ;; *) bad "提示「已登记…未改动」：$out" ;; esac
assert "重复登记后文件逐字节不变" cmp "$P" "$APP_AFTER"
# 工程里本来就有的文件：同样什么都不改
: > "$W/FlowVision/Sources/Common/Log.swift"
out=$(padd FlowVision/Sources/Common/Log.swift --target app --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "已有文件 Log.swift 退出码 0" || bad "已有文件 Log.swift 退出码 0（实际 $rc）"
assert "已有文件登记后仍逐字节不变" cmp "$P" "$APP_AFTER"
# 只登记了一半（缺构建项与编译阶段条目）：补齐缺的部分，且 ID 与一次登记到位时相同
new_case partial
BUILD_ID=$(grep -oE '[0-9A-F]{24} /\* __T0Probe.swift in Sources \*/' "$APP_AFTER" | head -1 | cut -d' ' -f1)
grep -v "$BUILD_ID" "$APP_AFTER" > "$P"
out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "半登记状态补齐退出码 0" || bad "半登记状态补齐退出码 0（实际 $rc）：$out"
assert "补齐后与一次登记到位的结果逐字节相同" cmp "$P" "$APP_AFTER"

echo "== 3. tests 目标登记 =="
new_case tests
out=$(padd PixyTests/__T0ProbeTests.swift --target tests --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "退出码 0" || bad "退出码 0（实际 $rc）：$out"
assert "四处各恰好新增 1 行" only_added_lines "$W/original.pbxproj" "$P" 4
assert "plutil -lint 通过" plutil -lint "$P"
assert "在 PixyTests 组、PixyTests 目标的编译阶段（因而不在 app 的）" structure_ok "$P" __T0ProbeTests.swift PixyTests PixyTests
assert "没有重复 ID" no_duplicate_ids "$P"

echo "== 4. 非法输入：非零退出且 pbxproj 不变 =="
new_case reject
rejects() {  # rejects <描述> <脚本参数...>
    local d=$1; shift
    local o r
    o=$(padd "$@" --project "$P" 2>&1); r=$?
    if [ $r -ne 0 ] && cmp -s "$P" "$W/original.pbxproj"; then ok "$d（退出码 $r）"; else bad "$d：退出码 $r，输出：$o"; fi
}
rejects "文件不存在" FlowVision/Sources/Common/Nope.swift --target app
: > "$W/FlowVision/Sources/Common/notes.txt"
rejects "扩展名不是 .swift" FlowVision/Sources/Common/notes.txt --target app
rejects "--target 非法" FlowVision/Sources/Common/__T0Probe.swift --target foo
rejects "缺少 --target" FlowVision/Sources/Common/__T0Probe.swift
rejects "app 的文件却指定 --target tests" FlowVision/Sources/Common/__T0Probe.swift --target tests
rejects "tests 的文件却指定 --target app" PixyTests/__T0ProbeTests.swift --target app
mkdir -p "$W/FlowVision/Sources/Nowhere" && : > "$W/FlowVision/Sources/Nowhere/X.swift"
rejects "目录在组树里没有对应的组" FlowVision/Sources/Nowhere/X.swift --target app
rejects "路径逃出仓库根" ../outside.swift --target app
assert "错误输出走 stderr、不污染 stdout" test -z "$(padd FlowVision/Sources/Common/Nope.swift --target app --project "$P" 2>/dev/null)"

echo "== 5. 校验失败不落盘 =="
new_case corrupt
# 5a 写入前校验：原文件括号已被破坏（删掉 PixyTests 组闭合的 `};` 行）
awk '/^\t\t\tpath = PixyTests;$/ {print; getline; print; getline; next} {print}' "$P" > "$W/broken.pbxproj"
cp "$W/broken.pbxproj" "$P"
out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
if [ $rc -ne 0 ] && cmp -s "$P" "$W/broken.pbxproj"; then ok "5a 原文件括号被破坏：拒绝处理且不改动（退出码 $rc）"; else bad "5a 原文件括号被破坏：退出码 $rc，输出：$out"; fi
case "$out" in *写入前校验*) ok "5a 报错说明是「写入前校验」" ;; *) bad "5a 报错说明是「写入前校验」：$out" ;; esac

for mode in break-brace drop-edit lint-tmp; do
    case "$mode" in
        break-brace) want="括号不平衡" ;;      # 内存里的平衡校验拦下
        drop-edit)   want="被意外改动" ;;      # 平衡但结构与预期不符，新旧对象对比拦下
        lint-tmp)    want="写入后校验未通过" ;; # 临时文件的 plutil 校验拦下
    esac
    new_case "fault-$mode"
    out=$(fault_run "$mode" FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
    if [ $rc -ne 0 ] && cmp -s "$P" "$W/original.pbxproj"; then ok "5b 后校验失败（$mode）：非零退出（$rc）且不落盘"; else bad "5b 后校验失败（$mode）：退出码 $rc，输出：$out"; fi
    case "$out" in *"$want"*) ok "5b ($mode) 由预期的校验拦下（含「$want」）" ;; *) bad "5b ($mode) 应含「$want」：$out" ;; esac
    assert "5b ($mode) 没有残留临时文件" test "$(ls -A "$W/FlowVision.xcodeproj")" = "project.pbxproj"
done

echo "== 6. --dry-run =="
new_case dry
out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && ok "退出码 0" || bad "退出码 0（实际 $rc）：$out"
assert "pbxproj 逐字节不变" cmp "$P" "$W/original.pbxproj"
assert "没有残留临时文件" test "$(ls -A "$W/FlowVision.xcodeproj")" = "project.pbxproj"
for label in PBXBuildFile PBXFileReference "PBXGroup" PBXSourcesBuildPhase __T0Probe.swift dry-run; do
    case "$out" in *"$label"*) ok "输出含「$label」" ;; *) bad "输出含「$label」" ;; esac
done

echo "== 7. 确定性与 --root =="
new_case det-a
new_case det-b
padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$TMP/det-a/FlowVision.xcodeproj/project.pbxproj" >/dev/null 2>&1
padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$TMP/det-b/FlowVision.xcodeproj/project.pbxproj" >/dev/null 2>&1
assert "同一文件在两份相同工程上得到逐字节相同的结果（ID 确定）" cmp "$TMP/det-a/FlowVision.xcodeproj/project.pbxproj" "$TMP/det-b/FlowVision.xcodeproj/project.pbxproj"
new_case root-a
mkdir -p "$TMP/elsewhere/FlowVision/Sources/Common" && : > "$TMP/elsewhere/FlowVision/Sources/Common/OnlyThere.swift"
rm -f "$W/FlowVision/Sources/Common/__T0Probe.swift"
out=$(padd FlowVision/Sources/Common/OnlyThere.swift --target app --project "$P" 2>&1); rc=$?
[ $rc -ne 0 ] && ok "默认根目录下不存在该文件：拒绝（退出码 $rc）" || bad "默认根目录下不存在该文件：应拒绝"
out=$(padd FlowVision/Sources/Common/OnlyThere.swift --target app --project "$P" --root "$TMP/elsewhere" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "--root 指向另一个目录后可登记" || bad "--root 指向另一个目录后可登记：$out"
assert "显式 --root 登记的结果结构正确" structure_ok "$P" OnlyThere.swift Common FlowVision
# 文件名含 + 与 - 时 path 必须加引号（与 Xcode 一致），且仍通过 plutil
new_case quoting
: > "$W/FlowVision/Sources/Common/Foo+Bar-Baz.swift"
padd FlowVision/Sources/Common/Foo+Bar-Baz.swift --target app --project "$P" >/dev/null 2>&1
assert "特殊文件名：path 加引号、plutil 通过、结构正确" grep -q 'path = "Foo+Bar-Baz.swift";' "$P"
assert "特殊文件名：结构正确" structure_ok "$P" "Foo+Bar-Baz.swift" Common FlowVision

echo "== 8. 在真实工程的副本上识别现有文件 =="
# 工程里已有的每一个 .swift 都应被识别为「已登记」（验证沿组树逐级匹配对真实结构成立）；
# 用副本 + --root 指向真实仓库根，只读
new_case real
checked=0
unreg=""
while IFS= read -r f; do
    rel=${f#"$REPO"/}
    case "$rel" in PixyTests/*) tgt=tests ;; *) tgt=app ;; esac
    o=$(padd "$rel" --target "$tgt" --project "$P" --root "$REPO" --dry-run 2>&1)
    case "$o" in *未改动*) ;; *) unreg="$unreg $rel" ;; esac
    checked=$((checked + 1))
done < <(find "$REPO/FlowVision" "$REPO/PixyTests" -name '*.swift' -not -path '*/.build/*' | sort)
if [ -z "$unreg" ] && [ "$checked" -gt 0 ]; then ok "真实工程 $checked 个 .swift 全部识别为已登记"; else bad "有 .swift 未被识别为已登记：$unreg"; fi
# 默认 --project（真实工程）只读试用：dry-run 一个已登记的应用文件与测试文件
out=$(padd FlowVision/Sources/Common/Log.swift --target app --dry-run 2>&1); rc=$?
{ [ $rc -eq 0 ] && case "$out" in *未改动*) true ;; *) false ;; esac; } && ok "默认 --project 解析到真实工程（dry-run，应用文件）" || bad "默认 --project（应用文件）：$out"
out=$(padd PixyTests/SortKeyTests.swift --target tests --dry-run 2>&1); rc=$?
{ [ $rc -eq 0 ] && case "$out" in *未改动*) true ;; *) false ;; esac; } && ok "默认 --project 解析到真实工程（dry-run，测试文件）" || bad "默认 --project（测试文件）：$out"

echo "== 9. 边界与对抗（同名文件、路径写法、符号链接、大小写、只读） =="
# 9a 同名文件分属两个组：各登记各的，第二个不能被当成「已登记」
samename_ok() {  # samename_ok <pbxproj>
    plutil -convert json -o - "$1" | python3 -I -c '
import json, sys
objs = json.load(sys.stdin)["objects"]
refs = [k for k, v in objs.items() if v.get("isa") == "PBXFileReference" and v.get("path") == "Dup.swift"]
assert len(refs) == 2, "文件引用数量 %d" % len(refs)
got = set()
for r in refs:
    g = [v["path"] for v in objs.values() if v.get("isa") == "PBXGroup" and r in v.get("children", [])]
    assert len(g) == 1, g
    bf = [k for k, v in objs.items() if v.get("isa") == "PBXBuildFile" and v.get("fileRef") == r]
    assert len(bf) == 1, bf
    got.add(g[0])
assert got == {"Common", "Views"}, got
'
}
new_case samename
mkdir -p "$W/FlowVision/Sources/Views"
: > "$W/FlowVision/Sources/Common/Dup.swift"
: > "$W/FlowVision/Sources/Views/Dup.swift"
padd FlowVision/Sources/Common/Dup.swift --target app --project "$P" >/dev/null 2>&1
out=$(padd FlowVision/Sources/Views/Dup.swift --target app --project "$P" 2>&1); rc=$?
{ [ $rc -eq 0 ] && case "$out" in *未改动*) false ;; *) true ;; esac; } && ok "另一个组里的同名文件不被误判为已登记" || bad "另一个组里的同名文件不被误判为已登记：$out"
assert "同名文件分属 Common / Views 两个组，引用与构建项各 1 个" samename_ok "$P"
assert "同名文件：没有重复 ID" no_duplicate_ids "$P"
# 9b 路径写法：./ 前缀、冗余的 // 与 ..、/tmp 与 /private/tmp 两种绝对路径写法最终是同一个文件
new_case paths
: > "$W/FlowVision/Sources/Common/P1.swift"
: > "$W/FlowVision/Sources/Common/P2.swift"
padd ./FlowVision/Sources/Common/P1.swift --target app --project "$P" >/dev/null 2>&1
out=$(padd "FlowVision//Sources/../Sources/Common/P1.swift" --target app --project "$P" 2>&1)
case "$out" in *未改动*) ok "./ 前缀与冗余 // .. 写法被规范化为同一个文件（幂等）" ;; *) bad "./ 前缀与冗余 // .. 写法应规范化：$out" ;; esac
padd "$W/FlowVision/Sources/Common/P2.swift" --target app --project "$P" >/dev/null 2>&1
if [ -d /private/tmp ]; then
    out=$(padd "/private$W/FlowVision/Sources/Common/P2.swift" --target app --project "$P" 2>&1)
    case "$out" in *未改动*) ok "绝对路径经 /tmp 与 /private/tmp 两种写法等价" ;; *) bad "绝对路径 /tmp 与 /private/tmp 应等价：$out" ;; esac
fi
assert "路径写法用例：文件引用/构建项各 1 处" structure_ok "$P" P1.swift Common FlowVision
# 9c 文件本身是符号链接：按它在工程里的位置登记，绝对与相对写法一致
new_case symfile
ln -s /etc/hosts "$W/FlowVision/Sources/Common/LinkTo.swift"
out=$(padd "$W/FlowVision/Sources/Common/LinkTo.swift" --target app --project "$P" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "绝对路径指向符号链接文件：按链接位置登记" || bad "绝对路径指向符号链接文件应可登记：$out"
assert "符号链接文件：结构正确" structure_ok "$P" LinkTo.swift Common FlowVision
# 9d 文件名大小写必须与磁盘一致（仅当临时目录所在卷大小写不敏感时才能构造这个场景）
new_case casing
: > "$W/FlowVision/Sources/Common/Real.swift"
if [ -e "$W/FlowVision/Sources/Common/real.swift" ]; then
    out=$(padd FlowVision/Sources/Common/real.swift --target app --project "$P" 2>&1); rc=$?
    if [ $rc -ne 0 ] && cmp -s "$P" "$W/original.pbxproj"; then ok "大小写与磁盘不一致：拒绝且不改动（退出码 $rc）"; else bad "大小写与磁盘不一致应拒绝：退出码 $rc，输出：$out"; fi
    case "$out" in *大小写*Real.swift*) ok "报错给出磁盘上的真实文件名" ;; *) bad "报错应给出磁盘上的真实文件名：$out" ;; esac
else
    ok "（跳过）临时目录所在卷大小写敏感，无法构造大小写不一致的场景"
fi
padd FlowVision/Sources/Common/Real.swift --target app --project "$P" >/dev/null 2>&1
assert "按磁盘真实大小写登记：结构正确" structure_ok "$P" Real.swift Common FlowVision
# 9e pbxproj 所在目录只读：给出中文错误而不是 Python traceback，工程不变，没有残留
if [ "$(id -u)" != 0 ]; then
    new_case readonly
    chmod a-w "$W/FlowVision.xcodeproj"
    out=$(padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" 2>&1); rc=$?
    chmod u+w "$W/FlowVision.xcodeproj"
    if [ $rc -ne 0 ] && cmp -s "$P" "$W/original.pbxproj"; then ok "目录只读：非零退出（$rc）且工程不变"; else bad "目录只读：退出码 $rc，输出：$out"; fi
    case "$out" in *Traceback*) bad "目录只读：不应输出 Python traceback：$out" ;; *错误：*) ok "目录只读：中文错误信息、无 traceback" ;; *) bad "目录只读：应有中文错误信息：$out" ;; esac
    assert "目录只读：没有残留临时文件" test "$(ls -A "$W/FlowVision.xcodeproj")" = "project.pbxproj"
fi
# 9f pbxproj 本身是符号链接：链接保持不变，改动落在链接目标上
new_case symproj
mkdir -p "$W/real"
mv "$P" "$W/real/project.pbxproj"
ln -s ../real/project.pbxproj "$P"
padd FlowVision/Sources/Common/__T0Probe.swift --target app --project "$P" >/dev/null 2>&1
assert "pbxproj 符号链接仍是符号链接" test -L "$P"
assert "改动落在符号链接的目标上" structure_ok "$W/real/project.pbxproj" __T0Probe.swift Common FlowVision
assert "目标旁没有残留临时文件" test "$(ls -A "$W/real")" = "project.pbxproj"

echo "== 10. 真实工程未被改动 =="
REAL_SHA_AFTER=$(shasum "$REAL" | cut -d' ' -f1)
[ "$REAL_SHA_BEFORE" = "$REAL_SHA_AFTER" ] && ok "真实 project.pbxproj 的 sha1 前后一致" || bad "真实 project.pbxproj 在测试期间发生了变化（若另有进程在改它，可忽略并重跑）"

echo
echo "通过 $PASS，失败 $FAIL"
[ "$FAIL" -eq 0 ]
