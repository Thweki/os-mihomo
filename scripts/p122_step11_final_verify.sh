#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# P12-2 · 最终验收：状态正确 + 规则生效 + 端到端（TUN 路径）+ LanDirect 安全
set -u
BASE=https://127.0.0.1
JAR=/tmp/p122_final_jar.txt
X=/conf/config.xml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 页面状态接口（应显示生效中） ##########"
GET /api/mihomo/routing/status | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  tun_enabled:', d.get('tun_enabled'), '| auto_route:', d.get('auto_route'),
      '| gateway:', d.get('gateway'), '| firewall_rule:', d.get('firewall_rule'))
for r in d.get('rows', []):
    print('  行:', r.get('interface'), r.get('source'), '->', r.get('target'),
          '|', r.get('state'), '|', r.get('note'))
"
echo "  --- 网络侧状态 ---"
GET /api/mihomo/routing/netstatus | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  device:', d.get('device'), d.get('device_up'), '| interface:', d.get('interface'),
      '| gateway:', d.get('gateway_present'), d.get('gateway_ip'), '| rules:', [r['interface'] for r in (d.get('rules') or [])])
"

echo
echo "########## 2. 端到端：进入 TUN 的流量（临时主机路由，测完即删） ##########"
TARGET=$(host -W 3 -t a api.ipify.org 127.0.0.1 2>/dev/null | awk '/has address/{print $NF; exit}')
route delete -host "$TARGET" 2>/dev/null || true
echo "  目标: api.ipify.org -> $TARGET"
route add -host "$TARGET" -interface tun_mihomo >/dev/null 2>&1 && echo "  临时路由已加"
echo -n "  经 TUN 取到的出口 IP: "; curl -s --max-time 25 --resolve "api.ipify.org:443:$TARGET" https://api.ipify.org; echo
route delete -host "$TARGET" >/dev/null 2>&1 && echo "  临时路由已删"
echo "  --- 内核日志（规则命中证据） ---"
tail -40 /var/log/mihomo.log | grep 'match' | tail -3 | sed 's/^/    /'

echo
echo "########## 3. LanDirect 侧安全性（关键） ##########"
printf '  config.xml 里 opt1(LanDirect) 的 route-to 数（应 0）: %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c 'igb4' || true)"
printf '  LanDirect 上的 pass 规则数（应与改动前一致 10）: %s\n' "$(pfctl -sr 2>/dev/null | grep -c 'on igb4' || true)"
printf '  接口 opt1 是否仍是 igb4/LanDirect: %s\n' "$(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
n=r.find('interfaces/opt1')
print((n.findtext('if') or '') + '/' + (n.findtext('descr') or ''))
")"
echo -n "  我自己的出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo "  unbound 指纹: $(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"

echo
echo "########## 4. 回滚动作（带参数）自检：只验证参数能被接收 ##########"
configctl mihomo policy-net-rollback /conf/nonexistent 2>&1 | head -2 | sed 's/^/  /'
rm -f "$JAR"
