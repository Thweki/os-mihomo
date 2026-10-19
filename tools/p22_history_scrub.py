#!/usr/bin/env python3
"""git filter-branch --tree-filter 用的机械替换器。

不写死任何口令：口令从环境变量 SCRUB_SECRET 读。
把当前目录下所有文本文件里出现的口令换成中性写法（不会把脚本"修好"，只保证历史里没有明文）。

  SCRUB_SECRET=<口令> git filter-branch -f --tree-filter \
      "python C:/.../tools/p22_history_scrub.py" -- --all
"""
import io
import os
import sys

SECRET = os.environ.get('SCRUB_SECRET', '')
if not SECRET:
    sys.exit('SCRUB_SECRET not set')

REPLACEMENTS = {
    '.ps1': '$env:OPN_PW',
    '.sh': '${OPN_PW}',
    '.php': "' . getenv('OPN_PW') . '",
}
DEFAULT = '<WebGUI password>'

touched = 0
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d != '.git']
    for name in files:
        path = os.path.join(root, name)
        try:
            raw = io.open(path, 'rb').read()
        except OSError:
            continue
        if SECRET.encode() not in raw:
            continue
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        ext = os.path.splitext(name)[1].lower()
        text = text.replace(SECRET, REPLACEMENTS.get(ext, DEFAULT))
        io.open(path, 'wb').write(text.encode('utf-8'))
        touched += 1
if touched:
    print('  scrubbed %d files' % touched)
