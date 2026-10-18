#!/bin/sh
# P12-2 · 清理重复 + 用修好的代码重新应用 + 完整核对
set -u
BASE=https://127.0.0.1
JAR=/tmp/p122_clean_jar.txt
PASS='${OPN_PW}'
X=/conf/config.xml
CLEAN=/conf/config.xml.mihomo-bak.20261018_180459
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 0. 当前（重复规则）状态 ##########"
printf '  我们的规则条数: %s | pf route-to: %s\n' \
  "$(grep -c 'Mihomo policy routing' "$X")" "$(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' || true)"
ls -1 /conf/config.xml.mihomo-bak.* | sed 's/^/  备份: /'

echo
echo "########## 1. 还原到干净备份 $CLEAN ##########"
configctl mihomo policy-net-rollback "$CLEAN" 2>&1 | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw); print('  status:', d.get('status'))
    for m in d.get('messages',[]): print('  msg:', m)
except Exception: print('  raw:', raw[:300])
"
printf '  还原后: 接口 %s / 网关 %s / 规则 %s / route-to %s / webgui-interfaces: %s\n' \
  "$(grep -c '<if>tun_mihomo</if>' "$X")" "$(grep -c '<name>MIHOMO_TUN</name>' "$X")" \
  "$(grep -c 'Mihomo policy routing' "$X")" "$(pfctl -sr 2>/dev/null | grep -c 'route-to' || true)" \
  "$(sed -n '/<webgui>/,/<\/webgui>/p' "$X" | grep -c '<interfaces>lan</interfaces>')"

echo
echo "########## 2. 重新应用（修好的去重逻辑） ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
if d.get('diff'): print('  --- diff ---'); print(d['diff'])
if d.get('message'): print('  message:', d['message'])
"

echo
echo "########## 3. 再应用一次（幂等性：应全部 already present） ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"

echo
echo "########## 4. 最终核对 ##########"
printf '  规则条数(应为 1): %s\n' "$(grep -c 'Mihomo policy routing' "$X")"
echo "  --- pf 策略路由规则 ---"
pfctl -sr 2>/dev/null | grep 'route-to' | sed 's/^/    /'
printf '  LanDirect(igb4) 的 route-to 数(应为 0): %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 || true)"
echo "  --- 接口/网关 ---"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
for node in r.find('interfaces'):
    if (node.findtext('if') or '') == 'tun_mihomo':
        print('    接口: %s -> %s (%s)' % (node.tag, node.findtext('if'), node.findtext('descr')))
gw = r.find('OPNsense/Gateways')
if gw is not None:
    for item in gw.findall('gateway_item'):
        print('    网关: %s -> %s via %s (monitor_disable=%s)' % (
            item.findtext('name'), item.findtext('gateway'), item.findtext('interface'),
            item.findtext('monitor_disable')))
PY
echo "  --- 状态接口（页面用） ---"
GET /api/mihomo/routing/netstatus | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('    interface:', d.get('interface'), '| gateway:', d.get('gateway_present'), d.get('gateway_ip'), '| rules:', [r['interface'] for r in (d.get('rules') or [])])
"
GET /api/mihomo/routing/status | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('rows',[]):
    print('    行状态:', r.get('interface'), '->', r.get('state'), '|', r.get('note'))
"

echo
echo "########## 5. 安全自检（我自己的链路 + 指纹） ##########"
echo -n "  出网(LanDirect): "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo "  nat/unbound 未变: $(pfctl -sn 2>/dev/null | sha256 -q) / $(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
echo "  LanDirect(igb4) pass 规则数: $(pfctl -sr 2>/dev/null | grep -c 'on igb4' || true)"
rm -f "$JAR"
