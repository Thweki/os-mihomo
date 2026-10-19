#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 实验：能否用 API 建「浮动规则」（interface 留空）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14j_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/firewall/filter" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

echo "########## 1. 浮动规则（interface 留空）+ 网关 ##########"
RESP=$(curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{
  "rule": {
    "enabled": "1", "action": "pass", "quick": "1",
    "ipprotocol": "inet", "direction": "in", "sequence": "1",
    "gateway": "MIHOMO_TUN", "description": "Mihomo test floating policy",
    "source": {"any": "1"}, "destination": {"any": "1"}
  }
}' "$BASE/api/firewall/filter/add_rule")
echo "  response: $(printf '%s' "$RESP" | head -c 400)"
UUID=$(printf '%s' "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null)
echo "  uuid: $UUID"

echo
echo "########## 2. 它在列表里的 prio_group（应为 Floating） ##########"
curl -sk -b "$JAR" "$BASE/api/firewall/filter/search_rule?rowCount=50" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for row in d.get('rows', []):
        if 'Mihomo' in (row.get('description') or '') or 'Default allow' in (row.get('description') or ''):
            print('   ', {k: row.get(k) for k in ('description','prio_group','interface','sequence','gateway','type','action')})
except Exception as e:
    print('  解析失败:', e)
"

echo
echo "########## 3. 生效后 pf 顺序（浮动规则应该在默认放行之前） ##########"
configctl filter reload >/dev/null 2>&1
sleep 2
pfctl -sr 2>/dev/null | grep -nE 'route-to|to any' | head -6 | sed 's/^/  /'

echo
echo "########## 4. 清理测试规则 ##########"
if [ -n "$UUID" ]; then
    curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
        "$BASE/api/firewall/filter/del_rule/$UUID" | head -c 100; echo
    configctl filter reload >/dev/null 2>&1
fi
echo "  残留: $(grep -c 'Mihomo test' /conf/config.xml)"
rm -f "$JAR"
