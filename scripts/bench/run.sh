#!/usr/bin/env bash
# Pixy 本机性能基线：对 300 / 6000 / 20000 张图片的目录，测「加载耗时」和「内存」。
#
# 做法：在 /tmp 生成测试目录 → 用 Debug 构建（PixyDbg）打开它 → 每 0.5 秒采样进程 RSS，
# 同时轮询应用写出的日志（环境变量 PIXY_LOG_FILE，仅 Debug 构建支持）→ 解析「Time taken to …」计时行
# → 观察窗口末尾用 footprint 读一次物理占用（含被系统压缩的页）→ 结束进程、清理目录、还原偏好 → 输出 Markdown 表。
#
# 只作本机对比，不进 CI（macOS runner 配额紧张、虚拟机里的数字不稳定）。测量定义、噪声与对比方法见
# docs/dev/performance-baseline.md。
#
# 用法：scripts/bench/run.sh [--dry-run] [档位 ...]
#   档位       目录里的图片数（正整数）；缺省为 300 6000 20000
#   --dry-run  只打印将做什么，不生成目录、不启动进程、不改偏好
#
# 环境变量（都可选）：
#   PIXY_BENCH_APP       被测可执行文件，缺省 .build/DerivedData-root/Build/Products/Debug/PixyDbg.app/Contents/MacOS/PixyDbg
#   PIXY_BENCH_DOMAIN    写 lastFolder / hasNormalExit 的偏好域，缺省 com.natinli.PixyDbg
#   PIXY_BENCH_TIMEOUT   每档等「尺寸信息读完」的上限（秒），缺省 120，超时记 FAIL
#   PIXY_BENCH_SETTLE    「尺寸信息读完」之后继续观察的秒数，缺省 40（用整数秒计时，实际是 40～41 秒，不会短于它）；
#                        稳态 RSS 取窗口末尾 5 个样本的中位数
#   PIXY_BENCH_INTERVAL  采样间隔（秒），缺省 0.5
#   PIXY_BENCH_TMPDIR    测试目录所在位置，缺省 /tmp
#   PIXY_BENCH_VERBOSE   设为 1 时把每个 RSS 样本打到 stderr（看内存曲线用）
#   PIXY_BENCH_SEED_COUNT  种子图数量，缺省 300（只给测试脚本缩短运行时间用，基线请保持缺省）
#
# 退出码：0 全部通过；1 有档位 FAIL；2 参数或前置条件不满足（没改任何东西）。
#
# 兼容 macOS 自带 bash 3.2：不用关联数组、mapfile、${var,,}；变量一律写成 ${var}，因为变量名后紧跟
# 全角中文字符时，在 zh_CN.UTF-8 下 bash 会把那个字符当成变量名的一部分（set -u 下直接报未定义）。
set -euo pipefail

BENCH_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${BENCH_DIR}/../.." && pwd -P)

DEFAULT_TIERS="300 6000 20000"
SEED_COUNT="${PIXY_BENCH_SEED_COUNT:-300}"

# 日志里的计时行：「<文案>: <秒数> seconds」，秒数都是从本次目录切换开始累计的
LABEL_LIST="Time taken to complete file list"
LABEL_FIRST="Time taken to complete loading first image"
LABEL_SIZE="Time taken to fully load size information"
LABEL_THUMB="Time taken to fully load image thumbnails"

# 运行期状态（cleanup 用）
WORK=""
APP_PID=""
CAFFEINATE_PID=""
PREFS_SAVED=0
SNAP_LAST=""
SNAP_EXIT=""
ROWS=""
ANY_FAIL=0

say() { printf '%s\n' "$*" >&2; }
die() { printf '错误：%s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 纯函数（run.sh 被 source 时可单独调用，scripts/test-bench-run.sh 靠这个测解析逻辑）
# ---------------------------------------------------------------------------

# parse_metric <日志文件> <文案>：输出该文案第一次「格式正确」出现时的秒数；没有、格式不符或文件读不了则什么都不输出（退出码仍为 0）。
# 用 index() 而不是正则找文案，所以文案里的特殊字符不用转义；行首粘着别的内容（日志第一行曾缺换行）也能命中。
parse_metric() {
    local file=$1 label=$2
    [ -r "${file}" ] || return 0
    LC_ALL=C awk -v label="${label}" '
        {
            i = index($0, label ": ")
            if (i == 0) next
            rest = substr($0, i + length(label) + 2)
            if (match(rest, /^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?[ ]+seconds/)) {
                split(rest, parts, " ")
                print parts[1]
                exit
            }
        }' "${file}"
}

# parse_footprint：从标准输入读 `footprint --noCategories -f bytes -p <pid>` 的输出，
# 输出「当前 KB 峰值 KB」（整数，空格分隔）；两行有一行缺失、单位不是 B 或不是数字时什么都不输出
parse_footprint() {
    LC_ALL=C awk '
        $1 == "phys_footprint:"      && $3 == "B" && $2 ~ /^[0-9]+$/ { cur = $2 }
        $1 == "phys_footprint_peak:" && $3 == "B" && $2 ~ /^[0-9]+$/ { peak = $2 }
        END { if (cur != "" && peak != "") printf "%d %d\n", cur / 1024, peak / 1024 }'
}

# read_footprint <pid>：读该进程的 phys_footprint（含被压缩的页，等同活动监视器「内存」列）当前值与进程生命周期内的峰值，
# 输出「当前 KB 峰值 KB」；footprint 不存在、进程已退出或读取失败时什么都不输出
# footprint 放在后台跑并最多等 10 秒（macOS 没有 timeout 命令），防止它卡住整个测量
read_footprint() {
    command -v footprint >/dev/null 2>&1 || return 0
    local out fp_pid n=0
    out=$(mktemp "${WORK:-${TMPDIR:-/tmp}}/footprint.XXXXXX") || return 0
    footprint --noCategories -f bytes -p "$1" >"${out}" 2>/dev/null &
    fp_pid=$!
    while kill -0 "${fp_pid}" 2>/dev/null && [ "${n}" -lt 100 ]; do
        sleep 0.1
        n=$((n + 1))
    done
    if kill -0 "${fp_pid}" 2>/dev/null; then kill -KILL "${fp_pid}" 2>/dev/null || true; fi
    wait "${fp_pid}" 2>/dev/null || true
    parse_footprint < "${out}" || true
    rm -f "${out}"
    return 0
}

# fmt_secs <秒数|空>：保留 3 位小数；空值显示为 -
fmt_secs() {
    if [ -z "${1:-}" ]; then printf '%s' "-"; return 0; fi
    LC_ALL=C awk -v v="$1" 'BEGIN { printf "%.3f", v + 0 }'
}

# fmt_mb <KB|空>：换算成 MB，保留 1 位小数；空值显示为 -
fmt_mb() {
    if [ -z "${1:-}" ]; then printf '%s' "-"; return 0; fi
    LC_ALL=C awk -v v="$1" 'BEGIN { printf "%.1f", v / 1024 }'
}

# max_of <数字 ...>：最大值；没有参数时什么都不输出
max_of() {
    [ "$#" -gt 0 ] || return 0
    printf '%s\n' "$@" | LC_ALL=C sort -n | tail -n 1
}

# median_of <数字 ...>：中位数（偶数个取中间两个的整数平均）；没有参数时什么都不输出
median_of() {
    [ "$#" -gt 0 ] || return 0
    printf '%s\n' "$@" | LC_ALL=C sort -n | LC_ALL=C awk '
        { a[NR] = $1 }
        END {
            if (NR == 0) exit
            if (NR % 2 == 1) print a[(NR + 1) / 2]
            else printf "%d\n", (a[NR / 2] + a[NR / 2 + 1]) / 2
        }'
}

# screen_state：输出「亮屏、未锁定」这样的一句话（显示器：亮屏 / 熄屏 / 未知；会话：已锁定 / 未锁定）。
# 显示器休眠或屏幕锁定时应用加载明显更慢（实测 300 张目录的首图耗时从 0.13 秒涨到 1.2 秒），
# 这两种状态下的数字不能和「亮屏、未锁定」时的基线互相比较，所以要写进报告、开头还要警告。
# 显示器状态用 CGDisplayIsAsleep 读（python3 ctypes，不依赖第三方包）；PIXY_BENCH_DISPLAY=asleep|awake 可强行指定（只给测试脚本用）。
screen_state() {
    local display lock
    case "${PIXY_BENCH_DISPLAY:-}" in
        asleep) display="熄屏" ;;
        awake)  display="亮屏" ;;
        *)
            case "$(python3 -I -c '
import ctypes, ctypes.util
cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))
cg.CGMainDisplayID.restype = ctypes.c_uint32
cg.CGDisplayIsAsleep.argtypes = [ctypes.c_uint32]
cg.CGDisplayIsAsleep.restype = ctypes.c_int
print(cg.CGDisplayIsAsleep(cg.CGMainDisplayID()))' 2>/dev/null)" in
                1) display="熄屏" ;;
                0) display="亮屏" ;;
                *) display="未知" ;;
            esac ;;
    esac
    if ioreg -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes'; then
        lock="已锁定"
    else
        lock="未锁定"
    fi
    printf '%s' "${display}、${lock}"
}

# is_pos_int <串> / is_decimal <串>：参数校验
is_pos_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 0 ]; }
is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
is_decimal() { printf '%s' "${1:-}" | LC_ALL=C grep -Eq '^[0-9]+(\.[0-9]+)?$'; }

# ---------------------------------------------------------------------------
# 偏好：只动 lastFolder 与 hasNormalExit 两个键，先快照后还原
# ---------------------------------------------------------------------------

# pref_snapshot <域> <键>：输出 absent | string:<值> | boolean:<0|1> | unsupported:<类型描述>
pref_snapshot() {
    local domain=$1 key=$2 type value
    if ! type=$(defaults read-type "${domain}" "${key}" 2>/dev/null); then
        printf '%s\n' "absent"
        return 0
    fi
    case "${type}" in
        "Type is string")
            value=$(defaults read "${domain}" "${key}")
            printf '%s\n' "string:${value}" ;;
        "Type is boolean")
            value=$(defaults read "${domain}" "${key}")
            printf '%s\n' "boolean:${value}" ;;
        *)
            printf '%s\n' "unsupported:${type}" ;;
    esac
}

# pref_restore <域> <键> <快照>
pref_restore() {
    local domain=$1 key=$2 snap=$3
    case "${snap}" in
        absent)      defaults delete "${domain}" "${key}" >/dev/null 2>&1 || true ;;
        string:*)    defaults write "${domain}" "${key}" -string "${snap#string:}" ;;
        boolean:1)   defaults write "${domain}" "${key}" -bool true ;;
        boolean:0)   defaults write "${domain}" "${key}" -bool false ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# 进程与清理
# ---------------------------------------------------------------------------

# app_running：有同名 PixyDbg 进程（任何路径）或命令行含被测可执行文件的路径时返回 0
app_running() {
    local name path_re
    name=$(basename "${APP}")
    if pgrep -x "${name}" >/dev/null 2>&1; then return 0; fi
    path_re=$(printf '%s' "${APP}" | sed 's/[][\.*^$()+?{|]/\\&/g')
    if pgrep -f "${path_re}( |\$)" >/dev/null 2>&1; then return 0; fi
    return 1
}

# stop_app：先 TERM，最多等 3 秒，还在就 KILL；只动本脚本启动的那个 pid
stop_app() {
    [ -n "${APP_PID}" ] || return 0
    if kill -0 "${APP_PID}" 2>/dev/null; then
        kill -TERM "${APP_PID}" 2>/dev/null || true
        local n=0
        while kill -0 "${APP_PID}" 2>/dev/null && [ "${n}" -lt 30 ]; do
            sleep 0.1
            n=$((n + 1))
        done
        if kill -0 "${APP_PID}" 2>/dev/null; then
            kill -KILL "${APP_PID}" 2>/dev/null || true
        fi
    fi
    wait "${APP_PID}" 2>/dev/null || true
    APP_PID=""
    return 0
}

# 退出（含 Ctrl-C、TERM、任何失败）时一定会跑：结束进程 → 删临时目录 → 还原偏好
cleanup() {
    local rc=$?
    set +e
    trap - EXIT INT TERM
    stop_app
    if [ -n "${CAFFEINATE_PID}" ]; then kill "${CAFFEINATE_PID}" 2>/dev/null; wait "${CAFFEINATE_PID}" 2>/dev/null; fi
    case "${WORK}" in
        "${TMP_ROOT}"/pixy-bench.*) rm -rf "${WORK}" ;;
    esac
    if [ "${PREFS_SAVED}" = "1" ]; then
        pref_restore "${DOMAIN}" lastFolder "${SNAP_LAST}"
        pref_restore "${DOMAIN}" hasNormalExit "${SNAP_EXIT}"
    fi
    exit "${rc}"
}

# ---------------------------------------------------------------------------
# 一档的测量。结果写进 R_* 全局变量，并追加一行到 ROWS
# ---------------------------------------------------------------------------
run_tier() {
    local tier=$1
    local tier_dir="${WORK}/dir-${tier}"
    local log_file="${WORK}/app-${tier}.log"
    local status="" start loaded_at=-1 elapsed rss alive settle_ticks=$((SETTLE + 1))
    [ "${SETTLE}" -eq 0 ] && settle_ticks=0
    local samples=()

    say "[bench] ${tier} 档：生成目录（硬链接复用 ${SEED_COUNT} 张种子图）…"
    mkdir "${tier_dir}"
    python3 -I "${BENCH_DIR}/gen-images.py" fan "${WORK}/seed" "${tier_dir}" "${tier}"

    defaults write "${DOMAIN}" lastFolder -string "file://${tier_dir}/"
    defaults write "${DOMAIN}" hasNormalExit -bool true

    say "[bench] ${tier} 档：启动 ${APP_NAME}，最多等 ${TIMEOUT} 秒，读完后再观察 ${SETTLE} 秒 …"
    : > "${log_file}"
    # 在临时目录里启动：Debug 构建带覆盖率插桩，会在当前目录留下 default.profraw，不能落在仓库里
    ( cd "${WORK}" && exec env PIXY_LOG_FILE="${log_file}" "${APP}" -AppleLanguages "(en)" </dev/null >/dev/null 2>&1 ) &
    APP_PID=$!
    start=${SECONDS}

    while :; do
        rss=""
        alive=1
        if kill -0 "${APP_PID}" 2>/dev/null; then
            rss=$(ps -o rss= -p "${APP_PID}" 2>/dev/null | tr -d ' ' || true)
        else
            alive=0
        fi
        if [ "${alive}" = "0" ] || [ -z "${rss}" ]; then
            status="FAIL(应用提前退出)"
            break
        fi
        samples+=("${rss}")
        elapsed=$((SECONDS - start))
        if [ "${PIXY_BENCH_VERBOSE:-}" = "1" ]; then
            say "    t=${elapsed}s rss=${rss}KB"
        fi

        if [ "${loaded_at}" -lt 0 ]; then
            if [ -n "$(parse_metric "${log_file}" "${LABEL_SIZE}")" ]; then
                loaded_at=${SECONDS}
            elif [ "${elapsed}" -ge "${TIMEOUT}" ]; then
                status="FAIL(${TIMEOUT} 秒内没读完尺寸信息)"
                break
            fi
        fi
        # SECONDS 是整数秒：要求「多过 SETTLE 个整数」才保证窗口真有 SETTLE 秒那么长（SETTLE=0 表示读完立刻结束）
        if [ "${loaded_at}" -ge 0 ] && [ $((SECONDS - loaded_at)) -ge "${settle_ticks}" ]; then
            status="OK"
            break
        fi
        sleep "${INTERVAL}"
    done

    local t_list t_first t_size t_thumb peak="" steady="" fp="" fp_cur="" fp_peak=""
    t_list=$(parse_metric "${log_file}" "${LABEL_LIST}")
    t_first=$(parse_metric "${log_file}" "${LABEL_FIRST}")
    t_size=$(parse_metric "${log_file}" "${LABEL_SIZE}")
    t_thumb=$(parse_metric "${log_file}" "${LABEL_THUMB}")
    if [ "${#samples[@]}" -gt 0 ]; then
        peak=$(max_of "${samples[@]}")
        local tail_n=5
        [ "${#samples[@]}" -lt "${tail_n}" ] && tail_n=${#samples[@]}
        steady=$(median_of "${samples[@]:$((${#samples[@]} - tail_n))}")
    fi

    if kill -0 "${APP_PID}" 2>/dev/null; then
        fp=$(read_footprint "${APP_PID}")
        fp_cur=${fp%% *}
        fp_peak=${fp##* }
        if [ -z "${fp}" ]; then fp_cur=""; fp_peak=""; fi
    fi

    if [ "${status}" != "OK" ]; then
        ANY_FAIL=1
        say "[bench] ${tier} 档失败：${status}。日志最后几行："
        tail -n 5 "${log_file}" 2>/dev/null | cut -c1-200 | sed 's/^/    | /' >&2 || true
    fi

    stop_app
    rm -rf "${tier_dir}" "${log_file}"

    ROWS="${ROWS}| ${tier} | $(fmt_secs "${t_list}") | $(fmt_secs "${t_first}") | $(fmt_secs "${t_size}") | $(fmt_secs "${t_thumb}") | $(fmt_mb "${peak}") | $(fmt_mb "${steady}") | $(fmt_mb "${fp_peak}") | $(fmt_mb "${fp_cur}") | ${status} |"$'\n'
    say "[bench] ${tier} 档完成：${status}"
    return 0
}

# ---------------------------------------------------------------------------
print_report() {
    local commit dirty built xcode SCREEN
    SCREEN=$(screen_state)
    commit=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
    dirty=""
    if [ -n "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null || true)" ]; then dirty="（工作区有未提交改动）"; fi
    built=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "${APP}" 2>/dev/null || printf 'unknown')
    xcode=$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { v = $0 } /^Build version/ { b = $3 } END { if (v != "") printf "%s (%s)", v, b }' || true)

    printf '%s\n' "## Pixy 性能基线（仅本机对比，不进 CI）"
    printf '\n'
    printf '%s\n' "- 日期：$(date '+%Y-%m-%d %H:%M')"
    printf '%s\n' "- 机器：$(sysctl -n hw.model 2>/dev/null || printf unknown) / $(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf unknown)"
    printf '%s\n' "- 系统：$(sw_vers -productName 2>/dev/null || printf unknown) $(sw_vers -productVersion 2>/dev/null || printf unknown)（$(sw_vers -buildVersion 2>/dev/null || printf unknown)）"
    printf '%s\n' "- Xcode：${xcode:-unknown}"
    printf '%s\n' "- 构建配置：Debug（${APP_NAME}，产物修改时间 ${built}）"
    printf '%s\n' "- 屏幕：${SCREEN}（只有「亮屏、未锁定」的数字能互相比较；熄屏或锁屏时应用加载更慢）"
    printf '%s\n' "- 源码 commit：${commit}${dirty}"
    printf '%s\n' "- 采样：RSS 每 ${INTERVAL} 秒一次；「尺寸信息读完」后再观察 ${SETTLE} 秒，稳态 RSS = 窗口末尾 5 个样本的中位数；单档等待上限 ${TIMEOUT} 秒"
    printf '%s\n' "- footprint：观察窗口末尾用 footprint 读一次 phys_footprint（含被系统压缩的页）；峰值是内核记录的整个进程生命周期的峰值，稳态是此刻的当前值"
    printf '\n'
    printf '%s\n' "耗时单位秒，均为从目录切换开始累计；「-」表示没有读到（日志里没出现该行，或 footprint 不可用）。"
    printf '\n'
    printf '%s\n' "| 档位 | 文件列表 | 首图 | 尺寸信息读完 | 缩略图读完 | 峰值 RSS (MB) | 稳态 RSS (MB) | 峰值 footprint (MB) | 稳态 footprint (MB) | 结果 |"
    printf '%s\n' "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|"
    printf '%s' "${ROWS}"
}

usage() {
    sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

main() {
    local dry_run=0 arg
    local tiers=()

    for arg in "$@"; do
        case "${arg}" in
            --dry-run)  dry_run=1 ;;
            -h|--help)  usage; exit 0 ;;
            -*)         die "不认识的选项：${arg}（用 --help 看用法）" ;;
            *)
                is_pos_int "${arg}" || die "档位必须是正整数，收到：${arg}"
                [ "${arg}" -le 100000 ] || die "档位不能超过 100000，收到：${arg}"
                tiers+=("${arg}") ;;
        esac
    done
    if [ "${#tiers[@]}" -eq 0 ]; then
        # shellcheck disable=SC2206
        tiers=(${DEFAULT_TIERS})
    fi

    DOMAIN="${PIXY_BENCH_DOMAIN:-com.natinli.PixyDbg}"
    APP="${PIXY_BENCH_APP:-${REPO_ROOT}/.build/DerivedData-root/Build/Products/Debug/PixyDbg.app/Contents/MacOS/PixyDbg}"
    APP_NAME=$(basename "${APP}")
    TIMEOUT="${PIXY_BENCH_TIMEOUT:-120}"
    SETTLE="${PIXY_BENCH_SETTLE:-40}"
    INTERVAL="${PIXY_BENCH_INTERVAL:-0.5}"
    TMP_ROOT="${PIXY_BENCH_TMPDIR:-/tmp}"

    is_pos_int "${SEED_COUNT}" || die "PIXY_BENCH_SEED_COUNT 必须是正整数，收到：${SEED_COUNT}"
    is_pos_int "${TIMEOUT}" || die "PIXY_BENCH_TIMEOUT 必须是正整数（秒），收到：${TIMEOUT}"
    is_uint "${SETTLE}" || die "PIXY_BENCH_SETTLE 必须是非负整数（秒），收到：${SETTLE}"
    is_decimal "${INTERVAL}" || die "PIXY_BENCH_INTERVAL 必须是数字（秒），收到：${INTERVAL}"
    printf '%s' "${TMP_ROOT}" | LC_ALL=C grep -Eq '^/[A-Za-z0-9_./-]*$' || die "PIXY_BENCH_TMPDIR 只能含字母数字和 _./-（它会被写进 file:// 地址），收到：${TMP_ROOT}"
    [ -d "${TMP_ROOT}" ] || die "PIXY_BENCH_TMPDIR 不是目录：${TMP_ROOT}"
    case "${APP}" in
        /Applications/*) die "不测 /Applications 下的应用，请用 Debug 构建的 PixyDbg：${APP}" ;;
    esac

    say "提醒：测量期间屏幕上会出现 PixyDbg 窗口（后台启动，一般不抢焦点），请不要操作它；也别同时跑别的重负载，否则数字不准。"
    say "只作本机对比：不碰 /Applications/Pixy.app，只改偏好域 ${DOMAIN} 的 lastFolder / hasNormalExit，结束后还原。"

    if [ "${dry_run}" = "1" ]; then
        say "[dry-run] 只打印计划，不生成目录、不启动进程、不改偏好。"
        printf '%s\n' "被测应用：${APP}"
        if [ -x "${APP}" ]; then printf '%s\n' "  （存在，可执行）"; else printf '%s\n' "  （不存在或不可执行：真实运行会报错）"; fi
        printf '%s\n' "偏好域：${DOMAIN}（备份并在结束后还原 lastFolder、hasNormalExit）"
        printf '%s\n' "测试目录：${TMP_ROOT}/pixy-bench.XXXXXX（结束后删除）"
    printf '%s\n' "运行期间用 caffeinate -dis 阻止显示器熄屏 / 系统睡眠（随脚本退出；不会把已经熄灭的显示器点亮）"
        printf '%s\n' "档位：${tiers[*]}"
        printf '%s\n' "每档：生成目录 → 写 lastFolder → 带 PIXY_LOG_FILE 启动 → 每 ${INTERVAL} 秒采样 RSS → 等到「${LABEL_SIZE}」（上限 ${TIMEOUT} 秒）→ 再观察 ${SETTLE} 秒 → 读一次 footprint → 结束进程并清理"
        exit 0
    fi

    # 前置检查：全部通过之前不改任何东西
    if [ ! -x "${APP}" ]; then
        die "找不到被测应用：${APP}
先构建 Debug 版：
  xcodebuild -project FlowVision.xcodeproj -scheme FlowVision -configuration Debug -derivedDataPath .build/DerivedData-root \\
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY='' SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG build
或用 PIXY_BENCH_APP 指向别处的可执行文件。"
    fi
    command -v python3 >/dev/null 2>&1 || die "需要 python3（生成测试图片）"
    command -v defaults >/dev/null 2>&1 || die "需要 macOS 的 defaults 命令"
    if app_running; then
        die "检测到 ${APP_NAME} 已在运行。为避免杀掉你正在看的实例、或让它读到被改写的偏好，请先退出它再跑。"
    fi
    if [ "$(screen_state)" != "亮屏、未锁定" ]; then
        say "警告：当前屏幕状态是「$(screen_state)」。熄屏或锁屏时应用加载明显更慢（实测 300 张目录的首图耗时 +1 秒），这次的数字不能和「亮屏、未锁定」时的基线比较（报告里会写明）。"
    fi
    SNAP_LAST=$(pref_snapshot "${DOMAIN}" lastFolder)
    SNAP_EXIT=$(pref_snapshot "${DOMAIN}" hasNormalExit)
    case "${SNAP_LAST}${SNAP_EXIT}" in
        *unsupported:*) die "${DOMAIN} 里的 lastFolder / hasNormalExit 类型不是预期的 string / boolean，无法安全备份（${SNAP_LAST} / ${SNAP_EXIT}）" ;;
    esac

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    WORK=$(mktemp -d "${TMP_ROOT}/pixy-bench.XXXXXX")
    PREFS_SAVED=1

    # 测量中途系统睡眠会让内存采样与观察窗口作废（实测遇到过两次：用户离开后整机睡眠、以及接电源时的「维护睡眠」，
    # 只有 -i 拦不住后者，-s 才行），所以整个运行期间阻止显示器熄屏（-d）、空闲睡眠（-i）和接电源时的系统睡眠（-s）；
    # -w 让它随本脚本退出。它不会把已经熄灭的显示器点亮。
    if command -v caffeinate >/dev/null 2>&1; then
        caffeinate -dis -w "$$" >/dev/null 2>&1 &
        CAFFEINATE_PID=$!
    fi

    say "[bench] 生成 ${SEED_COUNT} 张种子图 …"
    python3 -I "${BENCH_DIR}/gen-images.py" seed "${WORK}/seed" "${SEED_COUNT}"

    local tier
    for tier in "${tiers[@]}"; do
        run_tier "${tier}"
    done

    print_report
    [ "${ANY_FAIL}" = "0" ] || exit 1
    exit 0
}

# 被 source 时只提供函数；直接运行才执行 main
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
