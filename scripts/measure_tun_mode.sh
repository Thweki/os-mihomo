#!/bin/sh
# 实测：TUN 开启但 auto-route 关闭时，mihomo 在这台 FreeBSD 上做了什么
#   · 会创建什么接口、什么地址（决定 pf 策略路由的网关）
#   · 是否动默认路由/防火墙/DNS（必须一动不动）
#   · 测完立即把 TUN 关回去（回到当前试用状态）
set -u

BASE=https://127.0.0.1
JAR=/tmp/tun_measure_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

API() {
    if [ "$1" = "GET" ]; then curl -sk -b "$JAR" "$BASE$2"
    else curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' ${3:+--data "$3"} "$BASE$2"; fi
}

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

echo "########## 0. 基线（改动前） ##########"
DEF_BEFORE=$(netstat -rn -f inet | awk '$1=="default"{print $1" "$2" "$3" "$4}')
echo "  默认路由: $DEF_BEFORE"
PF_BEFORE=$(pfctl -sr 2>/dev/null | sha256 -q)
NAT_BEFORE=$(pfctl -sn 2>/dev/null | sha256 -q)
UB_BEFORE=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
echo "  pf=$PF_BEFORE  nat=$NAT_BEFORE"
echo "  现有 tun 设备: $(ifconfig -l | tr ' ' '\n' | grep -c '^tun' || true)"

echo
echo "########## 1. 开启 TUN，但关掉 auto-route / strict-route ##########"
API POST /api/mihomo/settings/import '{}' >/dev/null
API POST /api/mihomo/settings/set '{"mihomo":{"tun":{"enabled":"1","autoRoute":"0","strictRoute":"0"}}}' >/dev/null
API POST /api/mihomo/settings/apply '{}' | head -c 300; echo
BAK=$(ls -1t /usr/local/etc/mihomo/config.yaml.bak.* | head -1)
echo "  --- 与备份的差异 ---"
diff "$BAK" /usr/local/etc/mihomo/config.yaml | sed 's/^/    /'

echo
echo "########## 2. 重启服务让 TUN 生效 ##########"
API POST /api/mihomo/service/restart '{}' >/dev/null
sleep 6
service mihomo status 2>&1 | head -1

echo
echo "########## 3. 关键观测 ##########"
echo "--- 接口列表里的 tun ---"
ifconfig -l | tr ' ' '\n' | grep '^tun' || echo "  (没有 tun 设备)"
echo "--- ifconfig tun_mihomo ---"
ifconfig tun_mihomo 2>&1 | head -12
echo "--- 默认路由（必须与基线一致） ---"
DEF_AFTER=$(netstat -rn -f inet | awk '$1=="default"{print $1" "$2" "$3" "$4}')
echo "  before: $DEF_BEFORE"
echo "  after : $DEF_AFTER"
[ "$DEF_BEFORE" = "$DEF_AFTER" ] && echo "  => 默认路由未变 OK" || echo "  => **默认路由被改了**"
echo "--- 路由表里与 tun 相关的条目 ---"
netstat -rn -f inet | grep -i tun || echo "  (无)"
echo "--- pf / nat / unbound ---"
[ "$PF_BEFORE" = "$(pfctl -sr 2>/dev/null | sha256 -q)" ] && echo "  pf  未变 OK" || echo "  pf  **变了**"
[ "$NAT_BEFORE" = "$(pfctl -sn 2>/dev/null | sha256 -q)" ] && echo "  nat 未变 OK" || echo "  nat **变了**"
[ "$UB_BEFORE" = "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)" ] && echo "  unbound 未变 OK" || echo "  unbound **变了**"
echo "--- 连通性自检 ---"
echo -n "  DNS: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  HTTP(界面): "; curl -sk -o /dev/null -w '%{http_code}\n' "$BASE/ui/mihomo"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 http://www.freebsd.org/ 2>/dev/null || echo "FAIL"

echo
echo "########## 4. 控制器看 TUN 状态 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/overview" | head -c 300; echo

echo
echo "########## 5. 收尾：把 TUN 关回去（恢复试用状态） ##########"
API POST /api/mihomo/settings/import '{}' >/dev/null
API POST /api/mihomo/settings/set '{"mihomo":{"tun":{"enabled":"0"}}}' >/dev/null
API POST /api/mihomo/settings/apply '{}' >/dev/null
API POST /api/mihomo/service/restart '{}' >/dev/null
sleep 5
service mihomo status 2>&1 | head -1
echo "  tun.enable = $(awk '/^tun:/{f=1} f&&/^  enable:/{print $2; exit}' /usr/local/etc/mihomo/config.yaml)"
echo "  tun 设备数 = $(ifconfig -l | tr ' ' '\n' | grep -c '^tun' || true)"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
rm -f "$JAR"
