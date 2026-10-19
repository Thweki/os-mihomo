#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# P12-2 · 步骤 1：实测 TUN 地址形态（auto-route 关闭，不碰路由/防火墙）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p122_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }
GET()  { curl -sk -b "$JAR" "$BASE$1"; }

echo "########## 0. 基线（改动前） ##########"
RT0=$(netstat -rn -f inet | sha256 -q)
PF0=$(pfctl -sr 2>/dev/null | sha256 -q)
DEF0=$(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')
echo "  默认路由: $DEF0"
echo "  route sha: $RT0"
echo "  pf sha   : $PF0"
echo "  现有 tun 设备: $(ifconfig -l | tr ' ' '\n' | grep -c '^tun' || true)"

echo
echo "########## 1. 打开 TUN（auto-route / strict-route 关闭） ##########"
POST /api/mihomo/settings/import '{}' >/dev/null
POST /api/mihomo/settings/set '{"mihomo":{"tun":{"enabled":"1","autoRoute":"0","strictRoute":"0","device":"tun_mihomo"}}}' >/dev/null
POST /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  apply:', d.get('status'), '|', ' '.join(d.get('messages',[]))[:120])
"
echo "  --- 配置里的 tun 段 ---"
awk '/^tun:/{f=1} f{print "    "$0} f&&/^[a-z]/&&!/^tun:/{exit}' "$CFG" | head -12

echo
echo "########## 2. 重启服务让 TUN 生效 ##########"
POST /api/mihomo/service/restart '{}' >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'

echo
echo "########## 3. TUN 接口形态（决定 OPNsense 网关该填什么） ##########"
ifconfig tun_mihomo 2>&1 | sed 's/^/  /' || echo "  (没有 tun_mihomo)"
echo "  --- 路由表里与 tun 相关的条目 ---"
netstat -rn -f inet | grep -i tun | sed 's/^/    /' || echo "    (无)"
netstat -rn -f inet6 2>/dev/null | grep -i tun | head -5 | sed 's/^/    /' || true

echo
echo "########## 4. 安全检查：默认路由 / 路由表 / 防火墙是否被改动 ##########"
DEF1=$(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')
echo "  默认路由: $DEF1"
[ "$DEF0" = "$DEF1" ] && echo "  => 默认路由未变 OK" || echo "  => **默认路由被改了**"
[ "$RT0" = "$(netstat -rn -f inet | sha256 -q)" ] && echo "  => 路由表未变 OK" || echo "  => 路由表**有变化**（若仅新增 tun 网段的直连路由属正常）"
[ "$PF0" = "$(pfctl -sr 2>/dev/null | sha256 -q)" ] && echo "  => pf 未变 OK" || echo "  => pf **有变化**"
echo "  TUN 接口数: $(ifconfig -l | tr ' ' '\n' | grep -c '^tun' || true)"
echo "  mihomo 连接数: $(curl -s -H "Authorization: Bearer $(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read(); m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print(m.group(1).strip().strip(chr(34)).strip(chr(39)) if m else '')")" http://127.0.0.1:9090/connections | python3 -c "import json,sys; print(json.load(sys.stdin).get('downloadTotal',0), 'bytes 累计')" 2>/dev/null)"
echo -n "  DNS 自检: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  出网自检: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://www.freebsd.org/ || echo FAIL

echo
echo "########## 5. OPNsense 侧结构取证 ##########"
echo "--- 现有 gateway_item 结构（核心写法） ---"
grep -rn 'monitor_disable\|<gateway_item>' /usr/local/etc/inc/interfaces.inc /usr/local/etc/inc/gwlb.inc 2>/dev/null | head -6
echo "--- 现有 filter rule 结构（含 gateway 的写法） ---"
grep -rn "'gateway'\|<gateway>" /usr/local/etc/inc/filter.inc 2>/dev/null | head -6
echo "--- 当前 pf 里的 pass 规则样式（看 quick 与否） ---"
pfctl -sr 2>/dev/null | head -4 | sed 's/^/    /'
rm -f "$JAR"
