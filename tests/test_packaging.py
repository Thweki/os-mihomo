#!/usr/bin/env python3
"""Exercise build.sh with disposable sources and no FreeBSD or network access."""
import hashlib
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

# Keep real tar behavior (including a readable partial archive on failure).
# Only the FreeBSD pkg/sha256 commands and download boundary are substituted.
SHIM = '''#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import subprocess
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
if tool == 'tar':
    mode = 'create' if '-cf' in args else 'extract'
    counter = Path(os.environ['FIXTURE_STATE']) / mode
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    fail = os.environ.get('FAIL_TAR') == f'{mode}-{count}'
    if fail and mode == 'create':
        # tar can finish a valid archive despite failing to read source files.
        args = args[:-1] + ['-T', os.devnull]
    result = subprocess.run([os.environ['REAL_TAR'], *args])
    sys.exit(73 if fail else result.returncode)
if tool == 'sha256':
    print(hashlib.sha256(Path(args[-1]).read_bytes()).hexdigest())
    sys.exit(0)
if tool == 'pkg':
    if args == ['config', 'ABI']:
        print('FreeBSD:15:amd64')
        sys.exit(0)
    if args[:2] == ['info', '-F']:
        sys.exit(0)
sys.exit('Unexpected fixture command: ' + tool)
'''


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        shutil.copy2(ROOT / 'build.sh', self.source / 'build.sh')
        shutil.copytree(ROOT / 'src', self.source / 'src',
                        ignore=shutil.ignore_patterns('*.xz', '*.dat'))
        shutil.copytree(ROOT / 'packaging', self.source / 'packaging')
        (self.source / 'tools').mkdir()
        shutil.copy2(ROOT / 'tools/reproducible_archive.py',
                     self.source / 'tools/reproducible_archive.py')
        asset = lzma.compress(b'fixture core; never executed\n')
        (self.source / 'src/usr/local/bin/clash-meta-freebsd-amd64.xz').write_bytes(asset)
        commands = self.root / 'bin'
        commands.mkdir()
        for name in ('tar', 'pkg', 'sha256', 'curl', 'fetch'):
            shim = commands / name
            shim.write_text(SHIM, encoding='utf-8')
            shim.chmod(0o755)
        self.env = {
            'PATH': str(commands) + os.pathsep + os.environ['PATH'],
            'REAL_TAR': shutil.which('tar'),
            'FIXTURE_STATE': str(self.root),
            'SOURCE_DATE_EPOCH': '1234567890',
            'MIHOMO_SHA256': hashlib.sha256(asset).hexdigest(),
            'PYTHONDONTWRITEBYTECODE': '1',
        }

    def build(self, failure=''):
        return subprocess.run(['sh', str(self.source / 'build.sh')],
                              cwd=self.source, env={**self.env, 'FAIL_TAR': failure},
                              text=True, capture_output=True, timeout=30)

    def test_successful_copy_preserves_payload_and_samples(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with tarfile.open(self.source / 'dist/os-mihomo.pkg') as package:
            self.assertEqual(package.extractfile('/usr/local/bin/mihomo').read(),
                             b'fixture core; never executed\n')
            sample = package.getmember('/usr/local/etc/mihomo/config.yaml.sample')
            self.assertEqual(sample.mode, 0o600)
            self.assertNotIn('/usr/local/etc/mihomo/config.yaml', package.getnames())
        self.assertEqual((self.root / 'create').read_text(), '2')
        self.assertEqual((self.root / 'extract').read_text(), '2')

    def test_copy_failures_abort_both_build_stages(self):
        for failure in ('create-1', 'create-2', 'extract-1', 'extract-2'):
            with self.subTest(failure=failure):
                for mode in ('create', 'extract'):
                    (self.root / mode).unlink(missing_ok=True)
                (self.source / 'dist/os-mihomo.pkg').unlink(missing_ok=True)
                result = self.build(failure)
                self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
                self.assertFalse((self.source / 'dist/os-mihomo.pkg').exists())


if __name__ == '__main__':
    unittest.main()
