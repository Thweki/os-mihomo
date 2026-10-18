#!/bin/sh
# 应用完整 sniffer → 重启 → 自检（期望命中 AND 规则 → 🇺🇸 United States）
set -u
BASE=https://127.0.0.1
JAR=/tmp/sniff3_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
TOKEN_R=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

echo "########## 1. 应用（写入完整 sniffer 块） ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/settings/apply" | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  apply:', d.get('status'), '|', ' '.join(d.get('messages',[]))[:90])
"
echo "  --- config.yaml 的 sniffer 块 ---"
awk '/^sniffer:/{f=1} f{print "    "$0} f&&/^[a-z]/&&!/^sniffer:/{exit}' "$CFG" | head -14

echo
echo "########## 2. 重启服务（走插件动作 = onerestart） ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN_R" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/service/restart" >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'

echo
echo "########## 3. 自检 ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN_R" -H 'Content-Type: application/json' --data '{}' \
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
"

echo
echo "########## 4. 日志佐证 ##########"
tail -60 /var/log/mihomo.log | grep 'match' | tail -4 | sed 's/^/  /'
rm -f "$JAR"
