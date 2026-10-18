#!/bin/sh
# 立即回滚本次网络侧改动，并核对是否恢复干净
set -u
X=/conf/config.xml

echo "########## 1. 回滚（还原最近一次 config.xml 备份 + filter reload） ##########"
configctl mihomo policy-net-rollback 2>&1 | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
    print('  status:', d.get('status'))
    for m in d.get('messages',[]): print('  msg:', m)
except Exception:
    print('  raw:', raw[:400])
"

echo
echo "########## 2. 核对：webgui 的 interfaces 是否恢复 ##########"
sed -n '/<webgui>/,/<\/webgui>/p' "$X" | grep -n 'interfaces' | sed 's/^/  /'

echo
echo "########## 3. 核对：我们的东西应该都不在了 ##########"
printf '  tun_mihomo 接口块: %s\n' "$(grep -c '<if>tun_mihomo</if>' "$X")"
printf '  MIHOMO_TUN 网关  : %s\n' "$(grep -c '<name>MIHOMO_TUN</name>' "$X")"
printf '  策略路由规则     : %s\n' "$(grep -c 'Mihomo policy routing' "$X")"
printf '  pf route-to      : %s\n' "$(pfctl -sr 2>/dev/null | grep -c 'route-to' || true)"

echo
echo "########## 4. 接口列表（应恢复为 wan/lan/lo0/opt1/opt2） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
for node in r.find('interfaces'):
    print('  %-8s if=%-12s descr=%s' % (node.tag, node.findtext('if') or '', node.findtext('descr') or ''))
PY

echo
echo "########## 5. 安全自检 ##########"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo -n "  WebGUI: "; curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/ui/mihomo/routing
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo "  LanDirect(igb4) pass 规则数: $(pfctl -sr 2>/dev/null | grep -c 'on igb4' || true)"
echo "  config.xml 备份清单:"; ls -1 /conf/config.xml.mihomo-bak.* 2>/dev/null | sed 's/^/    /'
