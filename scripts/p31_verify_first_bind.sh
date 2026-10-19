#!/bin/sh
# 验证首绑顺序修复：跑一次「应用」，看网关先建、规则后写、pf 里真的出现 route-to
set -u
BASE=https://127.0.0.1
JAR=/tmp/p31_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

echo "########## 0. 应用前 ##########"
echo "  策略表行数: $(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
n=r.find('OPNsense/mihomo/policyRouting')
print(0 if n is None else len(n.findall('rule')))")"
echo "  MIHOMO_TUN 网关: $(grep -c 'MIHOMO_TUN' /conf/config.xml | head -1) 处"
echo "  插件浮动规则: $(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
f=r.find('OPNsense/Firewall/Filter')
print(0 if f is None else len([x for x in f.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]))")"
echo "  pf route-to(tun_mihomo): $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' | head -1)"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo
echo "########## 1. 应用（mihomo 规则 + 网络侧） ##########"
POST /api/mihomo/routing/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  [mihomo] status:', d.get('status'))
for m in d.get('messages',[]): print('   ', m)
"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  [OPNsense] status:', d.get('status'))
for m in d.get('messages',[]): print('   ', m)
if d.get('message'): print('   !! message:', str(d['message'])[:400])
"

echo
echo "########## 2. 应用后：网络侧对象 ##########"
echo "  MIHOMO_TUN 网关: $(grep -c 'MIHOMO_TUN' /conf/config.xml | head -1) 处"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
rules = [] if flt is None else [x for x in flt.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]
print('  插件浮动规则: %d 条' % len(rules))
for rule in sorted(rules, key=lambda x: int(x.findtext('sequence') or 0)):
    print('    seq=%-5s src=%-6s dst=%-8s gw=%-12s %s' % (
        rule.findtext('sequence'), rule.findtext('source_net') or '-',
        rule.findtext('destination_net') or '-', rule.findtext('gateway') or '-',
        rule.findtext('description')))
PY

echo
echo "########## 3. pf 规则（关键：route-to 必须出现在接口默认放行之前） ##########"
for dev in igb0 igb5 igb4; do
    echo "  --- $dev ---"
    pfctl -sr 2>/dev/null | grep "on $dev" | grep -n 'route-to' | head -3 | sed 's/^/    /'
done
echo "  igb4（LanDirect）route-to 条数（必须 0）: $(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 | head -1)"
echo "  内网直达规则（无网关）: $(pfctl -sr 2>/dev/null | grep -c 'to (igb.*:network)' | head -1) 条"

echo
echo "########## 4. 安全与连通 ##########"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  服务: $(service mihomo status 2>&1 | head -1)"

echo
echo "########## 5. 自检（把测试流量送进 TUN 看出口） ##########"
POST /api/mihomo/routing/selftest '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('status') != 'ok':
    print('  status:', d.get('status'), d.get('message',''))
for r in d.get('results', []):
    print('   %-6s 出口 IP: %-16s 组: %-22s 规则: %s' % (
        r.get('interface'), r.get('foreign_ip') or '(失败)',
        (r.get('foreign_group') or '—')[:20], (r.get('foreign_rule') or '—')[:46]))
"
rm -f "$JAR"
