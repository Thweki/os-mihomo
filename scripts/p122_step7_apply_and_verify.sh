#!/bin/sh
# P12-2 · 端到端：同步 OPNsense 网络侧（仅 lan）→ 验证 → 证明 LanDirect 未受影响
set -u
BASE=https://127.0.0.1
JAR=/tmp/p122_apply_jar.txt
PASS='${OPN_PW}'
CFG=/usr/local/etc/mihomo/config.yaml
XCFG=/conf/config.xml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 0. 变更前基线 ##########"
NAT0=$(pfctl -sn 2>/dev/null | sha256 -q)
RT0=$(netstat -rn -f inet | sha256 -q)
UB0=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
DEF0=$(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')
echo "  默认路由: $DEF0"
echo "  nat/route/unbound sha: $NAT0 / $RT0 / $UB0"
echo "  config.xml sha: $(sha256 -q $XCFG)"
echo "  现有 route-to 规则数: $(pfctl -sr 2>/dev/null | grep -c 'route-to' || true)"
echo "  LanDirect(igb4) 上的 pass 规则数: $(pfctl -sr 2>/dev/null | grep -c 'on igb4' || true)"

echo
echo "########## 1. 把策略行改成「策略路由=自动」 ##########"
UUID=$(GET /api/mihomo/routing/search_rule | python3 -c "import json,sys; print(json.load(sys.stdin)['rows'][0]['uuid'])")
POST "/api/mihomo/routing/set_rule/$UUID" '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"auto","descr":"lan 走美国组（自动策略路由）"}}' | sed 's/^/  /'

echo
echo "########## 2. 网络侧现状（netstatus） ##########"
GET /api/mihomo/routing/netstatus | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  device      :', d.get('device'), '| up:', d.get('device_up'))
print('  interface   :', d.get('interface') or '(absent)')
print('  gateway     :', d.get('gateway_name'), '| present:', d.get('gateway_present'), '| peer:', d.get('gateway_ip') or '(unknown)')
print('  rules       :', d.get('rules'))
print('  backups     :', [b.split('/')[-1] for b in (d.get('backups') or [])])
"

echo
echo "########## 3. 变更计划（弹窗里显示的就是这个） ##########"
GET /api/mihomo/routing/netplan | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('changes',[]): print('  ·', c)
print('  note:', d.get('note'))
"

echo
echo "########## 4. 应用（写 config.xml + filter reload） ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
if d.get('diff'): print('  --- diff ---'); print(d['diff'])
if d.get('message'): print('  message:', d['message'])
"

echo
echo "########## 5. 变更后验证 ##########"
echo "  --- config.xml 里我们加的东西 ---"
grep -n 'tun_mihomo\|MIHOMO_TUN\|Mihomo policy routing' "$XCFG" | sed 's/^/    /'
echo "  --- pf 里带 route-to 的规则（应只有 igb0/lan 一条） ---"
pfctl -sr 2>/dev/null | grep 'route-to' | sed 's/^/    /'
echo "  --- 有没有动到 LanDirect（igb4）的策略路由（应为 0）---"
pfctl -sr 2>/dev/null | grep 'route-to' | grep -c 'igb4' | sed 's/^/    igb4 route-to 数: /'
echo "  --- 网关是否被 OPNsense 认为可用 ---"
/usr/local/opnsense/scripts/routes/gateway_status.php 2>/dev/null | grep -i mihomo | sed 's/^/    /' || netstat -rn -f inet | grep 198.18.0 | sed 's/^/    /'
echo "  --- 安全复核 ---"
[ "$NAT0" = "$(pfctl -sn 2>/dev/null | sha256 -q)" ] && echo "    nat 未变 OK" || echo "    nat **变了**"
[ "$RT0" = "$(netstat -rn -f inet | sha256 -q)" ] && echo "    route 未变 OK" || echo "    route **变了**（新增 TUN 网段直连路由属正常）"
[ "$UB0" = "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)" ] && echo "    unbound 未变 OK" || echo "    unbound **变了**"
DEF1=$(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')
[ "$DEF0" = "$DEF1" ] && echo "    默认路由未变 OK ($DEF1)" || echo "    默认路由 **被改了**: $DEF1"
echo "    TUN 接口: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2}')"

echo
echo "########## 6. 端到端：把「进入 TUN」的流量验证一遍（临时主机路由，测完删除） ##########"
TARGET=$(host -W 3 -t a api.ipify.org 127.0.0.1 2>/dev/null | awk '/has address/{print $NF; exit}')
echo "  测试目标: api.ipify.org -> ${TARGET:-解析失败}"
if [ -n "${TARGET:-}" ]; then
    route add -host "$TARGET" -interface tun_mihomo 2>&1 | sed 's/^/    route add: /'
    echo -n "    经 TUN 的出口 IP: "
    curl -s --max-time 25 --resolve "api.ipify.org:443:$TARGET" https://api.ipify.org || echo FAIL
    route delete -host "$TARGET" 2>&1 | sed 's/^/    route delete: /'
    echo "    （已删除临时路由）"
fi
echo "  --- 内核日志证据（最近几条规则命中） ---"
tail -30 /var/log/mihomo.log | grep -E 'match' | tail -4 | sed 's/^/    /'

echo
echo "########## 7. 我自己的链路（LanDirect）自检 ##########"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://www.freebsd.org/ || echo FAIL
echo -n "  SSH/管理面: "; curl -sk -o /dev/null -w '%{http_code}\n' "$BASE/ui/mihomo/routing"
rm -f "$JAR"
