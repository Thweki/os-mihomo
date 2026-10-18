#!/usr/bin/env python3
"""
os-mihomo 交付前净化器

FreeBSD/OPNsense 对文件字节很敏感：
  · 带 UTF-8 BOM 的 PHP 文件 → "Namespace declaration statement has to be the very first statement"
  · CRLF 的 .sh / rc.d 脚本 → 无法执行（shebang 后会带上 \r）

本脚本扫描待交付的源码树，去掉 BOM、把行尾统一为 LF，并打印改动清单。
默认 dry-run，加 --write 才真正落盘。

用法:
  python tools/sanitize.py --write
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 需要净化的交付路径（相对仓库根）
TARGETS = [
    "src",
    "packaging",
]

TEXT_SUFFIXES = {
    ".php", ".sh", ".xml", ".yaml", ".yml", ".conf", ".json", ".inc", ".volt",
}
TEXT_NAMES = {"Makefile", "+MANIFEST.in"}

BOM = b"\xef\xbb\xbf"


def is_text_file(path: Path) -> bool:
    if path.suffix in TEXT_SUFFIXES:
        return True
    if path.name in TEXT_NAMES:
        return True
    if path.name.startswith("+"):          # pkg 脚本（+POST_INSTALL 等）
        return True
    return False


def sanitize(path: Path, write: bool) -> list[str]:
    changes: list[str] = []
    data = path.read_bytes()

    if data.startswith(BOM):
        data = data[len(BOM):]
        changes.append("strip BOM")

    if b"\r\n" in data:
        data = data.replace(b"\r\n", b"\n")
        changes.append("CRLF->LF")

    if changes and write:
        path.write_bytes(data)

    return changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="真正写回文件（默认只报告）")
    args = parser.parse_args()

    touched = 0
    scanned = 0
    for target in TARGETS:
        base = ROOT / target
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or not is_text_file(path):
                continue
            scanned += 1
            changes = sanitize(path, args.write)
            if changes:
                touched += 1
                rel = path.relative_to(ROOT).as_posix()
                print(f"{'FIXED' if args.write else 'WOULD FIX'}: {rel}  [{', '.join(changes)}]")

    print(f"\n扫描 {scanned} 个文本文件，{'修复' if args.write else '待修复'} {touched} 个")
    if touched and not args.write:
        print("提示：加 --write 才会真正落盘")
    return 0


if __name__ == "__main__":
    sys.exit(main())
