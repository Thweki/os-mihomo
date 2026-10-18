#!/bin/sh
# 绑定/解绑全生命周期验证（只动 lan 与 LanUS；LanDirect 全程不碰）
set -u
BASE=https://127.0.0.1
JAR=/tmp/bind_jar.txt
PASS='${OPN_PW}'
X=/conf/config.xml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

show_state() {
    echo "  config.xml: 我们的规则 $(grep -c 'Mihomo policy routing' "$X") 条 | 网关 $(grep -c '<name>MIHOMO_TUN</name>' "$X") | 接口块 $(grep -c '<if>tun_mihomo</if>' "$X")"
    echo "  pf route-to: $(pfctl -sr 2>/dev/null | grep 'route-to' | sed 's/.*on \([a-z0-9]*\) route-to (\([a-z0-9_]*\).*/\1->\2/' | tr '\n' ' ')"
    echo "  行状态:"
    GET /api/mihomo/routing/status | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('rows', []):
    print('    %-6s %-16s -> %-22s %s' % (r.get('interface'), r.get('source'), r.get('target'), r.get('state')))
"
}

echo "########## 0. 现状 ##########"
show_state

echo
echo "########## 1. 再绑一个接口：LanUS (opt2) ##########"
POST /api/mihomo/routing/add_rule '{"mihomo":{"enabled":"1","interface":"opt2","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"auto","descr":"LanUS 走美国组"}}' | sed 's/^/  add: /'
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- 变更后 ---"; show_state

echo
echo "########## 2. 删除 LanUS 那一行 → 解绑该接口 ##########"
UUID=$(GET /api/mihomo/routing/search_rule | python3 -c "
import json,sys
rows=json.load(sys.stdin)['rows']
print([r['uuid'] for r in rows if r['interface']=='opt2'][0])")
POST "/api/mihomo/routing/del_rule/$UUID" '{}' | sed 's/^/  del: /'
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- 变更后（lan 应仍在、opt2 应已解绑） ---"; show_state

echo
echo "########## 3. 全部解绑（把 lan 那行也禁用）→ 应清理网关与接口块 ##########"
UUID_LAN=$(GET /api/mihomo/routing/search_rule | python3 -c "
import json,sys
rows=json.load(sys.stdin)['rows']
print([r['uuid'] for r in rows if r['interface']=='lan'][0])")
POST "/api/mihomo/routing/set_rule/$UUID_LAN" '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"manual","descr":"lan（临时改手动以便测试解绑）"}}' >/dev/null
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- 变更后（应无规则/无网关/无接口块） ---"; show_state
echo "  --- 我自己的链路自检 ---"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL

echo
echo "########## 4. 重新绑定 lan（恢复交付状态） ##########"
POST "/api/mihomo/routing/set_rule/$UUID_LAN" '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"auto","descr":"lan 走美国组（自动策略路由）"}}' >/dev/null
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- 变更后 ---"; show_state

echo
echo "########## 5. 安全自检 ##########"
printf '  LanDirect(igb4) route-to 数（应 0）: %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 || true)"
printf '  LanDirect pass 规则数: %s\n' "$(pfctl -sr 2>/dev/null | grep -c 'on igb4' || true)"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo "  unbound 指纹: $(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
echo -n "  我自己的出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
