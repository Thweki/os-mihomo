#!/usr/bin/env python3
"""Exercise the actual rc.d poststart hook with fake processes; no service runs."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ReloadRecordTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='mihomo-service-')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.marker = self.root / 'last-reload'
        self.pid = self.root / 'pid'
        self.pid.write_text('41\n')
        script = (ROOT / 'src/usr/local/etc/rc.d/mihomo').read_text()
        # Load the real functions, without rc.subr or its startup dispatcher.
        script = script.replace('. /etc/rc.subr', '')
        script = script[:script.index('load_rc_config "${name}"')]
        self.script = self.root / 'service-functions.sh'
        self.script.write_text(script)

    def poststart(self, overrides=''):
        return subprocess.run(['sh', '-c', '''
. "$1"
pidfile="$2"
reloadfile="$3"
sleep() { :; }
kill() { [ "$1" = -0 ]; }
pgrep() { echo 52; }
date() { echo 1700000000; }
''' + overrides + '\nmihomo_poststart\n', 'fixture', str(self.script), str(self.pid), str(self.marker)],
            capture_output=True, text=True)

    def test_first_success_and_later_restart(self):
        self.assertEqual(self.poststart().returncode, 0)
        self.assertEqual(self.marker.read_text(), '1700000000\n')
        self.assertEqual(self.marker.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.poststart('date() { echo 1700000060; }').returncode, 0)
        self.assertEqual(self.marker.read_text(), '1700000060\n')
        self.assertEqual(list(self.root.glob('last-reload.*')), [])

    def test_failed_first_start_does_not_create_record(self):
        self.assertNotEqual(self.poststart('pgrep() { return 1; }').returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_failed_restart_keeps_last_success(self):
        for failure in ['kill() { return 1; }', 'pgrep() { return 1; }',
                        'kill() { [ "$2" = 41 ]; }']:
            with self.subTest(failure=failure):
                self.marker.write_text('1699999999\n')
                self.assertNotEqual(self.poststart(failure).returncode, 0)
                self.assertEqual(self.marker.read_text(), '1699999999\n')

    def test_missing_pidfile_is_not_success(self):
        self.pid.unlink()
        self.assertNotEqual(self.poststart().returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_recording_failure_does_not_fail_service_or_destroy_history(self):
        for failure in ['mktemp() { return 1; }', 'date() { echo partial; return 1; }',
                        'mv() { return 1; }']:
            with self.subTest(failure=failure):
                self.marker.write_text('1699999999\n')
                self.assertEqual(self.poststart(failure).returncode, 0)
                self.assertEqual(self.marker.read_text(), '1699999999\n')
                self.assertEqual(list(self.root.glob('last-reload.*')), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
