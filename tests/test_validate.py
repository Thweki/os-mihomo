#!/usr/bin/env python3
"""Portable validator fixtures: temporary files only; scripts are never run."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
from validate import check_correctness, check_shell_syntax, shell_files


class ValidationTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='mihomo-validate-')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def test_shell_discovery_and_parse_only(self):
        # No executable bits are needed; parsing must never execute any fixture.
        script = '#!/bin/sh\nexit 99\n'
        expected = {
            'build.sh', 'scripts/check.sh', 'tests/check.sh',
            'src/usr/bin/mihomo_sub', 'src/usr/local/etc/rc.d/mihomo',
            'src/etc/rc.conf.d/mihomo', 'src/usr/local/etc/mihomo/sub/env',
            'packaging/freebsd/+POST_INSTALL', 'packaging/freebsd/+PRE_DEINSTALL',
            'packaging/freebsd/+POST_DEINSTALL',
        }
        for relative in expected:
            self.write(relative, script if relative not in {
                'src/etc/rc.conf.d/mihomo', 'src/usr/local/etc/mihomo/sub/env'
            } else "example='value'\n")
        expected.add('src/usr/bin/env-shell')
        self.write('src/usr/bin/env-shell', '#!/usr/bin/env sh\nexit 99\n')
        self.write('src/data.txt', 'not a shell script\n')
        self.write('src/other', '#!/usr/bin/env python3\npass\n')
        self.write('work/ignored.sh', 'if then\n')
        self.assertEqual({p.relative_to(self.root).as_posix() for p in shell_files(self.root)}, expected)
        check_shell_syntax(self.root)

    def test_extensionless_syntax_error_rejected(self):
        self.write('src/usr/bin/mihomo_sub', '#!/bin/sh\nif then\n')
        with self.assertRaises(subprocess.CalledProcessError):
            check_shell_syntax(self.root)

    @unittest.skipUnless(shutil.which('shellcheck'), 'ShellCheck unavailable')
    def test_shell_correctness_error_rejected(self):
        # This parses as a command in sh, but ShellCheck catches the bad assignment.
        self.write('src/usr/bin/mihomo_sub', '#!/bin/sh\nvalue = example\n')
        check_shell_syntax(self.root)
        with self.assertRaises(subprocess.CalledProcessError):
            check_correctness(self.root)

    @unittest.skipUnless(importlib.util.find_spec('ruff'), 'Ruff unavailable')
    def test_python_correctness_error_rejected(self):
        self.write('tools/example.py', 'print(undefined_name)\n')
        with self.assertRaises(subprocess.CalledProcessError):
            check_correctness(self.root)

    @unittest.skipUnless(shutil.which('shellcheck') and importlib.util.find_spec('ruff'),
                         'ShellCheck or Ruff unavailable')
    def test_correctness_accepts_valid_fixtures(self):
        self.write('src/usr/bin/mihomo_sub', '#!/bin/sh\nvalue=example\nprintf "%s\\n" "$value"\n')
        self.write('tools/example.py', 'print("example")\n')
        check_correctness(self.root)


if __name__ == '__main__':
    unittest.main(verbosity=2)
