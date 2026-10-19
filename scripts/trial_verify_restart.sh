#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 验证 restart 路径 + 记录最终状态
set -u
BASE=https://127.0.0.1
JAR=/tmp/trial_jar3.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

echo "########## 1. 重启前 ##########"
service mihomo status 2>&1 | head -1
OLD_PID=$(pgrep -f '/usr/local/bin/mihomo -d /usr/local/etc/mihomo/' | head -1)
echo "  mihomo pid: ${OLD_PID:-无}"

echo
echo "########## 2. 通过界面接口重启 ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
     "$BASE/api/mihomo/service/restart"; echo
sleep 6

echo
echo "########## 3. 重启后 ##########"
service mihomo status 2>&1 | head -1
NEW_PID=$(pgrep -f '/usr/local/bin/mihomo -d /usr/local/etc/mihomo/' | head -1)
echo "  mihomo pid: ${NEW_PID:-无}"
if [ -n "${OLD_PID:-}" ] && [ -n "${NEW_PID:-}" ] && [ "$OLD_PID" != "$NEW_PID" ]; then
    echo "  => 重启生效（pid 变了）"
else
    echo "  => 需要人工确认"
fi
echo "--- 控制器 ---"
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/overview" | head -c 220; echo

echo
echo "########## 4. 最终状态 ##########"
echo -n "  TUN 接口: "; ifconfig 2>/dev/null | grep -c tun_mihomo
echo "  监听:"; sockstat -4 -l 2>/dev/null | egrep ':9090|:7891|:1053' | sed 's/^/    /'
echo -n "  开机自启: "; cat /etc/rc.conf.d/mihomo
echo "  config.yaml 的 tun.enable: $(awk '/^tun:/{f=1} f&&/^  enable:/{print $2; exit}' /usr/local/etc/mihomo/config.yaml)"
echo "  网络指纹:"
echo "    pf    $(pfctl -sr 2>/dev/null | sha256 -q)   (基线 b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6)"
echo "    route $(netstat -rn 2>/dev/null | sha256 -q)   (基线 46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619)"
echo -n "  DNS: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
rm -f "$JAR"
