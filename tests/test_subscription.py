#!/usr/bin/env python3
"""Offline sub.sh generation fixtures; PHP transaction behavior is in test_writes.php."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'src/usr/local/etc/mihomo/sub/sub.sh'
OUTPUT_DIR = None
TEMPLATE = '''allow-lan: false
mode: rule
log-level: silent
tun:
  enable: false
dns:
  enable: false
# __MIHOMO_PROXIES__
proxy-groups:
  - name: fixture-select
    type: select
    proxies:
# __MIHOMO_NODE_NAMES__
  - name: fixture-fallback
    type: select
    proxies:
# __MIHOMO_NODE_NAMES__
rules:
  - MATCH,fixture-select
'''

# Only ordinary plain/quoted names: YAML scalar escape fidelity is separate work.
LAYOUTS = {
    'block': ('  - name: block-first\n    type: direct\n'
              '  - type: direct\n    name: block-last\n',
              ['block-first', 'block-last']),
    'flow': ('  - {name: flow-first, type: direct}\n'
             '  - {type: direct, name: flow-last}\n'
             '  - {type: direct, name: "香港, primary", udp: true}\n',
             ['flow-first', 'flow-last', '香港, primary']),
    'mixed': ("  - { name: 'quoted, node', type: direct }\n"
              '  - type: direct\n    name: block node\n'
              '  - { type: direct, name : spaced }\n',
              ['quoted, node', 'block node', 'spaced']),
    'server-order': ('  - {name: before-server, server: example.invalid, type: socks5, port: 443}\n'
                     '  - {server: example.invalid, name: after-server, type: socks5, port: 443}\n',
                     ['before-server', 'after-server']),
    'nested-block': ('  - type: direct\n    metadata:\n      name: not-a-node\n'
                     '      items:\n        - name: also-not-a-node\n'
                     '    name: real-node\n', ['real-node']),
    'nested-flow': ('  - {metadata: {name: decoy, items: [a, b]}, type: direct, name: actual}\n'
                    '  - {type: direct, metadata: {name: decoy}, name: "braces {,} node"}\n',
                    ['actual', 'braces {,} node']),
    'indentless': ('- name: zero-indent\n  type: direct\n'
                   '- {type: direct, name: zero-flow}\n', ['zero-indent', 'zero-flow']),
    'comments': ('  # Nodes follow\n  - name: first\n    type: direct\n'
                 '\n# Between nodes\n  - {type: direct, name: second}\n', ['first', 'second']),
    'plain-quotes': ("  - {type: direct, name: user's node}\n"
                     '  - {type: direct, name: a "quoted" node}\n',
                     ["user's node", 'a "quoted" node']),
    'deduplicated': ('  - name: repeated\n    type: direct\n'
                     '  - name: repeated\n    type: direct\n', ['repeated']),
}


class SubscriptionFixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mihomo-subscription-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sub = self.root / 'sub'
        self.sub.mkdir()
        shutil.copyfile(SCRIPT, self.sub / 'sub.sh')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub('curl', '''
if [ "${FIXTURE_FALLBACK:-0}" = 1 ] && [ ! -f "$MIHOMO_DIR/attempt" ]; then
    touch "$MIHOMO_DIR/attempt"
    exit 1
fi
while [ "$#" -gt 1 ]; do
    if [ "$1" = -o ]; then shift; target=$1; fi
    shift
done
[ "$1" = "$FIXTURE_EXPECTED_URL" ] || exit 1
cp "$FIXTURE_PAYLOAD" "$target"
''')
        self.stub('jq', 'cat >/dev/null\nprintf %s fixture-encoded-url\n')
        self.stub('openssl', 'printf %s fixture-generated-secret\n')
        # Capture only the generator output. Never invoke the actual installer,
        # validator or service from this portable suite.
        self.stub('php', '''
shift
case "$1" in
    snapshot) printf '{}\\n' ;;
    install) cp "$2" "$3"; touch "$MIHOMO_DIR/installed" ;;
    *) exit 1 ;;
esac
''')
        # Do not inherit appliance settings or credentials from the caller.
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(('MIHOMO_', 'mihomo_', 'FIXTURE_'))
                    and key != 'INSECURE_TLS'}
        self.env.update({
            'PATH': str(self.bin) + os.pathsep + os.environ.get('PATH', ''),
            'MIHOMO_DIR': str(self.root),
            'MIHOMO_FORMAL_CONFIG': str(self.root / 'config.yaml'),
            'MIHOMO_LOCK_DIR': str(self.root / 'subscription.lock'),
            'MIHOMO_PHP_BIN': str(self.bin / 'php'),
            'MIHOMO_WRITE_HELPER': 'unused-fixture-helper',
            'MIHOMO_CONVERTER_URL': 'direct',
            'MIHOMO_SERVICE_CMD': 'false',
            'mihomo_URL': 'https://example.invalid/subscription',
            'mihomo_secret': 'example-change-me',
            'FIXTURE_PAYLOAD': str(self.root / 'payload.yaml'),
            'FIXTURE_EXPECTED_URL': 'https://example.invalid/subscription',
        })

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\nset -eu\n' + body, encoding='utf-8')
        path.chmod(0o700)

    def generate(self, payload, template=TEMPLATE, succeeds=True):
        (self.sub / 'template_config.yaml').write_text(template, encoding='utf-8')
        (self.root / 'payload.yaml').write_text(payload, encoding='utf-8')
        config = self.root / 'config.yaml'
        config.write_text('original fixture\n', encoding='utf-8')
        installed = self.root / 'installed'
        installed.unlink(missing_ok=True)
        result = subprocess.run(['sh', str(self.sub / 'sub.sh')], env=self.env,
                                capture_output=True, timeout=20)
        # Never print captured logs: this also keeps credentials out of failures.
        self.assertEqual(result.returncode == 0, succeeds, f'exit status {result.returncode}')
        self.assertEqual(installed.exists(), succeeds)
        self.assertEqual(list(self.root.glob('.mihomo-sub.*')), [])
        self.assertFalse((self.root / 'subscription.lock').exists())
        generated = config.read_text(encoding='utf-8')
        if not succeeds:
            self.assertEqual(generated, 'original fixture\n')
        return generated

    def assert_names(self, generated, expected):
        groups = generated.split('proxy-groups:\n', 1)[1].split('rules:\n', 1)[0]
        memberships = re.findall(r'    proxies:\n((?:      - .+\n)*)', groups)
        self.assertEqual(len(memberships), 2)
        for membership in memberships:
            names = [json.loads(value) for value in re.findall(r'^      - (.+)$', membership, re.M)]
            self.assertEqual(names, expected)
        self.assertNotIn('__MIHOMO_', generated)

    def test_layouts(self):
        for label, (nodes, expected) in LAYOUTS.items():
            with self.subTest(layout=label):
                payload = ('mode: global\nproxies:\n' + nodes
                           + 'proxy-groups:\n  - name: provider-group\n'
                           + '    type: select\n    proxies: [DIRECT]\n'
                           + 'rules:\n  - MATCH,REJECT\n')
                generated = self.generate(payload)
                self.assert_names(generated, expected)
                self.assertIn('proxies:\n' + nodes + 'proxy-groups:\n', generated)
                self.assertNotIn('provider-group', generated)
                self.assertNotIn('MATCH,REJECT', generated)
                self.assertNotIn('mode: global', generated)
                if OUTPUT_DIR is not None and label in ('block', 'flow', 'mixed'):
                    (OUTPUT_DIR / f'{label}.yaml').write_text(generated, encoding='utf-8')

    def test_converter_and_download_fallback(self):
        self.env['MIHOMO_CONVERTER_URL'] = 'https://converter.example.invalid/sub'
        self.env['FIXTURE_EXPECTED_URL'] = ('https://converter.example.invalid/sub'
                                           '?target=clash&url=fixture-encoded-url&udp=true&clash.dns=true&list=false')
        self.env['FIXTURE_FALLBACK'] = '1'
        generated = self.generate('proxies:\n' + LAYOUTS['flow'][0])
        self.assert_names(generated, LAYOUTS['flow'][1])
        self.assertTrue((self.root / 'attempt').exists())

    def test_rejected_inputs(self):
        for label, payload in {
            'empty': '', 'html': '<html>fixture</html>\n',
            'missing-proxies': 'rules:\n  - MATCH,DIRECT\n',
            'empty-proxies': 'proxies: []\n',
            'missing-name': 'proxies:\n  - {type: direct}\n',
        }.items():
            with self.subTest(input=label):
                self.generate(payload, succeeds=False)
        self.generate('proxies:\n' + LAYOUTS['block'][0],
                      template=TEMPLATE.replace('# __MIHOMO_NODE_NAMES__', ''), succeeds=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path,
                        help='save representative generated YAML for FreeBSD real-core checks')
    args = parser.parse_args()
    OUTPUT_DIR = args.output_dir
    if OUTPUT_DIR is not None:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    unittest.main(argv=[__file__], verbosity=2)
