#!/usr/bin/env python3
"""Reject accidental publication of local files or operational credentials."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FILES = {'.gitattributes', '.gitignore', '.github/workflows/ci.yml', '.github/dependabot.yml',
         'README.md', 'README.US.md', 'Makefile', 'build.sh', 'docs/ci-cd.md',
         'scripts/ci_build.sh', 'scripts/make_repo.sh', 'scripts/deploy.sh', 'scripts/rollback.sh',
         'tests/test_patch.php', 'tests/test_ui.js', 'tests/test_runtime.php', 'tools/build_locales.py',
         'tools/extract_strings.py', 'tools/mo_editor.py', 'tools/validate.py',
         'tools/check_publication.py'}
ROOTS = ('src/', 'locales/', 'packaging/freebsd/')

# These exact images were visually reviewed after local privacy blurring.
# Replacements need a new visual review before updating their hashes.
# A text scan cannot establish whether screenshot pixels contain private data.
SCREENSHOTS = {
    'docs/assets/overview.png': 'ddd4ef2cd6bff07a0b1f37b737d85e8e4e9cf53a82a10292cf22ac601a183d33',
    'docs/assets/routing.png': 'af58b1b61c8578ddab955e176034d50d3bcb0363a6fdfbe5bab4e854afea2eaf',
    'docs/assets/configuration-comparison.png': 'bccfa3ae5121377c488108ecfbd3b8365de396157de1de6c20e8282f151e49ea',
}

def check():
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    ignored = subprocess.check_output(['git', 'ls-files', '-ci', '--exclude-standard'], cwd=ROOT)
    assert not ignored.strip(), 'Ignored local files must not be tracked'
    for relative, digest in SCREENSHOTS.items():
        data = (ROOT / relative).read_bytes()
        assert data.startswith(b'\x89PNG\r\n\x1a\n'), f'Expected PNG screenshot: {relative}'
        assert hashlib.sha256(data).hexdigest() == digest, f'Screenshot needs privacy review: {relative}'
    for relative in filter(None, tracked):
        assert relative in FILES or relative in SCREENSHOTS or relative.startswith(ROOTS), f'Unexpected public file: {relative}'
        path = ROOT / relative
        if relative in SCREENSHOTS:
            continue
        if path.suffix in ('.xz', '.dat', '.mo'):
            continue
        content = path.read_text(encoding='utf-8')
        patterns = [r'gh[pousr]_[A-Za-z0-9]{30,}', r'github_pat_[A-Za-z0-9_]{30,}',
                    r'-----BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY-----',
                    r'https?://[^\s/:@]+:[^\s/@]{5,}@',
                    r'[A-Za-z]:[\\/]+Users[\\/]+[^\s\\/]+',
                    r'/(?:home|Users)/[A-Za-z0-9_.-]+/']
        for pattern in patterns:
            assert not re.search(pattern, content), f'Sensitive content in {relative}'
        private = re.findall(r'\b(?:192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)(?:/\d+)?', content)
        assert all(value in {'10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'} for value in private), f'Private host address in {relative}'
    sources = json.loads((ROOT / 'packaging/freebsd/geodata-source.json').read_text())
    for item in sources:
        assert hashlib.sha256((ROOT / item['file']).read_bytes()).hexdigest() == item['sha256'], 'Geodata differs from pinned public asset'
    binary = json.loads((ROOT / 'packaging/freebsd/binary-source.json').read_text())
    archive = ROOT / 'src/usr/local/bin/clash-meta-freebsd-amd64.xz'
    if archive.exists():
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == binary['sha256'], 'Core archive differs from pinned public asset'
    print(f'Publication check passed: {len(list(filter(None, tracked)))} files; third-party assets verified.')

if __name__ == '__main__':
    check()
