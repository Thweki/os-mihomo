#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 决定性实验：把策略规则写进新防火墙模块（sequence=0），看是否排在默认放行规则之前
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14i_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/firewall/filter" 2>/dev/null | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
echo "  token: $(printf '%s' "$TOKEN" | cut -c1-10)…"

echo
echo "########## 1. 往新模块加一条测试规则（sequence=0，带网关） ##########"
RESP=$(curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{
  "rule": {
    "enabled": "1", "action": "pass", "quick": "1", "interface": "lan",
    "ipprotocol": "inet", "direction": "in", "sequence": "0",
    "gateway": "MIHOMO_TUN", "description": "Mihomo test policy (lan)",
    "source": {"network": "lan"}, "destination": {"any": "1"}
  }
}' "$BASE/api/firewall/filter/add_rule")
echo "  response: $(printf '%s' "$RESP" | head -c 300)"
UUID=$(printf '%s' "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null)
echo "  uuid: $UUID"

echo
echo "########## 2. 应用并检查 pf 顺序 ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/firewall/filter/apply" >/dev/null 2>&1 || configctl filter reload >/dev/null 2>&1
sleep 2
echo "  --- igb0 上的规则顺序（默认放行 vs 测试规则） ---"
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -nE 'to any|route-to' | sed 's/^/    /'
echo "  --- 测试规则在 config.xml 里的位置 ---"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
for rule in ([] if flt is None else flt.findall('rules/rule')):
    print('  seq=%-6s iface=%-8s gw=%-12s %s' % (
        rule.findtext('sequence') or '-', rule.findtext('interface') or '-',
        rule.findtext('gateway') or '-', (rule.findtext('description') or '')[:44]))
PY

echo
echo "########## 3. 自检（走 TUN 的代理路径是否仍然正常） ##########"
TOKEN_R=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN_R" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/selftest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results', []):
    print('  ', r.get('interface'), '出口 IP:', r.get('foreign_ip') or '(失败)',
          '| 规则:', (r.get('foreign_rule') or '—')[:50])
"

echo
echo "########## 4. 清理：删除测试规则 ##########"
if [ -n "$UUID" ]; then
    curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
        "$BASE/api/firewall/filter/del_rule/$UUID" | head -c 120; echo
    configctl filter reload >/dev/null 2>&1
fi
echo "  剩余 Mihomo test 规则: $(grep -c 'Mihomo test policy' /conf/config.xml)"
rm -f "$JAR"
