#!/usr/bin/env python3
"""查看 tests/config.yaml 的分组/规则结构（不打印任何凭据）"""
import io
import re

t = io.open('tests/config.yaml', encoding='utf-8').read()

m = re.search(r'^proxy-groups:\s*$(.*?)(?=^[a-z][a-z0-9-]*:|\Z)', t, re.S | re.M)
seg = m.group(1) if m else ''
names = re.findall(r"name:\s*'([^']+)'", seg) + re.findall(r'name:\s*"([^"]+)"', seg) + re.findall(r'name:\s*([^,}\n]+)', seg)
print('proxy-groups (%d):' % len(names))
for n in names:
    print('   -', n.strip())

m2 = re.search(r'^rules:\s*$(.*)$', t, re.S | re.M)
rules = [l.strip() for l in (m2.group(1) if m2 else '').splitlines() if l.strip().startswith('-')]
print('\nrules 条数:', len(rules))
for r in rules[:6]:
    print('   ', r)
print('    ...')
for r in rules[-4:]:
    print('   ', r)

print('\n顶层键:', re.findall(r'^([a-z][a-z0-9-]*):', t, re.M))
print('tun 段:', bool(re.search(r'^tun:', t, re.M)))
print('external-controller:', re.findall(r'^external-controller:.*', t, re.M))
print('端口:', re.findall(r'^(?:mixed-port|socks-port|port|redir-port|tproxy-port):.*', t, re.M))
print('dns.listen:', re.findall(r'^\s+listen:.*', t, re.M))
print('allow-lan:', re.findall(r'^allow-lan:.*', t, re.M))
print('bind-address:', re.findall(r'^bind-address:.*', t, re.M))
