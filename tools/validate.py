#!/usr/bin/env python3
"""Portable CI checks; never connects to an appliance or runs package hooks."""
from pathlib import Path
import json
import re
import subprocess
import tempfile
import sys
import shutil
import xml.etree.ElementTree as ET
from build_locales import build
from check_publication import check

ROOT = Path(__file__).resolve().parent.parent


def shell_files(root=ROOT):
    """Find maintained POSIX scripts, including entrypoints without a suffix."""
    candidates = [root / 'build.sh']
    for directory in ['scripts', 'tests', 'src', 'packaging/freebsd']:
        candidates.extend((root / directory).rglob('*'))
    snippets = {'src/etc/rc.conf.d/mihomo', 'src/usr/local/etc/mihomo/sub/env'}
    paths = []
    for path in sorted(candidates):
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            first_line = stream.readline(128)
        if (path.suffix == '.sh' or path.relative_to(root).as_posix() in snippets
                or re.match(rb'#!\s*(?:/bin/sh|/usr/bin/env\s+sh)(?:\s|$)', first_line)):
            paths.append(path)
    return paths


def check_shell_syntax(root=ROOT):
    shell = shutil.which('sh') or ('C:/Program Files/Git/usr/bin/sh.exe' if sys.platform == 'win32' else 'sh')
    for path in shell_files(root):
        subprocess.run([shell, '-n', str(path)], check=True)


def check_correctness(root=ROOT):
    # Error-level shell diagnostics and Python runtime mistakes, not style rules.
    paths = shell_files(root)
    if paths:
        subprocess.run(['shellcheck', '--norc', '--shell=sh', '--severity=error',
                        *map(str, paths)], check=True)
    paths = sorted(path for directory in ['tools', 'tests']
                   for path in (root / directory).rglob('*.py'))
    if paths:
        subprocess.run([sys.executable, '-m', 'ruff', 'check', '--isolated', '--no-cache',
                        '--select', 'E9,F63,F7,F82', *map(str, paths)], check=True)


def main():
    check()
    build(check=True)
    check_shell_syntax()
    if '--lint' in sys.argv:
        check_correctness()
    subprocess.run([sys.executable, str(ROOT / 'tests/test_validate.py')], check=True)
    # Distributed samples must never acquire real controller/node credentials.
    examples = {'secret': 'example-change-me', 'password': 'example-password',
                'uuid': '00000000-0000-0000-0000-000000000000', 'public-key': 'A' * 43}
    for relative in ['config.yaml', 'sub/template_config.yaml']:
        sample = (ROOT / 'src/usr/local/etc/mihomo' / relative).read_text(encoding='utf-8')
        for field, value in re.findall(r'(?m)^\s*(secret|password|uuid|public-key):\s*([^\r\n]+)', sample):
            assert value.strip() == examples[field], f'{relative}: replace credentials with documented examples'
        assert 'external-controller: 127.0.0.1:9090' in sample
    count = 0
    frontend = '--frontend-only' in sys.argv
    for path in (ROOT / 'src').rglob('*'):
        if path.suffix == '.xml':
            ET.parse(path)
        if path.suffix == '.php' and not frontend:
            subprocess.run(['php', '-l', str(path)], check=True, stdout=subprocess.DEVNULL)
            count += 1
        if path.suffix == '.volt':
            text = re.sub(r'\{#.*?#\}', '', path.read_text(encoding='utf-8'), flags=re.S)
            for script in re.findall(r'<script[^>]*>(.*?)</script>', text, re.S):
                # Exercise quotes, Unicode, backslashes and line breaks in every JS translation.
                script = re.sub(r'\{\{.*?\}\}', lambda match: json.dumps("L'été \"中文\" \\ line\nnext") if 'lang._' in match.group() else 'example', script, flags=re.S)
                scratch = (ROOT / 'work' / 'checks').resolve()
                assert scratch.is_relative_to(ROOT.resolve())
                scratch.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(dir=scratch) as directory:
                    assert Path(directory).resolve().is_relative_to(scratch)
                    target = Path(directory) / 'view.js'
                    target.write_text(script, encoding='utf-8')
                    subprocess.run(['node', '--check', str(target)], check=True)
    subprocess.run(['node', str(ROOT / 'tests/test_ui.js')], check=True)
    subprocess.run([sys.executable, str(ROOT / 'tests/test_build.py')], check=True)
    if not frontend:
        subprocess.run(['php', str(ROOT / 'tests/test_runtime.php')], check=True)
        subprocess.run(['php', str(ROOT / 'tests/test_patch.php')], check=True)
        subprocess.run(['php', str(ROOT / 'tests/test_writes.php')], check=True)
        subprocess.run(['php', str(ROOT / 'tests/test_api.php')], check=True)
    for path in (ROOT / 'packaging/freebsd').glob('+*INSTALL'):
        text = path.read_text(encoding='utf-8')
        assert not re.search(r'configctl|pfctl|pkill|config.xml|service mihomo|setup_unbound|rm -rf', text), path
    print(f'Validated {count} PHP files, XML, translated JavaScript, locales, UI tests and shell syntax.')

if __name__ == '__main__':
    main()
