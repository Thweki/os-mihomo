#!/usr/bin/env python3
"""清除仓库里写死的 WebGUI 口令（历史遗留的 66 个 .sh + 1 个 .ps1）。

口径：
  * 仓库 / 文档 / 脚本里绝不出现口令本身；
  * 脚本改成从环境变量 OPN_PW 或第一个参数取（tools/remote.ps1 -ScriptArgs '<口令>'），
    取不到就报错退出 —— 宁可跑不起来，也不要静默用错口令；
  * sh 里的内嵌 python 用 os.environ['OPN_PW']（heredoc 不展开 shell 变量）。

用法：
  python tools/p22_scrub_secret.py            # 看一眼会改什么
  python tools/p22_scrub_secret.py --write    # 真改
"""
import io
import os
import re
import subprocess
import sys

# 口令本身绝不写进文件：从环境变量读（SCRUB_SECRET）
SECRET = os.environ.get('SCRUB_SECRET', '')
if not SECRET:
    sys.exit('set SCRUB_SECRET=<要清除的口令> before running this tool')
BLOCK = [
    'PASS="${OPN_PW:-${1:-}}"',
    'if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs \'<口令>\'"; exit 2; fi',
    'export OPN_PW="${PASS}"',
]

ASSIGN = re.compile(r'^(\s*)(?:PASS|pass|PW|pw|PASSWORD|password)=[\'"]?' + re.escape(SECRET) + r'[\'"]?\s*$')
PY_DICT = re.compile(r'([\'"]passwordfld[\'"]\s*:\s*)[\'"]' + re.escape(SECRET) + r'[\'"]')
PYPLACE = "__import__('os').environ.get('OPN_PW', '')"


def tracked_files():
    out = subprocess.run(['git', 'ls-files'], capture_output=True, text=True, check=True)
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def scrub(path, write):
    try:
        raw = io.open(path, 'rb').read()
    except OSError:
        return None
    if SECRET.encode() not in raw:
        return None
    text = raw.decode('utf-8')
    ext = os.path.splitext(path)[1].lower()
    changed = []

    if ext == '.sh':
        # 1) sh 内嵌 python 的字典写法
        text, n = PY_DICT.subn(lambda m: m.group(1) + PYPLACE, text)
        if n:
            changed.append('python 内嵌 %d 处' % n)
        # 2) 口令赋值整行 → 删掉（统一由插入的块提供）
        lines = text.split('\n')
        kept = []
        dropped = 0
        for line in lines:
            if ASSIGN.match(line):
                dropped += 1
                continue
            kept.append(line)
        if dropped:
            changed.append('赋值行 %d 处' % dropped)
            text = '\n'.join(kept)
        # 3) 其余出现（curl 表单里的 passwordfld=...）→ $PASS
        text, n = re.subn(re.escape(SECRET), '${PASS}', text)
        if n:
            changed.append('内联 %d 处' % n)
        # 4) 顶部补 PASS 取值的块
        if 'PASS="${OPN_PW' not in text:
            lines = text.split('\n')
            lines[1:1] = [''] + BLOCK
            text = '\n'.join(lines)
            changed.append('插入取口令块')
    elif ext == '.ps1':
        text = re.sub(
            r'^(\s*\$pass\s*=\s*)[\'"]' + re.escape(SECRET) + r'[\'"]',
            r'\1$env:OPN_PW',
            text,
            flags=re.M,
        )
        if '$env:OPN_PW' in text and '缺少' not in text:
            text = text.replace(
                '$pass = $env:OPN_PW',
                '$pass = $env:OPN_PW\n'
                'if (-not $pass) { Write-Host "缺少 WebGUI 口令：$env:OPN_PW=..." -ForegroundColor Red; exit 2 }',
                1,
            )
        text, n = re.subn(re.escape(SECRET), '$env:OPN_PW', text)
        changed.append('ps1 口令引用')
    else:
        text, n = re.subn(re.escape(SECRET), '<WebGUI 口令>', text)
        changed.append('其他文件 %d 处' % n)

    if SECRET in text:
        text = text.replace(SECRET, '<WebGUI 口令>')
        changed.append('兜底替换')
    if not write:
        return changed
    io.open(path, 'w', encoding='utf-8', newline='\n').write(text.replace('\r\n', '\n'))
    return changed


def main():
    write = '--write' in sys.argv
    hits = 0
    for path in tracked_files():
        res = scrub(path, write)
        if res:
            hits += 1
            print('  %-58s %s' % (path, ', '.join(res)))
    print('=== %d 个文件%s ===' % (hits, '已清理' if write else '待清理（加 --write 生效）'))


if __name__ == '__main__':
    main()
