#!/usr/bin/env bash
# scripts/bench/run.sh 的本机回归测试（不进 CI；需要 macOS 的 defaults / ps / pgrep 和 python3、perl）。
#
# 不启动真的 PixyDbg：用一个假应用（python3 脚本）代替——它读 PIXY_LOG_FILE，按固定节奏写计时行、占一块内存、
# 收到 TERM 就退出；通过 FAKE_MODE 环境变量切换行为（正常 / 永不写完成行 / 提前退出 / 忽略 TERM / 缺缩略图行 / 乱序）。
# 偏好写在一次性的域 com.natinli.PixyBenchTest.<pid> 里（PIXY_BENCH_DOMAIN），结束时删除；
# 开始和结束各读一次真实的 com.natinli.PixyDbg 的 lastFolder / hasNormalExit，必须一致（证明没碰它）。
# 测试目录放在本测试自己的临时目录里（PIXY_BENCH_TMPDIR），结束时整体清理。
#
# 用法：scripts/test-bench-run.sh     有失败时退出码为 1。
#   在两种环境下各跑一遍：env -u LANG -u LC_ALL scripts/test-bench-run.sh；LANG=zh_CN.UTF-8 scripts/test-bench-run.sh
#   （部分场景自己也会在两种 locale 下重跑 run.sh）。
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RUN="${SCRIPT_DIR}/bench/run.sh"
GEN="${SCRIPT_DIR}/bench/gen-images.py"
REAL_DOMAIN=com.natinli.PixyDbg

for tool in defaults ps pgrep python3 perl; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "需要 ${tool}" >&2; exit 1; }
done
[ -f "${RUN}" ] && [ -f "${GEN}" ] || { echo "找不到被测脚本" >&2; exit 1; }

TMP=$(mktemp -d /tmp/bench-run-test.XXXXXX)
ROOT="${TMP}/root"          # 被测脚本的 PIXY_BENCH_TMPDIR：每个场景结束后应当是空的
mkdir -p "${ROOT}"
DOM="com.natinli.PixyBenchTest.$$"
FAKE="${TMP}/fake-pixy"
REC="${TMP}/fake-record.txt"
SLEEPER_PID=""
BG_PID=""

cleanup() {
    [ -n "${SLEEPER_PID}" ] && kill "${SLEEPER_PID}" 2>/dev/null
    [ -n "${BG_PID}" ] && kill -KILL "${BG_PID}" 2>/dev/null
    pkill -f "${FAKE}" 2>/dev/null
    defaults delete "${DOM}" >/dev/null 2>&1
    rm -rf "${TMP}"
}
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望「$3」，实际「$2」）"; fi; }
has()   { case "${OUT}" in *"$2"*) ok "$1" ;; *) bad "$1（输出里没有「$2」）"; printf '%s\n' "${OUT}" | sed 's/^/      | /' | tail -15 ;; esac; }
hasnt() { case "${OUT}" in *"$2"*) bad "$1（输出里不该有「$2」）" ;; *) ok "$1" ;; esac; }
rc_is() { if [ "${RC}" -eq "$2" ]; then ok "$1（退出码 ${RC}）"; else bad "$1：退出码应为 $2，实际 ${RC}"; printf '%s\n' "${OUT}" | sed 's/^/      | /' | tail -15; fi; }

# ---------------------------------------------------------------------------
# 假应用
# ---------------------------------------------------------------------------
cat > "${FAKE}" <<'PYEOF'
#!/usr/bin/env python3
import mmap, os, signal, subprocess, sys, time

mode = os.environ.get("FAKE_MODE", "ok")
log = os.environ.get("PIXY_LOG_FILE")
record = os.environ.get("FAKE_RECORD")
domain = os.environ.get("FAKE_DOMAIN", "")

if mode == "ignore-term":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
else:
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))


def w(line):
    if log:
        with open(log, "a") as f:
            f.write("2026-01-01 00:00:00,000 [INFO] [fake()] " + line + "\n")


def defaults(key):
    r = subprocess.run(["defaults", "read", domain, key], capture_output=True, text=True)
    return r.stdout.strip()


if record:
    folder = defaults("lastFolder")
    path = folder[len("file://"):] if folder.startswith("file://") else folder
    count = len(os.listdir(path)) if os.path.isdir(path) else -1
    with open(record, "a") as f:
        f.write("argv=%s\n" % " ".join(sys.argv[1:]))
        f.write("log=%s\n" % log)
        f.write("lastFolder=%s\n" % folder)
        f.write("hasNormalExit=%s\n" % defaults("hasNormalExit"))
        f.write("files=%d\n" % count)
        f.write("cwd=%s\n" % os.getcwd())

if log:
    open(log, "w").close()
w("Logger initialized")

if mode == "exit-early":
    time.sleep(0.4)
    sys.exit(3)

time.sleep(0.3)
# 占住约 60 MB（逐页写入才算常驻），之后 munmap 立刻还给系统，让「峰值」大于「稳态」
SIZE = 60 * 1024 * 1024
blob = mmap.mmap(-1, SIZE)
for off in range(0, SIZE, 4096):
    blob[off] = 1
if mode == "hang":
    while True:
        time.sleep(0.1)

if mode == "reorder":
    w("Time taken to fully load image thumbnails: 0.600 seconds")
    w("Time taken to fully load size information: 0.250 seconds")
    w("Time taken to complete loading first image: 0.200 seconds")
    w("Time taken to complete file list: 0.050 seconds")
else:
    w("Time taken to complete file list: 0.050 seconds")
    w("Time taken to complete loading first image: 0.200 seconds")
    w("Time taken to fully load size information: 0.250 seconds")
    time.sleep(0.3)
    if mode != "no-thumb":
        w("Time taken to fully load image thumbnails: 0.600 seconds")
time.sleep(0.2)
blob.close()
while True:
    time.sleep(0.1)
PYEOF
chmod +x "${FAKE}"

# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------
# bench <参数...>：用假应用跑 run.sh，输出（含 stderr）进 OUT，退出码进 RC。
# 每次调用可在前面加 FAKE_MODE=…、T_TIMEOUT=…、T_SETTLE=…、T_LOCALE=zh 等变量。
bench() {
    local ea=()
    if [ "${T_LOCALE:-}" = "zh" ]; then ea=(LANG=zh_CN.UTF-8); else ea=(-u LANG -u LC_ALL); fi
    OUT=$(env ${ea[@]+"${ea[@]}"} PATH="${T_PATH:-${PATH}}" \
        PIXY_BENCH_APP="${BENCH_APP:-${FAKE}}" PIXY_BENCH_DOMAIN="${DOM}" PIXY_BENCH_TMPDIR="${BENCH_TMPDIR:-${ROOT}}" \
        PIXY_BENCH_TIMEOUT="${T_TIMEOUT:-4}" PIXY_BENCH_SETTLE="${T_SETTLE:-1}" PIXY_BENCH_INTERVAL="${T_INTERVAL:-0.1}" \
        PIXY_BENCH_SEED_COUNT=4 FAKE_RECORD="${REC}" FAKE_DOMAIN="${DOM}" FAKE_MODE="${FAKE_MODE:-ok}" \
        bash "${RUN}" "$@" 2>&1)
    RC=$?
}

dom_get()  { defaults read "${DOM}" "$1" 2>/dev/null || printf 'ABSENT'; }
dom_type() { defaults read-type "${DOM}" "$1" 2>/dev/null || printf 'ABSENT'; }
dom_reset() { defaults delete "${DOM}" >/dev/null 2>&1; rm -f "${REC}"; }
root_entries() { ls -A "${ROOT}" | wc -l | tr -d ' '; }
fake_procs()   { pgrep -f "${FAKE}" 2>/dev/null | wc -l | tr -d ' '; }
real_prefs()   { printf '%s|%s' "$(defaults read "${REAL_DOMAIN}" lastFolder 2>/dev/null || printf ABSENT)" "$(defaults read "${REAL_DOMAIN}" hasNormalExit 2>/dev/null || printf ABSENT)"; }
# 表格里第 N 档的第 K 列（1 起；列 1 是档位）
cell() { printf '%s\n' "${OUT}" | awk -F'|' -v t="$1" -v k="$2" '$2 + 0 == t + 0 && $2 ~ /[0-9]/ { gsub(/^ +| +$/, "", $(k + 1)); print $(k + 1); exit }'; }

caf_count()    { pgrep -f 'caffeinate -dis -w' 2>/dev/null | wc -l | tr -d ' '; }

REAL_BEFORE=$(real_prefs)
CAF_BEFORE=$(caf_count)

# ---------------------------------------------------------------------------
echo "== 语法 =="
bash -n "${RUN}" 2>/dev/null && ok "bash -n run.sh" || bad "bash -n run.sh"
bash -n "$0" 2>/dev/null && ok "bash -n 本测试" || bad "bash -n 本测试"
python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "${GEN}" && ok "gen-images.py 语法" || bad "gen-images.py 语法"
[ -x "${RUN}" ] && ok "run.sh 有可执行位" || bad "run.sh 没有可执行位"
[ -x "${GEN}" ] && ok "gen-images.py 有可执行位" || bad "gen-images.py 没有可执行位"

# ---------------------------------------------------------------------------
echo "== 解析与统计函数（source run.sh 后直接调用） =="
LOGF="${TMP}/parse.log"
FUNC_OUT="${TMP}/func.out"
(
    # shellcheck disable=SC1090
    source "${RUN}"
    set +e
    fails=0
    t() { # t <描述> <期望> <实际>
        if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; else printf '  FAIL %s（期望「%s」，实际「%s」）\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
    }
    L="Time taken to fully load size information"
    printf '%s\n' \
        "2026-01-01 00:00:00,000 [INFO] [f()] Time taken to complete file list: 3.020536334 seconds" \
        "2026-01-01 00:00:00,000 [INFO] [f()] Time taken to fully load size information: 4.173676667 seconds" > "${LOGF}"
    t "正常行：文件列表" "3.020536334" "$(parse_metric "${LOGF}" "Time taken to complete file list")"
    t "正常行：尺寸信息" "4.173676667" "$(parse_metric "${LOGF}" "${L}")"
    t "缺行：缩略图" "" "$(parse_metric "${LOGF}" "Time taken to fully load image thumbnails")"
    t "文件不存在" "" "$(parse_metric "${TMP}/nope.log" "${L}")"
    parse_metric "${TMP}/nope.log" "${L}" >/dev/null 2>&1; t "文件不存在时退出码 0" "0" "$?"
    : > "${LOGF}"
    t "空文件" "" "$(parse_metric "${LOGF}" "${L}")"

    printf '%s\n' \
        "x Time taken to fully load size information: abc seconds" \
        "x Time taken to fully load size information: 1.5 sec" \
        "x Time taken to fully load size information: -1.5 seconds" \
        "x Time taken to fully load size information 2.5 seconds" \
        "x Time taken to fully load size information: seconds" > "${LOGF}"
    t "格式不符的行全部忽略" "" "$(parse_metric "${LOGF}" "${L}")"

    printf '%s\n' \
        "x Time taken to fully load size information: abc seconds" \
        "x Time taken to fully load size information: 2.5 seconds" \
        "x Time taken to fully load size information: 9.9 seconds" > "${LOGF}"
    t "第一条格式正确的出现胜出（前面有坏行、后面有重复行）" "2.5" "$(parse_metric "${LOGF}" "${L}")"

    printf '%s\n' "Logger initialized2026-01-01 00:00:00,000 [INFO] [f()] Time taken to fully load size information: 0.5 seconds" > "${LOGF}"
    t "行首粘着别的内容（日志第一行曾缺换行）" "0.5" "$(parse_metric "${LOGF}" "${L}")"

    printf '%s\n' "x Time taken to complete file listing: 1.0 seconds" > "${LOGF}"
    t "文案只是更长文案的前缀时不误配" "" "$(parse_metric "${LOGF}" "Time taken to complete file list")"

    printf '%s\n' "x Time taken to fully load size information: 9.5e-05 seconds" > "${LOGF}"
    t "科学计数法" "9.5e-05" "$(parse_metric "${LOGF}" "${L}")"

    printf '%s\n' \
        "x Time taken to fully load image thumbnails: 0.6 seconds" \
        "x Time taken to fully load size information: 0.25 seconds" \
        "x Time taken to complete file list: 0.05 seconds" > "${LOGF}"
    t "乱序：不依赖行的先后" "0.25" "$(parse_metric "${LOGF}" "${L}")"
    t "乱序：文件列表" "0.05" "$(parse_metric "${LOGF}" "Time taken to complete file list")"

    printf '%s\n' "x Time taken to fully load size information: 12 seconds" > "${LOGF}"
    t "整数秒" "12" "$(parse_metric "${LOGF}" "${L}")"

    t "max_of 乱序" "30" "$(max_of 5 30 7)"
    t "max_of 单个" "5" "$(max_of 5)"
    t "max_of 空" "" "$(max_of)"
    t "median_of 奇数个" "7" "$(median_of 30 5 7)"
    t "median_of 偶数个（中间两个取整数平均）" "6" "$(median_of 5 7 100 1)"
    t "median_of 单个" "5" "$(median_of 5)"
    t "median_of 空" "" "$(median_of)"
    t "median_of 数值比较而不是字符串比较" "100" "$(median_of 9 100 1000)"

    case "$(screen_state)" in 亮屏、未锁定|亮屏、已锁定|熄屏、未锁定|熄屏、已锁定|未知、*) t "screen_state 输出格式「显示器、会话」" ok ok ;; *) t "screen_state 输出格式「显示器、会话」" ok "$(screen_state)" ;; esac
    t "screen_state：PIXY_BENCH_DISPLAY=asleep → 熄屏" "熄屏" "$(PIXY_BENCH_DISPLAY=asleep screen_state | sed 's/、.*//')"
    t "screen_state：PIXY_BENCH_DISPLAY=awake → 亮屏" "亮屏" "$(PIXY_BENCH_DISPLAY=awake screen_state | sed 's/、.*//')"
    t "fmt_secs 空" "-" "$(fmt_secs "")"
    t "fmt_secs 保留 3 位" "3.200" "$(fmt_secs 3.2)"
    t "fmt_secs 科学计数法" "0.000" "$(fmt_secs 9.5e-05)"
    t "fmt_mb 空" "-" "$(fmt_mb "")"
    t "fmt_mb 换算" "1.5" "$(fmt_mb 1536)"

    FP_OK=$(printf '%s\n' "====" "sleep [1]: 64-bit    Footprint: 753856 B (16384 bytes per page)" "====" "" "Auxiliary data:" "    phys_footprint: 770240 B" "    phys_footprint_peak: 803008 B")
    t "parse_footprint 正常输出（字节 → KB）" "752 784" "$(printf '%s\n' "${FP_OK}" | parse_footprint)"
    t "parse_footprint 缺峰值行" "" "$(printf '%s\n' "    phys_footprint: 770240 B" | parse_footprint)"
    t "parse_footprint 缺当前值行" "" "$(printf '%s\n' "    phys_footprint_peak: 803008 B" | parse_footprint)"
    t "parse_footprint 单位不是 B 时放弃" "" "$(printf '%s\n' "    phys_footprint: 752 KB" "    phys_footprint_peak: 784 KB" | parse_footprint)"
    t "parse_footprint 数字不合法时放弃" "" "$(printf '%s\n' "    phys_footprint: abc B" "    phys_footprint_peak: 803008 B" | parse_footprint)"
    t "parse_footprint 空输入" "" "$(printf '' | parse_footprint)"
    t "parse_footprint 两行顺序颠倒也行" "752 784" "$(printf '%s\n' "    phys_footprint_peak: 803008 B" "    phys_footprint: 770240 B" | parse_footprint)"
    t "read_footprint 进程不存在时什么都不输出" "" "$(read_footprint 999999)"

    is_pos_int 300; t "is_pos_int 300" "0" "$?"
    is_pos_int 0; t "is_pos_int 0 拒绝" "1" "$?"
    is_pos_int -5; t "is_pos_int -5 拒绝" "1" "$?"
    is_pos_int 3x; t "is_pos_int 3x 拒绝" "1" "$?"
    is_pos_int ""; t "is_pos_int 空串拒绝" "1" "$?"
    is_uint 0; t "is_uint 0" "0" "$?"
    is_decimal 0.5; t "is_decimal 0.5" "0" "$?"
    is_decimal .5; t "is_decimal .5 拒绝" "1" "$?"
    is_decimal 1e3; t "is_decimal 1e3 拒绝" "1" "$?"

    # 偏好快照 / 还原：absent、string、boolean、不支持的类型
    defaults delete "${DOM}" >/dev/null 2>&1
    t "快照：键不存在" "absent" "$(pref_snapshot "${DOM}" lastFolder)"
    defaults write "${DOM}" lastFolder -string "file:///tmp/a b/"
    t "快照：字符串（含空格）" "string:file:///tmp/a b/" "$(pref_snapshot "${DOM}" lastFolder)"
    defaults write "${DOM}" hasNormalExit -bool false
    t "快照：布尔 false" "boolean:0" "$(pref_snapshot "${DOM}" hasNormalExit)"
    defaults write "${DOM}" hasNormalExit -bool true
    t "快照：布尔 true" "boolean:1" "$(pref_snapshot "${DOM}" hasNormalExit)"
    defaults write "${DOM}" other -int 3
    case "$(pref_snapshot "${DOM}" other)" in unsupported:*) t "快照：整数视为不支持" ok ok ;; *) t "快照：整数视为不支持" ok "$(pref_snapshot "${DOM}" other)" ;; esac
    pref_restore "${DOM}" lastFolder absent
    t "还原 absent：键被删掉" "absent" "$(pref_snapshot "${DOM}" lastFolder)"
    pref_restore "${DOM}" lastFolder "string:file:///tmp/a b/"
    t "还原 string" "string:file:///tmp/a b/" "$(pref_snapshot "${DOM}" lastFolder)"
    pref_restore "${DOM}" hasNormalExit boolean:0
    t "还原 boolean false" "boolean:0" "$(pref_snapshot "${DOM}" hasNormalExit)"
    t "还原 boolean 后类型仍是布尔" "Type is boolean" "$(defaults read-type "${DOM}" hasNormalExit)"
    defaults delete "${DOM}" >/dev/null 2>&1
    exit "${fails}"
) > "${FUNC_OUT}" 2>&1
SUB_FAILS=$?
cat "${FUNC_OUT}"
PASS=$((PASS + $(grep -c '^  PASS' "${FUNC_OUT}")))
FAIL=$((FAIL + $(grep -c '^  FAIL' "${FUNC_OUT}")))
[ "${SUB_FAILS}" -eq 0 ] || [ "$(grep -c '^  FAIL' "${FUNC_OUT}")" -gt 0 ] || bad "函数级用例的子 shell 异常退出（${SUB_FAILS}）"

# ---------------------------------------------------------------------------
echo "== gen-images.py =="
GD="${TMP}/gen"
python3 -I "${GEN}" seed "${GD}/seed" 5
eq "seed 生成 5 张" "$(ls "${GD}/seed" | wc -l | tr -d ' ')" "5"
eq "文件名从 img_00001.png 起" "$(ls "${GD}/seed" | head -1)" "img_00001.png"
mkdir "${GD}/fan"
python3 -I "${GEN}" fan "${GD}/seed" "${GD}/fan" 12
eq "fan 生成 12 个" "$(ls "${GD}/fan" | wc -l | tr -d ' ')" "12"
eq "fan 文件名排序稳定（末尾）" "$(ls "${GD}/fan" | tail -1)" "img_00012.png"
eq "fan 是硬链接（第 6 个与第 1 个同 inode）" "$(stat -f %i "${GD}/fan/img_00006.png")" "$(stat -f %i "${GD}/seed/img_00001.png")"
python3 -I "${GEN}" seed "${GD}/seed2" 5
eq "生成是确定性的（两次内容一致）" "$(cat "${GD}"/seed/*.png | shasum | cut -c1-40)" "$(cat "${GD}"/seed2/*.png | shasum | cut -c1-40)"
file "${GD}/seed/img_00001.png" | grep -q "PNG image data" && ok "是合法 PNG" || bad "不是合法 PNG"
python3 -I "${GEN}" fan "${GD}/nope" "${GD}/fan" 3 >/dev/null 2>&1; rc=$?
[ "${rc}" -ne 0 ] && ok "种子目录不存在时失败" || bad "种子目录不存在时应失败"

# ---------------------------------------------------------------------------
echo "== 参数与前置条件校验：全部拒绝（退出码 2），且什么都没创建 =="
dom_reset
for badarg in abc 0 -5 3x 100001 --bogus; do
    bench "${badarg}"
    rc_is "拒绝参数 ${badarg}" "${RC}" 2
done
for pair in "T_TIMEOUT=0" "T_TIMEOUT=x" "T_SETTLE=-1" "T_SETTLE=x" "T_INTERVAL=abc" "T_INTERVAL=-1"; do
    env "${pair}" true
    ( export "${pair?}"; bench 5; echo "${RC}" > "${TMP}/rc.txt"; printf '%s' "${OUT}" > "${TMP}/out.txt" )
    RC=$(cat "${TMP}/rc.txt"); OUT=$(cat "${TMP}/out.txt")
    rc_is "拒绝环境变量 ${pair}" "${RC}" 2
done
BENCH_TMPDIR="relative/dir" bench 5;       rc_is "拒绝相对路径的 PIXY_BENCH_TMPDIR" "${RC}" 2
BENCH_TMPDIR="${TMP}/with space" bench 5;  rc_is "拒绝带空格的 PIXY_BENCH_TMPDIR" "${RC}" 2
BENCH_TMPDIR="${TMP}/missing" bench 5;     rc_is "拒绝不存在的 PIXY_BENCH_TMPDIR" "${RC}" 2
BENCH_APP="/Applications/Pixy.app/Contents/MacOS/Pixy" bench 5
rc_is "拒绝 /Applications 下的应用" "${RC}" 2
has "  并说明原因" "不测 /Applications"
BENCH_APP="${TMP}/no-such-app" bench 5
rc_is "找不到应用" "${RC}" 2
has "  报错里带构建命令" "xcodebuild"
has "  报错里提到 PIXY_BENCH_APP" "PIXY_BENCH_APP"
eq "被拒绝的运行没有改偏好（lastFolder 仍不存在）" "$(dom_get lastFolder)" "ABSENT"
eq "被拒绝的运行没有留下目录" "$(root_entries)" "0"
eq "被拒绝的运行没有启动假应用" "$([ -e "${REC}" ] && echo yes || echo no)" "no"

# ---------------------------------------------------------------------------
echo "== --dry-run：不生成目录、不启动进程、不改偏好 =="
for loc in unset zh; do
    dom_reset
    T_LOCALE=$([ "${loc}" = zh ] && echo zh || echo unset) bench --dry-run 7 11
    rc_is "dry-run（locale=${loc}）" "${RC}" 0
    has "  打印档位" "档位：7 11"
    has "  说明会阻止熄屏 / 睡眠" "caffeinate -dis"
    has "  打印被测应用" "${FAKE}"
    has "  说明只打印计划" "只打印计划"
    eq "  没生成目录" "$(root_entries)" "0"
    eq "  没启动假应用" "$([ -e "${REC}" ] && echo yes || echo no)" "no"
    eq "  没改偏好" "$(dom_get lastFolder)" "ABSENT"
done
BENCH_APP="${TMP}/no-such-app" bench --dry-run
rc_is "dry-run 在应用不存在时仍退出 0" "${RC}" 0
has "  但标出不存在" "不存在或不可执行"
bench --dry-run
has "  缺省档位 300 6000 20000" "档位：300 6000 20000"

# ---------------------------------------------------------------------------
echo "== 正常运行（假应用）：两个 locale 各一遍，偏好原来有值 =="
for loc in unset zh; do
    dom_reset
    defaults write "${DOM}" lastFolder -string "file:///orig/folder/"
    defaults write "${DOM}" hasNormalExit -bool false
    T_LOCALE=$([ "${loc}" = zh ] && echo zh || echo unset) bench 5 12
    rc_is "正常运行（locale=${loc}）" "${RC}" 0
    has "  表头" "| 档位 | 文件列表 | 首图 | 尺寸信息读完 | 缩略图读完 | 峰值 RSS (MB) | 稳态 RSS (MB) | 峰值 footprint (MB) | 稳态 footprint (MB) | 结果 |"
    has "  输出机器型号" "- 机器：$(sysctl -n hw.model)"
    has "  输出系统版本" "- 系统：macOS $(sw_vers -productVersion)"
    has "  输出构建配置" "- 构建配置：Debug"
    has "  输出屏幕状态" "- 屏幕："
    has "  输出日期" "- 日期：$(date '+%Y-%m-%d')"
    eq "  5 档：文件列表" "$(cell 5 2)" "0.050"
    eq "  5 档：首图" "$(cell 5 3)" "0.200"
    eq "  5 档：尺寸信息读完" "$(cell 5 4)" "0.250"
    eq "  5 档：缩略图读完" "$(cell 5 5)" "0.600"
    eq "  5 档：结果" "$(cell 5 10)" "OK"
    eq "  12 档：结果" "$(cell 12 10)" "OK"
    if command -v footprint >/dev/null 2>&1; then
        case "$(cell 12 8)|$(cell 12 9)" in
            [0-9]*.[0-9]\|[0-9]*.[0-9]) ok "  12 档：footprint 峰值 $(cell 12 8) MB / 稳态 $(cell 12 9) MB（数字）" ;;
            *) bad "  12 档：footprint 应为数字，实际「$(cell 12 8)」「$(cell 12 9)」" ;;
        esac
    fi
    peak=$(cell 12 6); steady=$(cell 12 7)
    if [ -n "${peak}" ] && [ -n "${steady}" ] && awk -v p="${peak}" -v s="${steady}" 'BEGIN { exit !(p >= 60 && s < p) }'; then
        ok "  12 档：峰值 ${peak} MB ≥ 60 且大于稳态 ${steady} MB（假应用占 60 MB 后释放）"
    else
        bad "  12 档：峰值 ${peak:-空} / 稳态 ${steady:-空} 不符合预期"
    fi
    eq "  按档位顺序输出（5 在 12 前）" "$(printf '%s\n' "${OUT}" | grep -E '^\| (5|12) \|' | awk -F'|' '{ printf "%d ", $2 }')" "5 12 "
    # 假应用被启动了两次；记录里能看到它启动那一刻的偏好
    eq "  假应用被启动 2 次" "$(grep -c '^argv=' "${REC}")" "2"
    eq "  启动参数带 -AppleLanguages (en)" "$(head -1 "${REC}")" "argv=-AppleLanguages (en)"
    case "$(grep '^log=' "${REC}" | head -1)" in "log=${ROOT}/pixy-bench."*"/app-5.log") ok "  PIXY_LOG_FILE 指向临时目录里的日志" ;; *) bad "  PIXY_LOG_FILE 不对：$(grep '^log=' "${REC}" | head -1)" ;; esac
    case "$(grep '^lastFolder=' "${REC}" | head -1)" in "lastFolder=file://${ROOT}/pixy-bench."*"/dir-5/") ok "  启动时 lastFolder 指向测试目录" ;; *) bad "  lastFolder 不对：$(grep '^lastFolder=' "${REC}" | head -1)" ;; esac
    eq "  启动时 hasNormalExit 为 true" "$(grep '^hasNormalExit=' "${REC}" | head -1)" "hasNormalExit=1"
    eq "  启动时目录里恰有 5 个文件" "$(grep '^files=' "${REC}" | head -1)" "files=5"
    case "$(grep '^cwd=' "${REC}" | head -1)" in "cwd=$(cd "${ROOT}" && pwd -P)/pixy-bench."*) ok "  应用的工作目录在临时目录里（不会在仓库里留下 default.profraw）" ;; *) bad "  应用的工作目录不对：$(grep '^cwd=' "${REC}" | head -1)" ;; esac
    eq "  第二次启动时目录里恰有 12 个文件" "$(grep '^files=' "${REC}" | tail -1)" "files=12"
    eq "  结束后 lastFolder 还原" "$(dom_get lastFolder)" "file:///orig/folder/"
    eq "  结束后 hasNormalExit 还原（false）" "$(dom_get hasNormalExit)" "0"
    eq "  结束后 hasNormalExit 仍是布尔类型" "$(dom_type hasNormalExit)" "Type is boolean"
    eq "  结束后清理了临时目录" "$(root_entries)" "0"
    eq "  结束后没有残留的假应用进程" "$(fake_procs)" "0"
done

echo "== 正常运行：偏好原来没有这两个键 → 结束后删掉 =="
dom_reset
bench 5
rc_is "正常运行（偏好原本为空）" "${RC}" 0
eq "  lastFolder 被删回不存在" "$(dom_get lastFolder)" "ABSENT"
eq "  hasNormalExit 被删回不存在" "$(dom_get hasNormalExit)" "ABSENT"
eq "  清理了临时目录" "$(root_entries)" "0"

echo "== 屏幕状态（ioreg 垫片模拟锁屏，PIXY_BENCH_DISPLAY 模拟熄屏） =="
mkdir -p "${TMP}/shim-locked" "${TMP}/shim-unlocked"
cat > "${TMP}/shim-locked/ioreg" <<'SHIM'
#!/bin/sh
echo '      "CGSSessionScreenIsLocked"=Yes,"kCGSSessionOnConsoleKey"=Yes'
SHIM
cat > "${TMP}/shim-unlocked/ioreg" <<'SHIM'
#!/bin/sh
echo '      "CGSSessionLoginDoneKey"=Yes'
SHIM
chmod +x "${TMP}/shim-locked/ioreg" "${TMP}/shim-unlocked/ioreg"
for combo in "awake locked 亮屏、已锁定 warn" "asleep unlocked 熄屏、未锁定 warn" "asleep locked 熄屏、已锁定 warn" "awake unlocked 亮屏、未锁定 nowarn"; do
    set -- ${combo}
    dom_reset
    PIXY_BENCH_DISPLAY="$1" T_PATH="${TMP}/shim-$2:${PATH}" bench 5
    rc_is "屏幕状态 $3 时仍正常运行" "${RC}" 0
    has "  报告里写明「$3」" "- 屏幕：$3"
    if [ "$4" = warn ]; then
        has "  开头警告" "警告：当前屏幕状态是「$3」"
    else
        hasnt "  亮屏且未锁定时没有警告" "警告：当前屏幕状态"
    fi
done
unset PIXY_BENCH_DISPLAY

echo "== 缩略图行缺失 / 乱序 =="
dom_reset
FAKE_MODE=no-thumb bench 5
rc_is "缺缩略图行仍算 OK（尺寸信息读完才是必需）" "${RC}" 0
eq "  缩略图列显示 -" "$(cell 5 5)" "-"
eq "  尺寸信息仍有值" "$(cell 5 4)" "0.250"
dom_reset
FAKE_MODE=reorder bench 5
rc_is "日志行乱序" "${RC}" 0
eq "  乱序：尺寸信息" "$(cell 5 4)" "0.250"
eq "  乱序：文件列表" "$(cell 5 2)" "0.050"
eq "  乱序：缩略图" "$(cell 5 5)" "0.600"

# ---------------------------------------------------------------------------
echo "== 超时路径：假应用永不写完成行 =="
dom_reset
defaults write "${DOM}" lastFolder -string "file:///orig/folder/"
defaults write "${DOM}" hasNormalExit -bool true
START=$(date +%s)
FAKE_MODE=hang T_TIMEOUT=2 bench 5
ELAPSED=$(( $(date +%s) - START ))
rc_is "超时" "${RC}" 1
has "  表格里标 FAIL" "FAIL(2 秒内没读完尺寸信息)"
has "  打印日志最后几行供排查" "Logger initialized"
if [ "${ELAPSED}" -ge 2 ] && [ "${ELAPSED}" -le 12 ]; then ok "  耗时 ${ELAPSED} 秒（≈ 超时 2 秒 + 启动与清理）"; else bad "  耗时 ${ELAPSED} 秒不合理"; fi
eq "  清理了目录" "$(root_entries)" "0"
eq "  没有残留进程" "$(fake_procs)" "0"
eq "  偏好还原（lastFolder）" "$(dom_get lastFolder)" "file:///orig/folder/"
eq "  偏好还原（hasNormalExit）" "$(dom_get hasNormalExit)" "1"
eq "  多档时超时不影响继续下一档：第二档照常记录" "$(FAKE_MODE=hang T_TIMEOUT=1 bench 5 6; printf '%s\n' "${OUT}" | grep -c '^| .*FAIL(1 秒内没读完尺寸信息)')" "2"

echo "== 应用提前退出 =="
dom_reset
FAKE_MODE=exit-early bench 5
rc_is "应用提前退出" "${RC}" 1
has "  表格里标 FAIL" "FAIL(应用提前退出)"
eq "  清理了目录" "$(root_entries)" "0"

echo "== 忽略 TERM 的应用：升级到 KILL =="
dom_reset
FAKE_MODE=ignore-term bench 5
rc_is "忽略 TERM 的应用" "${RC}" 0
eq "  没有残留进程" "$(fake_procs)" "0"
eq "  清理了目录" "$(root_entries)" "0"

# ---------------------------------------------------------------------------
# 运行中被 TERM / INT：必须清理进程、目录并还原偏好。
# 后台 `&` 启动的非交互 bash 会忽略 SIGINT 且无法再 trap，所以用 perl 先把 INT/TERM 恢复成默认再 exec。
run_signal_case() {
    local sig=$1 expect=$2 n=0
    dom_reset
    defaults write "${DOM}" lastFolder -string "file:///orig/folder/"
    defaults write "${DOM}" hasNormalExit -bool false
    (
        exec env -u LANG -u LC_ALL PIXY_BENCH_APP="${FAKE}" PIXY_BENCH_DOMAIN="${DOM}" PIXY_BENCH_TMPDIR="${ROOT}" \
            PIXY_BENCH_TIMEOUT=60 PIXY_BENCH_SETTLE=1 PIXY_BENCH_INTERVAL=0.1 PIXY_BENCH_SEED_COUNT=4 \
            FAKE_RECORD="${REC}" FAKE_DOMAIN="${DOM}" FAKE_MODE=hang \
            perl -e '$SIG{INT} = "DEFAULT"; $SIG{TERM} = "DEFAULT"; exec @ARGV' bash "${RUN}" 5
    ) > "${TMP}/bg.out" 2>&1 &
    BG_PID=$!
    while [ ! -s "${REC}" ] && [ "${n}" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    sleep 0.5
    [ -s "${REC}" ] && ok "  ${sig}：假应用已启动" || bad "  ${sig}：假应用没有启动"
    kill "-${sig}" "${BG_PID}" 2>/dev/null
    wait "${BG_PID}" 2>/dev/null
    RC=$?
    BG_PID=""
    OUT=$(cat "${TMP}/bg.out")
    rc_is "运行中收到 ${sig}" "${RC}" "${expect}"
    eq "  ${sig}：没有残留进程" "$(fake_procs)" "0"
    eq "  ${sig}：清理了目录" "$(root_entries)" "0"
    eq "  ${sig}：偏好还原（lastFolder）" "$(dom_get lastFolder)" "file:///orig/folder/"
    eq "  ${sig}：偏好还原（hasNormalExit）" "$(dom_get hasNormalExit)" "0"
}
echo "== 运行中收到 TERM =="
run_signal_case TERM 143
echo "== 运行中收到 INT（Ctrl-C） =="
run_signal_case INT 130

# ---------------------------------------------------------------------------
echo "== 同名进程已在运行：拒绝，且不杀它 =="
dom_reset
defaults write "${DOM}" lastFolder -string "file:///orig/folder/"
FAKE_MODE=hang FAKE_RECORD=/dev/null python3 "${FAKE}" >/dev/null 2>&1 &
SLEEPER_PID=$!
sleep 0.5
bench 5
rc_is "已有实例在运行" "${RC}" 2
has "  说明原因" "已在运行"
if kill -0 "${SLEEPER_PID}" 2>/dev/null; then ok "  已有的实例没被杀"; else bad "  已有的实例被杀了"; fi
eq "  没改偏好" "$(dom_get lastFolder)" "file:///orig/folder/"
eq "  没生成目录" "$(root_entries)" "0"
eq "  没启动新实例" "$([ -e "${REC}" ] && echo yes || echo no)" "no"
kill "${SLEEPER_PID}" 2>/dev/null; wait "${SLEEPER_PID}" 2>/dev/null; SLEEPER_PID=""
bench --dry-run
rc_is "已有实例时 dry-run 不受影响" "${RC}" 0

# ---------------------------------------------------------------------------
echo "== 没碰真实的偏好域 =="
eq "真实 ${REAL_DOMAIN} 的 lastFolder / hasNormalExit 前后一致" "$(real_prefs)" "${REAL_BEFORE}"
eq "测试目录没有残留（ROOT 为空）" "$(root_entries)" "0"
eq "没有残留的假应用进程" "$(fake_procs)" "0"
sleep 1
eq "没有残留的 caffeinate（-w 随脚本退出，含 TERM / INT 的情形）" "$(caf_count)" "${CAF_BEFORE}"
if ls /tmp 2>/dev/null | grep -q '^pixy-bench\.'; then
    LEFT=$(ls /tmp | grep -c '^pixy-bench\.')
    echo "  提示：/tmp 下有 ${LEFT} 个 pixy-bench.* 目录——可能是别的真实运行留下的，本测试只在自己的 ROOT 里跑"
fi

echo
echo "通过 ${PASS}、失败 ${FAIL}。"
[ "${FAIL}" -eq 0 ]
