#!/usr/bin/env python3
"""把改动过的文本文件统一成 LF（仓库 .gitattributes 要求）"""
import io
import subprocess

out = subprocess.run(['git', 'diff', '--name-only'], capture_output=True, text=True, check=True)
fixed = 0
for path in [p.strip() for p in out.stdout.splitlines() if p.strip()]:
    try:
        raw = io.open(path, 'rb').read()
    except OSError:
        continue
    if b'\r\n' in raw:
        io.open(path, 'wb').write(raw.replace(b'\r\n', b'\n'))
        fixed += 1
        print('  LF 化:', path)
print('=== %d 个文件 ===' % fixed)
