#!/bin/sh
# 取证：/configs 完整字段（决定"运行中"这一栏能填多少）
set -u
CFG=/usr/local/etc/mihomo/config.yaml
SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print((m.group(1).strip().strip('\"').strip(chr(39))) if m else '')")

echo "########## GET /configs 全部字段 ##########"
curl -s -m 5 http://127.0.0.1:9090/configs -H "Authorization: Bearer $SECRET" | python3 -m json.tool --no-ensure-ascii | sed 's/^/  /'

echo
echo "########## 对照：文件里我们能管的键，内核报了几个 ##########"
curl -s -m 5 http://127.0.0.1:9090/configs -H "Authorization: Bearer $SECRET" | python3 - <<'PY'
import json, sys
d = json.load(sys.stdin)
flat = {k: v for k, v in d.items() if not isinstance(v, dict)}
tun = d.get('tun') or {}
print('  顶层标量:', ', '.join(sorted(flat.keys())))
print('  tun 子键:', ', '.join(sorted(tun.keys())))
print()
for key in ('log-level', 'mode', 'allow-lan', 'bind-address', 'mixed-port', 'socks-port', 'ipv6',
            'external-controller', 'secret', 'sniffer', 'dns', 'interface-name'):
    print('  %-22s %s' % (key, '有' if key in d else '没有'))
for key in ('enable', 'device', 'stack', 'auto-route', 'strict-route', 'mtu', 'dns-hijack', 'inet4-address'):
    print('  tun.%-18s %s' % (key, tun.get(key, '(没有)') if key in tun else '没有'))
PY
