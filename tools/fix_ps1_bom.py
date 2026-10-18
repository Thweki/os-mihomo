#!/usr/bin/env python3
"""
确保 tools/ 下的 PowerShell 脚本是 UTF-8 with BOM。

Windows PowerShell 5.1 在读取没有 BOM 的 .ps1 时会按系统 ANSI 代码页解码，
中文会变成乱码并可能破坏语法（引号失配）。.sh / .php 等交付到 FreeBSD 的文件
则必须保持无 BOM，因此只处理 .ps1。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOM = b"\xef\xbb\xbf"


def main() -> int:
    changed = 0
    for path in sorted((ROOT / "tools").glob("**/*.ps1")):
        data = path.read_bytes()
        if not data.startswith(BOM):
            path.write_bytes(BOM + data)
            print(f"BOM added: {path.relative_to(ROOT)}")
            changed += 1
    print(f"已处理 {changed} 个文件" if changed else "全部已带 BOM")
    return 0


if __name__ == "__main__":
    sys.exit(main())
