#!/usr/bin/env python3
"""P21c 词条：删掉底部那句旧提示（复选框时代的产物）"""
import io
import re

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()
pat = r'''^\s*'Tick "leave alone" = this plugin never writes that item\.'.*\n(?:.*\n)?'''
t2, cnt = re.subn(pat, '', t, count=1, flags=re.M)
if cnt:
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t2)
    print('已删旧提示词条')
else:
    print('未找到；相关行：')
    for line in t.splitlines():
        if 'leave alone' in line and 'Tick' in line:
            print('   ', line.strip())
