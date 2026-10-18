#!/bin/sh
# 修复验证 + 安全启动试用
set -u

BASE=https://127.0.0.1
JAR=/tmp/trial_jar2.txt
CFG=/usr/local/etc/mihomo/config.yaml
PASS='${OPN_PW}'
rm -f "$JAR"

API() {
    if [ "$1" = "GET" ]; then
        curl -sk -b "$JAR" "$BASE$2"
    else
        curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' \
             ${3:+--data "$3"} "$BASE$2"
    fi
}

echo "########## 0. 登录 ##########"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
echo "  OK"

echo
echo "########## 1. 修复点：configd 动作现在用 one* ##########"
grep -A1 -E '^\[(start|stop|restart)\]' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf | grep command

echo
echo "########## 2. 修复点：状态不再返回 disabled（前端才会有按钮） ##########"
API GET /api/mihomo/service/status; echo

echo
echo "########## 3. 指纹（启动前） ##########"
PF0=$(pfctl -sr 2>/dev/null | sha256 -q); NAT0=$(pfctl -sn 2>/dev/null | sha256 -q)
RT0=$(netstat -rn 2>/dev/null | sha256 -q); UB0=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
echo "  pf=$PF0"
echo "  route=$RT0"

echo
echo "########## 4. 通过界面接口启动服务 ##########"
API POST /api/mihomo/service/start '{}'; echo
sleep 5
echo "--- 服务状态 ---"
service mihomo status 2>&1 | head -2
echo "--- 进程 ---"
ps -ax -o pid,etime,command 2>/dev/null | grep '[m]ihomo' | head -3

echo
echo "########## 5. 启动后安全复核 ##########"
echo -n "  TUN 接口数（应为 0）: "; ifconfig 2>/dev/null | grep -c tun_mihomo
echo "  监听（应全部是 127.0.0.1）:"
sockstat -4 -l 2>/dev/null | egrep ':9090|:7891|:1053' | sed 's/^/    /'
[ "$PF0" = "$(pfctl -sr 2>/dev/null | sha256 -q)" ] && echo "  pf      一致 OK" || echo "  pf      **不一致**"
[ "$NAT0" = "$(pfctl -sn 2>/dev/null | sha256 -q)" ] && echo "  nat     一致 OK" || echo "  nat     **不一致**"
[ "$RT0" = "$(netstat -rn 2>/dev/null | sha256 -q)" ] && echo "  route   一致 OK" || echo "  route   **不一致**"
[ "$UB0" = "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)" ] && echo "  unbound 一致 OK" || echo "  unbound **不一致**"

echo
echo "########## 6. 仪表盘数据 ##########"
API GET /api/mihomo/service/status; echo
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/overview" | head -c 600; echo
echo "--- 分组数量 ---"
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/proxies" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ready:', d.get('ready'), '| groups:', len(d.get('groups',[])), '|', [g.get('name') for g in d.get('groups',[])][:6])" 2>/dev/null || echo "  (解析失败)"

echo
echo "########## 7. 自检 ##########"
echo -n "  DNS: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  HTTP(mihomo 页): "; curl -sk -b "$JAR" -o /dev/null -w '%{http_code}\n' "$BASE/ui/mihomo"
rm -f "$JAR"
