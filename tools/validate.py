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

def main():
    check()
    build(check=True)
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
    if not frontend:
        subprocess.run(['php', str(ROOT / 'tests/test_runtime.php')], check=True)
    for path in [*(ROOT / name for name in ['build.sh', 'scripts/deploy.sh', 'scripts/rollback.sh', 'scripts/ci_build.sh', 'scripts/make_repo.sh']), *sorted((ROOT / 'packaging/freebsd').glob('+*INSTALL'))]:
        shell = shutil.which('sh') or ('C:/Program Files/Git/usr/bin/sh.exe' if sys.platform == 'win32' else 'sh')
        subprocess.run([shell, '-n', str(path)], check=True)
    for path in (ROOT / 'packaging/freebsd').glob('+*INSTALL'):
        text = path.read_text(encoding='utf-8')
        assert not re.search(r'configctl|pfctl|pkill|config.xml|service mihomo|setup_unbound|rm -rf', text), path
    print(f'Validated {count} PHP files, XML, translated JavaScript, locales, UI tests and shell syntax.')

if __name__ == '__main__':
    main()
