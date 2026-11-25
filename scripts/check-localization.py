#!/usr/bin/env python3
"""本地化 key 检查：防止「标识符式 key 缺语言又没有英文回退」再次让界面露出原始 key。

背景：xcstrings 编译后，某个 key 在某语言包里缺失时 NSLocalizedString 会直接返回 key。
英文原句式的 key（如 "Open"）本身就是回退，没问题；标识符式的 key
（如 "sidebar-favorites"）必须二选一：xcstrings 里语言齐全，或者调用处带 `value:` 英文回退。

规则（只检查标识符式 key，即 ^[a-z0-9]+(-[a-z0-9]+)*$）：
  1. Swift 源码里用字面量引用的 key 必须存在于 Localizable.xcstrings；
  2. 该 key 要么覆盖 xcstrings 里出现过的全部语言，要么调用处带 `value:`；
  3. （警告）xcstrings 里语言不齐、且 Swift 里没有任何字面量引用的 key。

局限：key 来自变量（如 specialEntry(key:) 里转手的 key）无法静态识别，需要在转手处自带回退。

用法：scripts/check-localization.py [仓库根目录]    有错误时退出码为 1。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
XCSTRINGS = ROOT / "FlowVision/Resources/Localizable.xcstrings"
SOURCES = ROOT / "FlowVision/Sources"

IDENTIFIER_KEY = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')


def call_text(source, start):
    """start 指向 NSLocalizedString( 之后的第一个字符，返回到配对右括号为止的参数文本。"""
    depth, i, in_string = 1, start, False
    while i < len(source):
        c = source[i]
        if in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return source[start:i]
        i += 1
    return None


def collect_calls():
    """返回 {key: [(文件, 行号, 是否带 value:)]}，只收集第一个参数是字符串字面量的调用。"""
    found = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        for m in re.finditer(r"NSLocalizedString\(", source):
            args = call_text(source, m.end())
            if args is None:
                continue
            first = re.match(r'\s*"((?:[^"\\]|\\.)*)"', args)
            if not first:
                continue
            has_value = re.search(r"\bvalue\s*:", STRING_LITERAL.sub('""', args)) is not None
            line = source.count("\n", 0, m.start()) + 1
            found.setdefault(first.group(1), []).append((path.relative_to(ROOT), line, has_value))
    return found


def main():
    strings = json.loads(XCSTRINGS.read_text(encoding="utf-8"))["strings"]
    languages = set()
    for entry in strings.values():
        languages |= set(entry.get("localizations", {}))

    def complete(entry):
        return entry.get("shouldTranslate") is False or languages <= set(entry.get("localizations", {}))

    calls = collect_calls()
    errors, warnings = [], []

    for key, uses in sorted(calls.items()):
        if not IDENTIFIER_KEY.match(key):
            continue
        entry = strings.get(key)
        for path, line, has_value in uses:
            if entry is None:
                errors.append(f"{path}:{line}  {key}  不在 Localizable.xcstrings 里")
            elif not complete(entry) and not has_value:
                missing = ", ".join(sorted(languages - set(entry.get("localizations", {}))))
                errors.append(f"{path}:{line}  {key}  缺少 {missing}，且调用处没有 value: 英文回退")

    for key, entry in sorted(strings.items()):
        if IDENTIFIER_KEY.match(key) and not complete(entry) and key not in calls:
            warnings.append(f"{key}  语言不齐且源码里没有字面量引用（可能是死 key，或经变量引用）")

    for w in warnings:
        print(f"警告：{w}")
    for e in errors:
        print(f"错误：{e}", file=sys.stderr)
    if errors:
        print(f"本地化检查失败：{len(errors)} 处。", file=sys.stderr)
        return 1
    print(f"本地化检查通过：{len(calls)} 个字面量 key，xcstrings 共 {len(languages)} 种语言。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
