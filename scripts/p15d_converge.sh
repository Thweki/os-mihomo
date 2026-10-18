#!/bin/sh
# 一致性收敛：表里已无策略行 → 网络侧也应当全部撤掉（浮动规则/网关/接口）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p15d_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

echo "########## 0. 现状：浮动规则是否还在 ##########"
python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
rules = [] if flt is None else [x for x in flt.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]
print('  Mihomo 浮动规则数:', len(rules))
for rule in rules:
    print('   ', rule.findtext('description'))
"
echo "  pf route-to: $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' || true)"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

echo
echo "########## 1. 同步（表里无行 → 全部解绑） ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/netapply" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"

echo
echo "########## 2. 收敛结果 ##########"
python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
rules = [] if flt is None else [x for x in flt.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]
print('  Mihomo 浮动规则数:', len(rules))
gw = r.find('OPNsense/Gateways')
print('  MIHOMO_TUN 网关:', 'present' if (gw is not None and any((i.findtext('name')=='MIHOMO_TUN') for i in gw.findall('gateway_item'))) else 'removed')
tun = None
for node in r.find('interfaces'):
    if (node.findtext('if') or '') == 'tun_mihomo':
        tun = node.tag
print('  tun_mihomo 接口块:', tun or 'removed')
"
echo "  pf route-to: $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' || true)"
echo "  服务: $(service mihomo status 2>&1 | head -1)"
echo "  TUN 设备仍由内核创建（auto-route 关）: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2}')"

echo
echo "########## 3. 自检（无绑定时应提示无可自检项） ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/selftest" | head -c 300; echo

echo
echo "########## 4. 安全 ##########"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
