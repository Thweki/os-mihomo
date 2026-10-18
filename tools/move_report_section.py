#!/usr/bin/env python3
"""把 §21（P15）移到附录之后，保持正文顺序与目录一致"""
import io

p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()

start = t.find('## 21. P15')
end = t.find('## 20. 附录：命令速查')
if start == -1 or end == -1 or end < start:
    raise SystemExit('定位失败: %s %s' % (start, end))

block = t[start:end]
t = t[:start] + t[end:]          # 先摘掉
t = t.rstrip('\n') + '\n\n---\n\n' + block.rstrip('\n') + '\n'
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)

import re
print('正文标题顺序（末尾部分）：')
for m in re.finditer(r'^## .*$', t, re.M):
    if m.start() > len(t) - 14000:
        print('  ', m.group(0)[:60])
