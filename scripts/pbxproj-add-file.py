#!/usr/bin/env python3
"""把一个新的 Swift 源文件登记进 FlowVision.xcodeproj/project.pbxproj。

背景：本工程没有使用自动同步的文件夹，新增一个源文件要同时改 4 处，手改很容易漏或写错：
  1. PBXBuildFile        一行，「X.swift in Sources」，指向文件引用
  2. PBXFileReference    一行，文件本身
  3. PBXGroup.children   所属组里加一项（沿组树按 path 逐级匹配，不硬编码组 ID）
  4. PBXSourcesBuildPhase.files   目标的「Sources」编译阶段里加一项

用法：
  scripts/pbxproj-add-file.py <相对仓库根的路径> --target app|tests [--project <pbxproj>] [--root <仓库根>] [--dry-run]

  --target app    登记进 FlowVision 应用目标（文件须位于 FlowVision/ 下）
  --target tests  登记进 PixyTests 目标（文件须位于 PixyTests/ 下）
  --project       pbxproj 路径（或 .xcodeproj 目录），默认是本仓库的真实工程；在副本上试用时指向副本
  --root          用来检查「文件存在」的仓库根，默认是 pbxproj 所在 .xcodeproj 的上一级
  --dry-run       只打印将登记的内容并做校验，不写任何文件

行为约定：
  - 幂等：文件已登记（所属组里已有同名 path 的文件引用、且目标的编译阶段里已有指向它的构建项）
    就什么都不改，提示「已登记」并以 0 退出；只缺其中一部分时只补缺的部分。
  - ID：24 位大写十六进制。文件引用 ID = sha1(相对路径) 前 24 位，构建项 ID = sha1("build:" + 相对路径)
    前 24 位；与文件里已有的任何 24 位十六进制串冲突时依次 +1。同一文件、同一工程文本每次得到同一组 ID。
  - 插入位置：两个「一行一项」的 section 按 ID 升序插入（与 Xcode 自己的写法一致，之后用 Xcode 保存
    不会产生多余 diff）；组的 children 与编译阶段的 files 追加在末尾（Xcode 保留用户顺序）。
  - 校验：写入前对原文件、写入前对新内容都做「括号/花括号/引号平衡 + 内置解析 + 与 plutil -lint」检查，
    并对比新旧对象确认只多了预期的几项；新内容先写临时文件、校验通过后才原子替换，任何一步失败都不落盘。
  - 只支持 .swift；文件必须真实存在，且文件名大小写与磁盘一致（macOS 默认大小写不敏感，real.swift 能找到 Real.swift，
    但登记进工程的必须是磁盘上的拼写）；相对路径按仓库根解析，不是当前目录；只用 Python 标准库。
  - pbxproj 本身是符号链接时，改动写到链接目标上，链接保持不变。

退出码：0 成功（含已登记、dry-run）；1 参数/校验/登记失败；2 命令行参数错误（argparse）。
"""
import argparse
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path
from types import SimpleNamespace

# --target 到 PBXNativeTarget 名称的映射；目标名同时也是该目标源文件所在的顶层目录
TARGETS = {"app": "FlowVision", "tests": "PixyTests"}

DEFAULT_PROJECT = Path(__file__).resolve().parent.parent / "FlowVision.xcodeproj" / "project.pbxproj"
ID_TOKEN = re.compile(r"\b[0-9A-Fa-f]{24}\b")
ID_LINE = re.compile(r"^\t+([0-9A-Fa-f]{24})\b")


class RegisterError(Exception):
    """面向用户的错误，消息直接打印。"""


# ---------------------------------------------------------------------------
# 括号 / 花括号 / 引号平衡校验
# ---------------------------------------------------------------------------

def check_balance(text):
    """扫描一遍：跳过注释与引号字符串，检查 { } ( ) 严格嵌套且引号、块注释都已闭合。"""
    pairs = {"}": "{", ")": "("}
    stack = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == '"':
            start_line = line
            i += 1
            while True:
                if i >= n:
                    raise RegisterError("引号不平衡：第 %d 行开始的字符串没有闭合" % start_line)
                ch = text[i]
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    i += 1
                    break
                if ch == "\n":
                    line += 1
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise RegisterError("注释不平衡：第 %d 行开始的 /* 没有闭合" % line)
            line += text.count("\n", i, end)
            i = end + 2
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = n if end < 0 else end
        elif c in "{(":
            stack.append((c, line))
            i += 1
        elif c in "})":
            if not stack or stack[-1][0] != pairs[c]:
                raise RegisterError("括号不平衡：第 %d 行出现多余或不匹配的 %s" % (line, c))
            stack.pop()
            i += 1
        else:
            i += 1
    if stack:
        raise RegisterError("括号不平衡：第 %d 行的 %s 没有闭合" % (stack[-1][1], stack[-1][0]))


# ---------------------------------------------------------------------------
# 旧式（ASCII）plist 解析：只为读结构，并记录每个列表右括号的偏移用于定位插入点
# ---------------------------------------------------------------------------

class PDict(dict):
    pass


class PList(list):
    close = -1  # 右括号 ")" 在原文里的字符偏移


class PlistError(Exception):
    pass


_UNQUOTED = re.compile(r"[A-Za-z0-9_$+/:.\-]+")
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}


class _Parser:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def fail(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise PlistError("第 %d 行：%s" % (line, msg))

    def skip(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("/*", self.i):
                end = s.find("*/", self.i + 2)
                if end < 0:
                    self.fail("注释没有闭合")
                self.i = end + 2
            elif s.startswith("//", self.i):
                end = s.find("\n", self.i)
                self.i = n if end < 0 else end + 1
            else:
                break

    def peek(self):
        self.skip()
        if self.i >= len(self.s):
            self.fail("意外的文件结尾")
        return self.s[self.i]

    def expect(self, ch):
        if self.peek() != ch:
            self.fail("期望 %r，实际是 %r" % (ch, self.s[self.i]))
        self.i += 1

    def string(self):
        if self.peek() == '"':
            self.i += 1
            out = []
            while True:
                if self.i >= len(self.s):
                    self.fail("引号没有闭合")
                c = self.s[self.i]
                if c == "\\":
                    nxt = self.s[self.i + 1] if self.i + 1 < len(self.s) else ""
                    out.append(_ESCAPES.get(nxt, nxt))
                    self.i += 2
                elif c == '"':
                    self.i += 1
                    return "".join(out)
                else:
                    out.append(c)
                    self.i += 1
        m = _UNQUOTED.match(self.s, self.i)
        if not m:
            self.fail("无法识别的字符 %r" % self.s[self.i])
        self.i = m.end()
        return m.group(0)

    def value(self):
        c = self.peek()
        if c == "{":
            self.i += 1
            d = PDict()
            while self.peek() != "}":
                key = self.string()
                self.expect("=")
                val = self.value()
                self.expect(";")
                if key in d:
                    self.fail("重复的键 %s" % key)
                d[key] = val
            self.i += 1
            return d
        if c == "(":
            self.i += 1
            lst = PList()
            while self.peek() != ")":
                lst.append(self.value())
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() != ")":
                    self.fail("列表项之间缺少逗号")
            lst.close = self.i
            self.i += 1
            return lst
        return self.string()


def parse_plist(text):
    p = _Parser(text)
    try:
        root = p.value()
        p.skip()
        if p.i != len(text):
            p.fail("顶层之后还有多余内容")
    except PlistError as e:
        raise RegisterError("解析 pbxproj 失败，%s" % e)
    if not isinstance(root, PDict) or not isinstance(root.get("objects"), PDict):
        raise RegisterError("不是预期的 pbxproj 结构（缺少顶层 objects 字典）")
    return root


def plutil_lint(path):
    """macOS 上用系统 plutil 再校验一次；没有 plutil（非 macOS）返回 False 表示跳过。"""
    exe = shutil.which("plutil")
    if not exe:
        return False
    r = subprocess.run([exe, "-lint", str(path)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True)
    if r.returncode != 0:
        raise RegisterError("plutil -lint 未通过：%s" % r.stdout.strip())
    return True


def validate_text(text):
    """内存里的校验：平衡检查 + 内置解析。返回解析结果。"""
    check_balance(text)
    return parse_plist(text)


# ---------------------------------------------------------------------------
# 生成条目
# ---------------------------------------------------------------------------

def plist_quote(s):
    """与 Xcode 一致：只含字母数字与 _ . / 时不加引号，其余（含 + -）一律加引号。"""
    if re.fullmatch(r"[A-Za-z0-9_./]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def make_id(seed, taken):
    n = int(hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24], 16)
    while True:
        cand = "%024X" % n
        if cand not in taken:
            taken.add(cand)
            return cand
        n = (n + 1) % (1 << 96)


def find_group(objects, group_id, parts, depth=0):
    """从 group_id 起沿组树按 path 逐级匹配 parts（目录层级），返回 (组 ID, [沿途 path])；找不到返回 None。

    有 path 的组消耗对应的目录层级；只有 name 没有 path 的组是纯逻辑分组，不消耗层级，
    会继续往里找。"""
    if not parts:
        return group_id, []
    if depth > 64:
        return None
    for cid in objects[group_id].get("children", []):
        child = objects.get(cid)
        if not child or child.get("isa") != "PBXGroup" or child.get("sourceTree") != "<group>":
            continue
        path = child.get("path")
        if path:
            seg = [x for x in path.split("/") if x]
            if seg and parts[:len(seg)] == seg:
                found = find_group(objects, cid, parts[len(seg):], depth + 1)
                if found:
                    return found[0], [path] + found[1]
        else:
            found = find_group(objects, cid, parts, depth + 1)
            if found:
                return found
    return None


def flat_section_offset(text, isa, new_id):
    """「一行一项」的 section 里，找到第一个 ID 大于 new_id 的条目行首；没有则落在 End 标记之前。"""
    begin = re.search(r"^/\* Begin %s section \*/[ \t]*\n" % isa, text, re.M)
    end = re.search(r"^/\* End %s section \*/" % isa, text, re.M)
    if not begin or not end or end.start() < begin.end():
        raise RegisterError("找不到 %s section" % isa)
    pos = begin.end()
    while pos < end.start():
        nl = text.index("\n", pos)
        m = ID_LINE.match(text[pos:nl])
        if m and m.group(1).upper() > new_id:
            return pos
        pos = nl + 1
    return end.start()


def list_append_point(text, lst, what):
    """列表末尾追加：返回 (右括号所在行的行首偏移, 新条目的缩进)。要求右括号独占一行（Xcode 的写法）。"""
    close = lst.close
    line_start = text.rfind("\n", 0, close) + 1
    lead = text[line_start:close]
    if lead.strip() != "":
        raise RegisterError("%s 的列表不是「右括号独占一行」的格式，请手工登记" % what)
    return line_start, lead + "\t"


def make_plan(text, root, rel, target):
    objects = root["objects"]
    name = rel.rsplit("/", 1)[-1]
    target_name = TARGETS[target]

    top = rel.split("/")[0]
    if "/" not in rel or top != target_name:
        raise RegisterError("--target %s 的源文件应位于 %s/ 目录下（收到 %s）" % (target, target_name, rel))

    projects = [o for o in objects.values() if o.get("isa") == "PBXProject"]
    if len(projects) != 1 or projects[0].get("mainGroup") not in objects:
        raise RegisterError("找不到唯一的 PBXProject / mainGroup")
    main_group = projects[0]["mainGroup"]

    found = find_group(objects, main_group, rel.split("/")[:-1])
    if not found:
        raise RegisterError("组树里找不到与目录 %s 对应的组（逐级按 path 匹配）；请先在 Xcode 里建组" % "/".join(rel.split("/")[:-1]))
    group_id, chain = found
    group = objects[group_id]
    if not isinstance(group.get("children"), PList):
        raise RegisterError("组 %s 没有 children 列表" % group_id)

    targets = [o for o in objects.values() if o.get("isa") == "PBXNativeTarget" and o.get("name") == target_name]
    if len(targets) != 1:
        raise RegisterError("找不到唯一的目标 %s" % target_name)
    phases = [pid for pid in targets[0].get("buildPhases", [])
              if objects.get(pid, {}).get("isa") == "PBXSourcesBuildPhase"]
    if len(phases) != 1:
        raise RegisterError("目标 %s 应恰有 1 个 Sources 编译阶段，实际 %d 个" % (target_name, len(phases)))
    phase_id = phases[0]
    phase = objects[phase_id]
    if not isinstance(phase.get("files"), PList):
        raise RegisterError("编译阶段 %s 没有 files 列表" % phase_id)

    # 已有的文件引用（所属组里同名 path）与指向它的构建项（在该目标的编译阶段里）
    ref_id = next((c for c in group["children"]
                   if objects.get(c, {}).get("isa") == "PBXFileReference" and objects[c].get("path") == name), None)
    build_id = None
    if ref_id:
        build_id = next((b for b in phase["files"]
                         if objects.get(b, {}).get("isa") == "PBXBuildFile" and objects[b].get("fileRef") == ref_id), None)

    plan = SimpleNamespace(rel=rel, name=name, target=target, target_name=target_name,
                           group_id=group_id, group_path="/".join(chain), phase_id=phase_id,
                           ref_id=ref_id, build_id=build_id,
                           new_ref=ref_id is None, new_build=build_id is None,
                           edits=[], lines=[])
    if not plan.new_ref and not plan.new_build:
        return plan

    taken = {m.upper() for m in ID_TOKEN.findall(text)}
    if plan.new_ref:
        plan.ref_id = make_id(rel, taken)
    if plan.new_build:
        plan.build_id = make_id("build:" + rel, taken)

    if plan.new_build:
        line = "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            plan.build_id, name, plan.ref_id, name)
        plan.edits.append((flat_section_offset(text, "PBXBuildFile", plan.build_id), line))
        plan.lines.append(("PBXBuildFile", line))
    if plan.new_ref:
        line = ("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
                "path = %s; sourceTree = \"<group>\"; };\n") % (plan.ref_id, name, plist_quote(name))
        plan.edits.append((flat_section_offset(text, "PBXFileReference", plan.ref_id), line))
        plan.lines.append(("PBXFileReference", line))
        offset, indent = list_append_point(text, group["children"], "组 " + (plan.group_path or group_id))
        line = "%s%s /* %s */,\n" % (indent, plan.ref_id, name)
        plan.edits.append((offset, line))
        plan.lines.append(("PBXGroup %s (%s) children" % (group_id, plan.group_path), line))
    if plan.new_build:
        offset, indent = list_append_point(text, phase["files"], "编译阶段 " + phase_id)
        line = "%s%s /* %s in Sources */,\n" % (indent, plan.build_id, name)
        plan.edits.append((offset, line))
        plan.lines.append(("PBXSourcesBuildPhase %s (%s) files" % (phase_id, target_name), line))

    if len({o for o, _ in plan.edits}) != len(plan.edits):
        raise RegisterError("内部错误：多处插入点重合")
    return plan


def apply_edits(text, edits):
    """edits: [(偏移, 要插入的文本)]。从后往前插入，前面的偏移不受影响。"""
    for offset, chunk in sorted(edits, key=lambda e: e[0], reverse=True):
        text = text[:offset] + chunk + text[offset:]
    return text


def verify_result(old_root, new_root, plan):
    """对比新旧解析结果：只多出预期的对象与列表项，其余逐项相等。"""
    old_o, new_o = old_root["objects"], new_root["objects"]
    expect = set()
    if plan.new_ref:
        expect.add(plan.ref_id)
    if plan.new_build:
        expect.add(plan.build_id)
    if set(new_o) - set(old_o) != expect or set(old_o) - set(new_o):
        raise RegisterError("校验失败：新增的对象与预期不符")
    if {k: v for k, v in old_root.items() if k != "objects"} != {k: v for k, v in new_root.items() if k != "objects"}:
        raise RegisterError("校验失败：顶层字段被改动")
    for oid, obj in old_o.items():
        want = obj
        if oid == plan.group_id and plan.new_ref:
            want = PDict(obj)
            want["children"] = list(obj["children"]) + [plan.ref_id]
        elif oid == plan.phase_id and plan.new_build:
            want = PDict(obj)
            want["files"] = list(obj["files"]) + [plan.build_id]
        if new_o[oid] != want:
            raise RegisterError("校验失败：对象 %s 被意外改动" % oid)
    if plan.new_ref and new_o[plan.ref_id] != {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift",
                                               "path": plan.name, "sourceTree": "<group>"}:
        raise RegisterError("校验失败：新文件引用的内容不对")
    if plan.new_build and new_o[plan.build_id] != {"isa": "PBXBuildFile", "fileRef": plan.ref_id}:
        raise RegisterError("校验失败：新构建项的内容不对")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def normalize_rel(file_arg, root):
    p = file_arg
    if os.path.isabs(p):
        # 两边都取真实路径再相对化（macOS 的 /tmp 是 /private/tmp 的符号链接）；
        # 只解析父目录，文件本身即使是符号链接也按它在工程里的位置登记，不跟随到链接目标
        parent, base = os.path.split(p)
        p = os.path.relpath(os.path.join(os.path.realpath(parent), base), os.path.realpath(str(root)))
    rel = os.path.normpath(p).replace(os.sep, "/")
    if rel.startswith("../") or rel == ".." or rel.startswith("/"):
        raise RegisterError("文件不在仓库根 %s 之内：%s" % (root, file_arg))
    return rel


def run(args):
    project = Path(args.project) if args.project else DEFAULT_PROJECT
    if project.is_dir():
        project = project / "project.pbxproj"
    if not project.is_file():
        raise RegisterError("找不到 pbxproj：%s" % project)
    project = project.resolve()  # 若它是符号链接，原子替换要落在链接目标上，而不是把链接换成普通文件
    root = Path(args.root) if args.root else project.parent.parent

    rel = normalize_rel(args.file, root)
    name = rel.rsplit("/", 1)[-1]
    if not name.endswith(".swift") or name == ".swift":
        raise RegisterError("只支持登记 .swift 源文件：%s" % rel)
    if "*/" in name or any(ord(c) < 32 for c in name):
        raise RegisterError("文件名含有不能写进 pbxproj 注释的字符：%r" % name)
    if not (root / rel).is_file():
        raise RegisterError("文件不存在：%s（相对路径按根目录 %s 解析，不是当前目录）" % (rel, root))
    # macOS 默认大小写不敏感：real.swift 能「找到」Real.swift，但登记进工程的名字必须与磁盘上的一致
    try:
        siblings = os.listdir(str((root / rel).parent))
    except OSError:
        siblings = None
    if siblings is not None:
        nfc = lambda s: unicodedata.normalize("NFC", s)
        if nfc(name) not in {nfc(n) for n in siblings}:
            actual = next((n for n in siblings if nfc(n).casefold() == nfc(name).casefold()), "?")
            raise RegisterError("文件名与磁盘上的大小写不一致：%s（磁盘上是 %s），请按磁盘上的名字重新输入" % (name, actual))

    raw = project.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise RegisterError("pbxproj 不是 UTF-8 编码")
    if "\r" in text:
        raise RegisterError("pbxproj 含有 CR 换行，不支持")

    # 写入前校验原文件：已经损坏的工程不碰
    try:
        old_root = validate_text(text)
        plutil_lint(project)
    except RegisterError as e:
        raise RegisterError("写入前校验未通过，未做任何改动：%s" % e)

    plan = make_plan(text, old_root, rel, args.target)
    where = "目标 %s，组 %s [%s]" % (plan.target_name, plan.group_path or "(根)", plan.group_id)

    if not plan.edits:
        print("已登记：%s（%s），未改动。" % (rel, where))
        return 0

    new_text = apply_edits(text, plan.edits)

    # 写入前校验新内容（内存里）
    try:
        new_root = validate_text(new_text)
        verify_result(old_root, new_root, plan)
    except RegisterError as e:
        raise RegisterError("新内容校验未通过，未写入：%s" % e)

    if args.dry_run:
        # plutil 只认文件：dry-run 把新内容放到系统临时目录里校验，完事即删，不碰工程
        fd, tmp = tempfile.mkstemp(prefix="pbxproj-dry-", suffix=".pbxproj")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(new_text.encode("utf-8"))
            linted = plutil_lint(tmp)
        except RegisterError as e:
            raise RegisterError("新内容校验未通过，未写入：%s" % e)
        finally:
            os.unlink(tmp)
        print("[dry-run] 将登记 %s → %s" % (rel, where))
        for label, line in plan.lines:
            print("  + %s:\n      %s" % (label, line.strip()))
        print("校验通过（%s），dry-run 未写入任何文件。" % ("括号平衡 + 内置解析 + plutil -lint" if linted
                                                        else "括号平衡 + 内置解析；本机没有 plutil，已跳过 plutil -lint"))
        return 0

    # 先写同目录临时文件，plutil 校验通过后原子替换；任何失败都清理临时文件、原文件保持不变
    try:
        fd, tmp = tempfile.mkstemp(prefix=".project.pbxproj.", suffix=".tmp", dir=str(project.parent))
    except OSError as e:
        raise RegisterError("无法在 %s 里创建临时文件，pbxproj 未被改动：%s" % (project.parent, e))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(new_text.encode("utf-8"))
        os.chmod(tmp, stat.S_IMODE(os.stat(str(project)).st_mode))
        try:
            linted = plutil_lint(tmp)
        except RegisterError as e:
            raise RegisterError("写入后校验未通过，未落盘：%s" % e)
        os.replace(tmp, str(project))
        tmp = None
    except OSError as e:
        raise RegisterError("写入失败，pbxproj 未被改动：%s" % e)
    finally:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)

    print("已登记：%s → %s" % (rel, where))
    for label, line in plan.lines:
        print("  + %s" % label)
    if not linted:
        print("提示：本机没有 plutil，已跳过 plutil -lint（括号平衡与内置解析校验已通过）。")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="pbxproj-add-file.py",
        description="把一个新的 Swift 源文件登记进 pbxproj（文件引用、构建项、所属组、编译阶段四处）。")
    ap.add_argument("file", help="相对仓库根的 .swift 文件路径，例如 FlowVision/Sources/Common/Foo.swift")
    ap.add_argument("--target", required=True, choices=sorted(TARGETS),
                    help="app = FlowVision 应用目标；tests = PixyTests 目标")
    ap.add_argument("--project", help="pbxproj 路径或 .xcodeproj 目录，默认是本仓库的真实工程")
    ap.add_argument("--root", help="检查文件存在用的仓库根，默认是 .xcodeproj 的上一级")
    ap.add_argument("--dry-run", action="store_true", help="只打印并校验，不写文件")
    args = ap.parse_args(argv)
    try:
        return run(args)
    except RegisterError as e:
        print("错误：%s" % e, file=sys.stderr)
        return 1
    except OSError as e:
        print("错误：文件读写失败：%s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
