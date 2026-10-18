#!/usr/bin/env python3
"""
os-mihomo —— 待译字符串提取器

从插件源码里搜集所有会进 gettext 的英文串：
  · PHP : gettext('...') / gettext("...")
  · Volt: lang._('...')

用法:
  python tools/extract_strings.py            # 打印所有字符串（去重排序）
  python tools/extract_strings.py --json     # 输出 JSON（供后续比对/生成 .po）
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = [ROOT / 'src/usr/local/opnsense', ROOT / 'src/usr/local/www']
SUFFIXES = {'.php', '.volt'}

# gettext('多行也可以') / gettext("...") / lang._('...')
PATTERNS = [
    re.compile(r"gettext\(\s*'((?:[^'\\]|\\.)*)'\s*\)", re.S),
    re.compile(r'gettext\(\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S),
    re.compile(r"lang\._\(\s*'((?:[^'\\]|\\.)*)'\s*\)", re.S),
    re.compile(r'lang\._\(\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S),
]

# 表单/模型 XML 里会被框架统一 gettext() 的节点
#   · ControllerBase::parseFormNode() 对 label / help / hint 调 gettext()
#   · 模型的 ValidationMessage 由 BaseField 输出时翻译
XML_NODES = ('label', 'help', 'hint', 'ValidationMessage', 'OptionValues')
XML_TAGS = re.compile(
    r'<(' + '|'.join(XML_NODES) + r')>(.*?)</\1>', re.S
)

# 这些是「拼接用的片段」，不单独翻译（保留在结果里但标注）
UNESCAPE = {"\\'": "'", '\\"': '"', '\\n': '\n', '\\\\': '\\'}


def unescape(text: str) -> str:
    for src, dst in UNESCAPE.items():
        text = text.replace(src, dst)
    return text


def collect() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}

    def add(value: str, rel: str) -> None:
        value = value.strip()
        if not value:
            return
        found.setdefault(value, [])
        if rel not in found[value]:
            found[value].append(rel)

    for base in SCAN_DIRS:
        if not base.exists():
            continue
        for path in sorted(base.rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(ROOT).as_posix()

            if path.suffix in SUFFIXES:
                text = path.read_text(encoding='utf-8', errors='replace')
                # 去掉注释，减少误报（/* */ 与 // 与 {# #}）
                text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
                text = re.sub(r'\{#.*?#\}', '', text, flags=re.S)
                text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
                for pattern in PATTERNS:
                    for match in pattern.finditer(text):
                        add(unescape(match.group(1)), rel)

            elif path.suffix == '.xml':
                # 表单定义与模型定义：label / help / hint / ValidationMessage / OptionValues
                text = path.read_text(encoding='utf-8', errors='replace')
                for match in XML_TAGS.finditer(text):
                    # 只取第一行有内容的；长帮助文本把换行折叠成空格（与 gettext 原文一致）
                    value = re.sub(r'\s+', ' ', match.group(2)).strip()
                    if match.group(1) == 'OptionValues':
                        # 选项值是一组 <key>Label</key>，只收集标签
                        for key, label in re.findall(r'<([A-Za-z0-9_-]+)>(.*?)</\1>', match.group(2), re.S):
                            add(re.sub(r'\s+', ' ', label).strip(), rel)
                        continue
                    add(value, rel)

    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--out', default='', help='把 JSON 写入文件（避免 shell 重定向带来的编码问题）')
    args = parser.parse_args()

    strings = collect()
    if args.out:
        Path(args.out).write_text(
            json.dumps({k: v for k, v in sorted(strings.items())}, ensure_ascii=False, indent=1),
            encoding='utf-8'
        )
        print(f'written {len(strings)} strings -> {args.out}')
        return 0
    if args.json:
        print(json.dumps({k: v for k, v in sorted(strings.items())}, ensure_ascii=False, indent=1))
    else:
        print(f'# 共 {len(strings)} 条唯一字符串\n')
        for value in sorted(strings):
            print(f'--- {value!r}')
            for src in strings[value]:
                print(f'      {src}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
