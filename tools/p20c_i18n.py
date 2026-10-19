#!/usr/bin/env python3
"""按前缀删掉废弃词条（键 + 紧随的译文行）"""
import io
import re

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

patterns = [
    r"^\s*'Device name, must match the firewall rules.*\n(?:\s+'.*\n)?",
    r"^\s*'gvisor is recommended on FreeBSD\..*\n",
]
n = 0
for pat in patterns:
    t2, cnt = re.subn(pat, '', t, count=1, flags=re.M)
    if cnt:
        t = t2
        n += cnt
        print('已删:', pat[:44])
    else:
        print('!! 没找到:', pat[:44])
print('共删', n)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
