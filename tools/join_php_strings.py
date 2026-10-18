#!/usr/bin/env python3
"""
把 PHP 源码里跨行的字符串拼接（'a ' .\n 'b'）合并成单一字面量。

目的：gettext() 只能提取「一个字面量」的字符串；跨行拼接会让这些长句
无法进入翻译词库（表现为页面上长句仍是英文）。

只用在本仓库的源文件上，且只匹配 `' .` 紧跟换行再跟 `'` 的形态。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [ROOT / 'src/usr/local/opnsense']

PATTERN = re.compile(r"'[ \t]*(?:\.[ \t]*)?\r?\n[ \t]*(?:\.[ \t]*)?'")
REPLACEMENT = ''          # 去掉「收尾引号 + ' .' + 换行 + 起始引号」，把两个字面量并成一个
                          # 兼容两种写法：
                          #   'part one ' .\n   'part two'      （点在前一行末尾）
                          #   'part one '\n     . 'part two'      （点在下一行开头）


def main() -> int:
    write = '--write' in sys.argv
    total = 0
    for base in TARGETS:
        for path in sorted(base.rglob('*.php')):
            text = path.read_text(encoding='utf-8')
            new, count = PATTERN.subn(REPLACEMENT, text)
            if count:
                total += count
                print(f'{"FIXED" if write else "WOULD FIX"}: {path.relative_to(ROOT).as_posix()}  ({count} 处拼接)')
                if write:
                    path.write_text(new, encoding='utf-8', newline='\n')
    print(f'\n共 {total} 处')
    if not write and total:
        print('加 --write 才会落盘')
    return 0


if __name__ == '__main__':
    sys.exit(main())
