#!/usr/bin/env python3
"""scripts/release-prepare.sh 的文本改写助手：只改本地文件，不联网、不碰 git。

不要单独使用：版本号、build 号、日期的合法性与递增规则由 release-prepare.sh 负责，
这里只负责「在文件里精确地改那几处，并在改前改后各验证一遍」。

子命令（都以 `--dry-run` 只验证并打印计划、不写文件；不带则写入）：

  pbxproj read <project.pbxproj>
      打印 FlowVision 目标当前的「版本 build号」。要求该目标恰有 Debug、Release 两个配置，各有且仅有一行
      MARKETING_VERSION 与 CURRENT_PROJECT_VERSION，且两个配置的值相同；否则报错。

  pbxproj edit <project.pbxproj> --old-version V --old-build B --new-version V --new-build B [--dry-run]
      只改 FlowVision 目标那两个配置里的 4 行（测试目标 PixyTests 的 1.0 / 1 不是这里的值，也不在这两个配置里，
      不会被碰到）。改前对原文件、改后对临时文件各跑 plutil -lint；改后回读，要求内容与计划逐字节一致，
      且与原文件相比恰好 4 行不同。

  changelog edit <CHANGELOG.md> --version V --date YYYY-MM-DD [--dry-run]
      把「## [Fork] 未发布」标题换成「## [Fork] <日期> — <版本>」，其后补一句未签名说明（与 0.0.5 / 0.0.6 的
      发版提交一致：只换标题，不在上方再留一个空的「未发布」）。要求「未发布」小节唯一且有实际内容，
      且文件里没有同版本的小节。

  checklist edit <release-smoke-checklist.md> --version V --build B --prev-version V --prev-build B
                 --date YYYY-MM-DD [--dry-run]
      在「## 记录」段顶部插入「### <版本>（未签名版）」骨架（tag、build、日期已填，其余留空待填）。

退出码：0 成功；1 任何校验或写入失败（消息在 stderr）。文件一律先写同目录临时文件、校验后 os.replace 原子替换，
任何一步失败都不落盘（已落盘后的回读校验失败则由调用方 release-prepare.sh 还原）。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

APP_TARGET = "FlowVision"  # PBXNativeTarget 名称；产物名是 Pixy，目标名沿用上游
EM_DASH = "—"
UNRELEASED_HEADING = "## [Fork] 未发布"
UNSIGNED_NOTE = "仍为**未签名**版本，升级后首次启动需再放行一次（[安装说明](docs/user/installation.md)）。"
CHECKLIST_SECTION = "## 记录"
VERSION_RE = re.compile(r"^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$")
BUILD_RE = re.compile(r"^[0-9]{10}$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


class ReleaseError(Exception):
    """面向用户的错误，消息直接打印。"""


# ---------------------------------------------------------------------------
# 读写
# ---------------------------------------------------------------------------

def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
    except OSError as e:
        raise ReleaseError("无法读取 %s：%s" % (path, e.strerror or e))
    except UnicodeDecodeError:
        raise ReleaseError("%s 不是 UTF-8 文本" % path)
    if "\r" in text:
        raise ReleaseError("%s 含 CR 行尾，本脚本只处理 LF 行尾的文件" % path)
    return text


FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def outside_fence(lines):
    """逐行标记「是否在围栏代码块（``` 或 ~~~）之外」；围栏行本身算块内。

    CHANGELOG / checklist 里的标题要认真实标题，不能认代码块里举例用的同名标题。
    围栏没有闭合时，其后的所有行都算块内（宁可「找不到」而拒绝，也不去改一个不确定的标题）。
    """
    flags = []
    fence = None  # (字符, 长度)
    for line in lines:
        m = FENCE_RE.match(line)
        if fence is None:
            flags.append(m is None)
            if m:
                fence = (m.group(1)[0], len(m.group(1)))
        else:
            flags.append(False)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not line[m.end():].strip():
                fence = None
    return flags


def atomic_write(path, text, validate=None):
    """先写同目录临时文件、可选校验、再原子替换；pbxproj 是符号链接时写到链接目标上。"""
    real = os.path.realpath(path)
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(prefix=".%s." % os.path.basename(real), suffix=".tmp", dir=os.path.dirname(real))
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        shutil.copymode(real, tmp)
        if validate is not None:
            validate(tmp)
        os.replace(tmp, real)
        tmp = None
    except OSError as e:
        raise ReleaseError("写入 %s 失败：%s" % (path, e.strerror or e))
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.unlink(tmp)
    if read_text(path) != text:
        raise ReleaseError("写入 %s 后回读内容与计划不一致" % path)


def plutil_lint(path):
    try:
        r = subprocess.run(["plutil", "-lint", path], capture_output=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise ReleaseError("需要 macOS 自带的 plutil 来校验 pbxproj 结构，但没有找到它")
    if r.returncode != 0:
        raise ReleaseError("plutil -lint 未通过：%s" % (r.stdout + r.stderr).strip())


def plutil_json(path):
    try:
        r = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise ReleaseError("需要 macOS 自带的 plutil 来解析 pbxproj，但没有找到它")
    if r.returncode != 0:
        raise ReleaseError("plutil 无法解析 %s：%s" % (path, (r.stdout + r.stderr).strip()))
    return json.loads(r.stdout)


# ---------------------------------------------------------------------------
# pbxproj
# ---------------------------------------------------------------------------

SETTING_RE = {
    "MARKETING_VERSION": re.compile(r"^(\t\t\t\tMARKETING_VERSION = )([^;\"]+)(;)$"),
    "CURRENT_PROJECT_VERSION": re.compile(r"^(\t\t\t\tCURRENT_PROJECT_VERSION = )([^;\"]+)(;)$"),
}


def app_config_ids(path):
    """FlowVision 目标的构建配置 ID（沿 目标 -> 配置列表 -> 配置，不靠值或名字猜）。"""
    objs = plutil_json(path)["objects"]
    targets = [v for v in objs.values() if v.get("isa") == "PBXNativeTarget" and v.get("name") == APP_TARGET]
    if len(targets) != 1:
        raise ReleaseError("pbxproj 里应当恰有 1 个名为 %s 的目标，实际 %d 个" % (APP_TARGET, len(targets)))
    config_list = objs[targets[0]["buildConfigurationList"]]
    ids = list(config_list["buildConfigurations"])
    if len(ids) != 2:
        raise ReleaseError("%s 目标应当恰有 Debug、Release 两个构建配置，实际 %d 个" % (APP_TARGET, len(ids)))
    return ids


def config_block(lines, config_id):
    """配置定义块的 [起, 止) 行号：起于「\\t\\t<ID> /* 名 */ = {」，止于下一个「\\t\\t};」之后。"""
    head = re.compile(r"^\t\t%s /\* .* \*/ = \{$" % re.escape(config_id))
    starts = [i for i, line in enumerate(lines) if head.match(line)]
    if len(starts) != 1:
        raise ReleaseError("找不到构建配置 %s 的定义块（匹配 %d 处）" % (config_id, len(starts)))
    for j in range(starts[0] + 1, len(lines)):
        if lines[j] == "\t\t};":
            return starts[0], j + 1
    raise ReleaseError("构建配置 %s 的定义块没有闭合" % config_id)


def app_settings(path, lines):
    """返回 {配置ID: {设置名: (行号, 值)}}，并校验每个配置各有且仅有一行、两个配置值相同。"""
    found = {}
    for config_id in app_config_ids(path):
        start, end = config_block(lines, config_id)
        entry = {}
        for name, regex in SETTING_RE.items():
            hits = [(i, regex.match(lines[i])) for i in range(start, end) if regex.match(lines[i])]
            if len(hits) != 1:
                raise ReleaseError(
                    "%s 目标的构建配置 %s 里 %s 应当恰有 1 行（写成不带引号的单个值），实际 %d 行"
                    % (APP_TARGET, config_id, name, len(hits)))
            i, m = hits[0]
            entry[name] = (i, m.group(2).strip())
        found[config_id] = entry
    for name in SETTING_RE:
        values = sorted({entry[name][1] for entry in found.values()})
        if len(values) != 1:
            raise ReleaseError("%s 目标的 Debug / Release 两个配置里 %s 不一致：%s" % (APP_TARGET, name, "、".join(values)))
    reject_lookalikes(lines, found)
    return found


ANY_SETTING_RE = re.compile(r"^\s*(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = \"?([^;\"]+)\"?;\s*$")


def reject_lookalikes(lines, found):
    """FlowVision 目标之外若还有行的值与它当前的版本 / build 号相同，拒绝：本脚本只改那两个配置，会把它们漏掉。

    （现在测试目标 PixyTests 是 1.0 / 1，不会撞；将来若新增与 App 同值的目标——比如要同步版本的内嵌扩展——
    默默只改 App 会让两边版本不一致，宁可拒绝让人确认。）
    """
    mine = {i for entry in found.values() for (i, _value) in entry.values()}
    current = {name: next(iter(found.values()))[name][1] for name in SETTING_RE}
    clash = {}
    for i, line in enumerate(lines):
        m = ANY_SETTING_RE.match(line)
        if m and i not in mine and m.group(2).strip() == current[m.group(1)]:
            clash.setdefault(m.group(1), []).append(i + 1)
    if clash:
        detail = "；".join("%s = %s 还出现在第 %s 行" % (name, current[name], "、".join(str(n) for n in nums))
                          for name, nums in sorted(clash.items()))
        raise ReleaseError(
            "pbxproj 里 %s 目标之外，还有别的目标 / 配置使用了与它相同的值：%s。\n"
            "本脚本只改 %s 目标的两个配置，会把这些行漏掉（例如新增了要与 App 同步版本的内嵌扩展，或项目级配置）；"
            "先确认它们该不该一起升级，再手工处理或扩展本脚本。" % (APP_TARGET, detail, APP_TARGET))


def pbxproj_current(path):
    text = read_text(path)
    plutil_lint(path)
    found = app_settings(path, text.split("\n"))
    any_entry = next(iter(found.values()))
    return any_entry["MARKETING_VERSION"][1], any_entry["CURRENT_PROJECT_VERSION"][1]


def cmd_pbxproj_read(args):
    version, build = pbxproj_current(args.file)
    print("%s %s" % (version, build))


def cmd_pbxproj_edit(args):
    for label, value, regex in (("--old-version", args.old_version, VERSION_RE), ("--new-version", args.new_version, VERSION_RE),
                                ("--old-build", args.old_build, BUILD_RE), ("--new-build", args.new_build, BUILD_RE)):
        if not regex.match(value):
            raise ReleaseError("%s 的值不合法：%r" % (label, value))
    text = read_text(args.file)
    plutil_lint(args.file)
    lines = text.split("\n")
    found = app_settings(args.file, lines)
    cur_version = next(iter(found.values()))["MARKETING_VERSION"][1]
    cur_build = next(iter(found.values()))["CURRENT_PROJECT_VERSION"][1]
    if (cur_version, cur_build) != (args.old_version, args.old_build):
        raise ReleaseError("pbxproj 当前是 %s / %s，与预期的 %s / %s 不符（文件在检查之后被改过？）"
                           % (cur_version, cur_build, args.old_version, args.old_build))
    new_values = {"MARKETING_VERSION": args.new_version, "CURRENT_PROJECT_VERSION": args.new_build}
    new_lines = list(lines)
    touched = []
    for entry in found.values():
        for name, (i, _old) in entry.items():
            new_lines[i] = SETTING_RE[name].sub(lambda m, v=new_values[name]: m.group(1) + v + m.group(3), lines[i])
            touched.append((i + 1, name))
    changed = [i for i, (a, b) in enumerate(zip(lines, new_lines)) if a != b]
    if len(changed) != 4 or len(lines) != len(new_lines):
        raise ReleaseError("内部校验失败：应恰好改 4 行，实际 %d 行" % len(changed))
    new_text = "\n".join(new_lines)

    # 全文件计数：新值多 2 处、旧值少 2 处（测试目标 PixyTests 的 1.0 / 1 不受影响）
    for name in SETTING_RE:
        old_line = "%s = %s;" % (name, args.old_version if name == "MARKETING_VERSION" else args.old_build)
        new_line = "%s = %s;" % (name, new_values[name])
        if new_text.count(old_line) != text.count(old_line) - 2 or new_text.count(new_line) != text.count(new_line) + 2:
            raise ReleaseError("内部校验失败：%s 的新旧值计数不符合预期" % name)
    others = sum(1 for line in lines if re.match(r"^\t\t\t\t(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = ", line)) - 4

    print("pbxproj  %s" % args.file)
    print("  MARKETING_VERSION        %s -> %s   （%s 目标 Debug、Release 各一处，第 %s 行）" % (
        args.old_version, args.new_version, APP_TARGET,
        "、".join(str(n) for n, name in sorted(touched) if name == "MARKETING_VERSION")))
    print("  CURRENT_PROJECT_VERSION  %s -> %s   （同上，第 %s 行）" % (
        args.old_build, args.new_build,
        "、".join(str(n) for n, name in sorted(touched) if name == "CURRENT_PROJECT_VERSION")))
    print("  不动：其余 %d 行 MARKETING_VERSION / CURRENT_PROJECT_VERSION（另外的目标，值与 Pixy 无关）" % others)
    if args.dry_run:
        return

    def validate(tmp):
        plutil_lint(tmp)
        check = app_settings(tmp, new_text.split("\n"))
        entry = next(iter(check.values()))
        if (entry["MARKETING_VERSION"][1], entry["CURRENT_PROJECT_VERSION"][1]) != (args.new_version, args.new_build):
            raise ReleaseError("改写后的 pbxproj 回读到的版本不是预期值")

    atomic_write(args.file, new_text, validate)
    version, build = pbxproj_current(args.file)
    if (version, build) != (args.new_version, args.new_build):
        raise ReleaseError("写入后回读到 %s / %s，不是预期的 %s / %s" % (version, build, args.new_version, args.new_build))
    print("  已写入并回读校验（plutil -lint 通过，恰好改了 4 行）")


# ---------------------------------------------------------------------------
# CHANGELOG
# ---------------------------------------------------------------------------

def cmd_changelog_edit(args):
    if not VERSION_RE.match(args.version):
        raise ReleaseError("--version 的值不合法：%r" % args.version)
    if not DATE_RE.match(args.date):
        raise ReleaseError("--date 的值不合法：%r" % args.date)
    text = read_text(args.file)
    lines = text.split("\n")
    out = outside_fence(lines)
    at = [i for i, line in enumerate(lines) if out[i] and line.rstrip() == UNRELEASED_HEADING]
    if not at:
        raise ReleaseError("%s 里找不到「%s」小节（没有记录要发布的改动，或标题被改过）" % (args.file, UNRELEASED_HEADING))
    if len(at) > 1:
        raise ReleaseError("%s 里有 %d 个「%s」标题，无法确定该转换哪一个" % (args.file, len(at), UNRELEASED_HEADING))
    i = at[0]
    end = next((k for k in range(i + 1, len(lines)) if out[k] and lines[k].startswith("## ")), len(lines))
    body = [line for line in lines[i + 1:end] if line.strip()]
    if not body:
        raise ReleaseError("「%s」小节下没有任何内容（只有标题和空行），没有东西可发；先把本版改动记进 CHANGELOG" % UNRELEASED_HEADING)
    suffix = "%s %s" % (EM_DASH, args.version)
    for k, line in enumerate(lines):
        if out[k] and line.startswith("## [Fork]") and line.rstrip().endswith(suffix):
            raise ReleaseError("%s 里已经有版本 %s 的小节：%s" % (args.file, args.version, line.rstrip()))

    new_heading = "## [Fork] %s %s %s" % (args.date, EM_DASH, args.version)
    has_note = body[0].startswith("仍为**未签名**版本")
    head = [new_heading]
    if not has_note:
        head += ["", UNSIGNED_NOTE]
        if i + 1 < len(lines) and lines[i + 1].strip():  # 标题后原本没有空行，补一个把说明与正文隔开
            head += [""]
    new_lines = lines[:i] + head + lines[i + 1:]
    new_text = "\n".join(new_lines)

    print("CHANGELOG  %s" % args.file)
    print("  标题：%s" % UNRELEASED_HEADING)
    print("    ->  %s" % new_heading)
    print("  「未发布」小节共 %d 行非空内容，随标题一起成为 %s 的小节；上方不再留空的「未发布」（与 0.0.5、0.0.6 发版提交一致）" % (len(body), args.version))
    if has_note:
        print("  未签名说明：小节开头已有，不重复插入")
    else:
        print("  其后插入：%s" % UNSIGNED_NOTE)
    if args.dry_run:
        return

    atomic_write(args.file, new_text)
    check = read_text(args.file).split("\n")
    check_out = outside_fence(check)
    if (sum(1 for k, line in enumerate(check) if check_out[k] and line.rstrip() == new_heading) != 1
            or any(check_out[k] and line.rstrip() == UNRELEASED_HEADING for k, line in enumerate(check))):
        raise ReleaseError("写入后回读 CHANGELOG：标题不符合预期")
    print("  已写入并回读校验")


# ---------------------------------------------------------------------------
# checklist
# ---------------------------------------------------------------------------

ORDINALS = {1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "七", 8: "八", 9: "九", 10: "十"}


def checklist_skeleton(version, build, prev_version, prev_build, date):
    seq = int(build[8:])
    nth = "当日第%s版" % ORDINALS.get(seq, " %d " % seq)
    return [
        "### %s（未签名版）" % version,
        "",
        "- Release tag：`v%s`；build `%s`（%s，build 号规则见 release.md，大于 %s 的 `%s`）" % (version, build, nth, prev_version, prev_build),
        "- macOS / Xcode：",
        "- 架构：",
        "- 本地产物（上面的签名、架构、DMG 结构检查针对它；Release 页附件由 CI 重建，哈希不同，以 Release 的 `SHA256SUMS.txt` 为准）：",
        "  - ZIP ``",
        "  - DMG ``",
        "- Release 页附件（CI 构建，下载后 `shasum -a 256 -c SHA256SUMS.txt` 核对；Latest、非 pre-release）：",
        "  - ZIP ``",
        "  - DMG ``",
        "- 发布过程：",
        "- 本版内容：",
        "- 界面验证范围：",
        "- 未覆盖：",
        "- 日期：%s" % date,
    ]


def cmd_checklist_edit(args):
    for label, value, regex in (("--version", args.version, VERSION_RE), ("--prev-version", args.prev_version, VERSION_RE),
                                ("--build", args.build, BUILD_RE), ("--prev-build", args.prev_build, BUILD_RE),
                                ("--date", args.date, DATE_RE)):
        if not regex.match(value):
            raise ReleaseError("%s 的值不合法：%r" % (label, value))
    text = read_text(args.file)
    lines = text.split("\n")
    out = outside_fence(lines)
    at = [i for i, line in enumerate(lines) if out[i] and line.rstrip() == CHECKLIST_SECTION]
    if not at:
        raise ReleaseError("%s 里找不到「%s」段，无法插入本版骨架" % (args.file, CHECKLIST_SECTION))
    if len(at) > 1:
        raise ReleaseError("%s 里有 %d 个「%s」标题，无法确定插在哪里" % (args.file, len(at), CHECKLIST_SECTION))
    heading = "### %s（未签名版）" % args.version
    if any(out[k] and line.rstrip() == heading for k, line in enumerate(lines)):
        raise ReleaseError("%s 里已经有「%s」" % (args.file, heading))
    i = at[0]
    j = next((k for k in range(i + 1, len(lines)) if lines[k].strip()), len(lines))
    skeleton = checklist_skeleton(args.version, args.build, args.prev_version, args.prev_build, args.date)
    tail = lines[j:]
    if tail and tail != [""]:
        new_lines = lines[:i + 1] + [""] + skeleton + [""] + tail
    else:  # 「## 记录」是最后一段且下面什么都没有
        new_lines = lines[:i + 1] + [""] + skeleton + [""]
    new_text = "\n".join(new_lines)

    print("checklist  %s" % args.file)
    print("  在「%s」段顶部插入（tag、build、日期已填，其余留空待填）：" % CHECKLIST_SECTION)
    for line in skeleton:
        print("    | %s" % line if line else "    |")
    if args.dry_run:
        return

    atomic_write(args.file, new_text)
    check = read_text(args.file).split("\n")
    check_out = outside_fence(check)
    at_check = [k for k, line in enumerate(check) if check_out[k] and line.rstrip() == CHECKLIST_SECTION]
    if len(at_check) != 1 or check[at_check[0] + 1] != "" or check[at_check[0] + 2] != heading:
        raise ReleaseError("写入后回读 checklist：骨架不在「%s」段顶部" % CHECKLIST_SECTION)
    print("  已写入并回读校验")


# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="release-prepare-edit.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="area", required=True)

    pb = sub.add_parser("pbxproj").add_subparsers(dest="action", required=True)
    r = pb.add_parser("read")
    r.add_argument("file")
    r.set_defaults(fn=cmd_pbxproj_read)
    e = pb.add_parser("edit")
    e.add_argument("file")
    e.add_argument("--old-version", required=True)
    e.add_argument("--old-build", required=True)
    e.add_argument("--new-version", required=True)
    e.add_argument("--new-build", required=True)
    e.add_argument("--dry-run", action="store_true")
    e.set_defaults(fn=cmd_pbxproj_edit)

    cl = sub.add_parser("changelog").add_subparsers(dest="action", required=True)
    e = cl.add_parser("edit")
    e.add_argument("file")
    e.add_argument("--version", required=True)
    e.add_argument("--date", required=True)
    e.add_argument("--dry-run", action="store_true")
    e.set_defaults(fn=cmd_changelog_edit)

    ck = sub.add_parser("checklist").add_subparsers(dest="action", required=True)
    e = ck.add_parser("edit")
    e.add_argument("file")
    e.add_argument("--version", required=True)
    e.add_argument("--build", required=True)
    e.add_argument("--prev-version", required=True)
    e.add_argument("--prev-build", required=True)
    e.add_argument("--date", required=True)
    e.add_argument("--dry-run", action="store_true")
    e.set_defaults(fn=cmd_checklist_edit)
    return p


def main(argv):
    # 系统自带的 Python 3.9 在非 UTF-8 的 locale（LC_ALL=en_US.ISO8859-1 / US-ASCII）下，默认编码会让中文输出抛 UnicodeEncodeError；
    # 本脚本的输出一律按 UTF-8 写（与终端无关：消息由 bash 脚本原样转给用户）。
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    args = build_parser().parse_args(argv)
    try:
        args.fn(args)
    except ReleaseError as e:
        print("%s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
