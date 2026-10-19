#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 开启 sniffer → 重新自检（期望：国外流量命中 AND 规则 → 🇺🇸 United States）
set -u
BASE=https://127.0.0.1
JAR=/tmp/sniff_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 打开 sniffer（模型 + 落盘） ##########"
POST /api/mihomo/settings/set '{"mihomo":{"general":{"sniffer":"1"}}}' | sed 's/^/  set: /'
POST /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  apply:', d.get('status'), '|', ' '.join(d.get('messages',[]))[:100])
"
echo "  config.yaml 里的 sniffer："
grep -n -A2 '^sniffer:' "$CFG" | sed 's/^/    /' || echo "    (无)"

echo
echo "########## 2. 重启服务 ##########"
POST /api/mihomo/service/restart '{}' >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'

echo
echo "########## 3. 重新自检 ##########"
TOKEN2=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN2" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/selftest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for r in d.get('results', []):
    print('  ---', r.get('interface'), '(' + (r.get('source') or '') + ' →', (r.get('expected_group') or 'DIRECT') + ')')
    print('     出口 IP :', r.get('foreign_ip') or '(失败)')
    print('     命中规则:', r.get('foreign_rule') or '—')
    print('     出口组  :', r.get('foreign_group') or '—')
    print('     国内    :', r.get('domestic_rule') or '—')
    if r.get('note'): print('     备注    :', r.get('note'))
"

echo
echo "########## 4. 内核日志佐证（最近 5 条命中） ##########"
tail -60 /var/log/mihomo.log | grep 'match' | tail -5 | sed 's/^/  /'
rm -f "$JAR"
