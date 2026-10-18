#!/bin/sh
# 复核（终）：浮动规则幂等 + pf 顺序（route-to 必须在默认放行之前）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14l_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 连续两次应用（第二次必须 nothing changed） ##########"
for i in 1 2; do
    echo "  --- 第 $i 次 ---"
    POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('   status:', d.get('status'))
for m in d.get('messages',[]): print('   msg:', m)
"
done

echo
echo "########## 2. 规则条数与内容（应恰好 4 条，无重复） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
rules = [] if flt is None else [x for x in flt.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]
print('  Mihomo 规则数:', len(rules))
for rule in sorted(rules, key=lambda x: int(x.findtext('sequence') or 0)):
    print('   seq=%-5s gw=%-12s src=%-6s dst=%-8s %s' % (
        rule.findtext('sequence'), rule.findtext('gateway') or '-',
        rule.findtext('source_net') or '-', rule.findtext('destination_net') or '-',
        rule.findtext('description')))
PY

echo
echo "########## 3. pf 里的顺序：浮动规则必须排在接口默认放行规则之前 ##########"
configctl filter reload >/dev/null 2>&1
sleep 2
RT_LINE=$(pfctl -sr 2>/dev/null | grep -n 'route-to' | head -1 | cut -d: -f1)
DEF_LINE=$(pfctl -sr 2>/dev/null | grep -n 'on igb0' | grep 'label "cd0e458a' | head -1 | cut -d: -f1)
echo "  route-to 规则行号: ${RT_LINE:-未找到}"
echo "  默认放行规则行号 : ${DEF_LINE:-未找到}"
if [ -n "${RT_LINE:-}" ] && [ -n "${DEF_LINE:-}" ] && [ "$RT_LINE" -lt "$DEF_LINE" ]; then
    echo "  => 浮动策略路由排在默认放行之前 ✅（真实转发流量会被送进 mihomo）"
else
    echo "  => 顺序仍不对 ❌"
fi
echo "  --- 浮动规则在 pf 里的样子 ---"
pfctl -sr 2>/dev/null | grep -E 'route-to|to \(igb4:network\)|to \(igb5:network\)' | head -4 | sed 's/^/    /'

echo
echo "########## 4. 自检 + 安全 ##########"
POST /api/mihomo/routing/selftest '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results', []):
    print('  ', r.get('interface'), '出口 IP:', r.get('foreign_ip') or '(失败)', '| 组:', (r.get('foreign_group') or '—')[:34])
"
printf '  igb4 route-to 数（应 0）: %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 || true)"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
