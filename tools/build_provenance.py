#!/usr/bin/env python3
"""Record build inputs and output digests; CI attests this file with the package."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parent.parent


def command(*args):
    if args[0] == 'git':
        args = ('git', '-c', f'safe.directory={ROOT.as_posix()}', *args[1:])
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    dist = ROOT / 'dist'
    package_hash = hashlib.sha256((dist / 'os-mihomo.pkg').read_bytes()).hexdigest()
    if os.environ.get('REPRODUCIBLE_PACKAGE_SHA256') != package_hash:
        sys.exit('Run ci_build.sh to compare independent builds before recording provenance')
    info = {
        'schema': 1,
        'source': {
            'repository': 'https://github.com/Thweki/os-mihomo',
            'commit': command('git', 'rev-parse', 'HEAD'),
            'tree': command('git', 'rev-parse', 'HEAD^{tree}'),
            'dirty': bool(command('git', 'status', '--porcelain', '--untracked-files=normal')),
        },
        'source_date_epoch': int(os.environ['SOURCE_DATE_EPOCH']),
        'toolchain': {'os': platform.platform(), 'python': platform.python_version(),
                      'zlib': zlib.ZLIB_RUNTIME_VERSION, 'pkg': command('pkg', '-v')},
        'inputs': {name: json.loads((ROOT / 'packaging/freebsd' / name).read_text())
                   for name in ('binary-source.json', 'geodata-source.json')},
        'artifacts': {name: hashlib.sha256((dist / name).read_bytes()).hexdigest()
                      for name in ('os-mihomo.pkg', 'os-mihomo-repository.tar.gz')},
        'verification': {'package_double_build': True, 'package_hooks_executed': False},
    }
    if os.environ.get('CI') and info['source']['dirty']:
        sys.exit('Refusing provenance for a dirty CI source tree')
    (dist / 'build-info.json').write_text(json.dumps(info, sort_keys=True, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
