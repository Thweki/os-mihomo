#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 复核：浮动规则是否真的排在默认放行规则之前 + 计划/幂等 + 自检
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14k_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }
GET()  { curl -sk -b "$JAR" "$BASE$1"; }

echo "########## 1. 计划 ##########"
GET /api/mihomo/routing/netplan | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('changes',[]): print('  ·', c)
print('  note:', d.get('note'))
"

echo
echo "########## 2. 应用 ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
if d.get('message'): print('  message:', str(d['message'])[:300])
for m in d.get('messages',[]): print('  msg:', m)
"

echo
echo "########## 3. 新模块里的浮动规则 ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
for rule in ([] if flt is None else flt.findall('rules/rule')):
    d = rule.findtext('description') or ''
    if 'Mihomo' not in d:
        continue
    print('  seq=%-5s iface=%-10s gw=%-12s src=%-8s dst=%-8s %s' % (
        rule.findtext('sequence') or '-', rule.findtext('interface') or '(floating)',
        rule.findtext('gateway') or '-',
        rule.findtext('source_net') or '-', rule.findtext('destination_net') or '-', d))
PY

echo
echo "########## 4. 旧版根 <filter> 是否已清空 ##########"
python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('filter')
print('  根 <filter> 下规则数:', 0 if flt is None else len(flt.findall('rule')))
"

echo
echo "########## 5. pf 顺序（浮动规则应在默认放行之前；route-to 应在直达之后） ##########"
configctl filter reload >/dev/null 2>&1
sleep 2
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -nE 'route-to|to any|192.168.2|192.168.10' | sed 's/^/  /'

echo
echo "########## 6. 幂等：再应用一次 ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"

echo
echo "########## 7. 自检 ##########"
POST /api/mihomo/routing/selftest '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results', []):
    print('  ', r.get('interface'), '出口 IP:', r.get('foreign_ip') or '(失败)',
          '| 规则:', (r.get('foreign_rule') or '—')[:52], '| 组:', (r.get('foreign_group') or '—')[:34])
"

echo
echo "########## 8. 安全（LanDirect / 默认路由 / 出网） ##########"
printf '  igb4 route-to 数（应 0）: %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 || true)"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
