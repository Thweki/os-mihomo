#!/usr/bin/env python3
"""列出 .po 里仍未翻译的词条（精确文本）"""
import io
import sys

sys.path.insert(0, 'tools')
from mo_editor import read_po  # noqa: E402

po = read_po('locales/zh_CN.po')
missing = [l.rstrip('\n') for l in io.open('refs/zh_CN-missing.txt', encoding='utf-8') if l.strip()]
left = [m for m in missing if m not in po]
print('未翻译 %d 条：' % len(left))
for m in left:
    print('KEY: ' + repr(m))
