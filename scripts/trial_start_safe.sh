#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 安全模式启动试用：只把 tun.enable 改一行（走插件自己的 Apply 通道），然后启动服务
#
# 安全前提（脚本会逐条验证）：
#   · allow-lan: false + bind-address: 127.0.0.1   → 代理端口只监听回环
#   · dns.listen: 127.0.0.1:1053                   → DNS 只监听回环
#   · external-controller: 127.0.0.1:9090          → 控制器只监听回环
#   · tun.enable: false                            → 不创建 TUN、不改默认路由
set -u

BASE=https://127.0.0.1
JAR=/tmp/trial_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

say() { printf '\n########## %s ##########\n' "$1"; }

API() {   # API <method> <path> [json]
    if [ "$1" = "GET" ]; then
        curl -sk -b "$JAR" "$BASE$2"
    else
        curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' \
             ${3:+--data "$3"} "$BASE$2"
    fi
}

say "0. 登录 WebGUI"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
echo "  登录后 CSRF token: $(printf '%s' "$TOKEN" | cut -c1-8)…"

say "1. 改动前：把 '插件默认配置' 与 '启动后果' 记录下来"
echo "--- config.yaml 里的关键行 ---"
grep -nE '^(log-level|mode|allow-lan|bind-address|socks-port|external-controller|secret):' "$CFG"
awk '/^tun:/,/^[a-z]/{print "  " $0}' "$CFG" | head -12
echo "--- 网络指纹（改动前）---"
PF_BEFORE=$(pfctl -sr 2>/dev/null | sha256 -q)
NAT_BEFORE=$(pfctl -sn 2>/dev/null | sha256 -q)
RT_BEFORE=$(netstat -rn 2>/dev/null | sha256 -q)
UB_BEFORE=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
echo "  pf=$PF_BEFORE"
echo "  nat=$NAT_BEFORE"
echo "  route=$RT_BEFORE"
echo "  unbound=$UB_BEFORE"
echo "  config.yaml sha256: $(sha256 -q "$CFG")"

say "2. 用插件自己的通道改一行：tun.enable → false"
echo "--- 2.1 从当前配置文件导入模型（import）---"
API POST /api/mihomo/settings/import '{}' | head -c 400; echo
echo "--- 2.2 设置 TUN Mode = 关（set）---"
API POST /api/mihomo/settings/set '{"mihomo":{"tun":{"enabled":"0"}}}' | head -c 400; echo
echo "--- 2.3 应用（apply：mihomo -t 校验 + 自动备份 + 最小 diff）---"
API POST /api/mihomo/settings/apply '{}' | head -c 600; echo

say "3. 校验改动：应该恰好是 1 行差异"
BAK=$(ls -1t /usr/local/etc/mihomo/config.yaml.bak.* 2>/dev/null | head -1)
echo "  备份文件: ${BAK:-（没有）}"
if [ -n "${BAK:-}" ]; then
    echo "  --- diff（备份 → 现在）---"
    diff "$BAK" "$CFG" | sed 's/^/    /'
    echo "  --- 差异行数: $(diff "$BAK" "$CFG" | grep -c '^[<>]') ---"
fi
echo "  config.yaml sha256: $(sha256 -q "$CFG")"
echo "  --- 改动后的 tun 段 ---"
awk '/^tun:/,/^[a-z]/{print "  " $0}' "$CFG" | head -10

say "4. 启动服务（插件自己的 start 动作）"
API POST /api/mihomo/service/start '{}' | head -c 300; echo
sleep 4
echo "--- 服务状态 ---"
service mihomo status 2>&1 | head -2
echo "--- 进程 ---"
ps -ax -o pid,etime,command 2>/dev/null | grep '[m]ihomo' | head -3

say "5. 启动后安全复核"
echo "--- 有没有 TUN 接口（应该没有）---"
ifconfig 2>/dev/null | grep -c tun_mihomo | sed 's/^/  tun_mihomo 接口数: /'
echo "--- 监听（应只有 127.0.0.1）---"
sockstat -4 -l 2>/dev/null | egrep 'mihomo|:9090|:7891|:1053' || echo "  (没有预期之外的监听)"
echo "--- 网络指纹（改动后，应与前完全一致）---"
PF_AFTER=$(pfctl -sr 2>/dev/null | sha256 -q)
NAT_AFTER=$(pfctl -sn 2>/dev/null | sha256 -q)
RT_AFTER=$(netstat -rn 2>/dev/null | sha256 -q)
UB_AFTER=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
[ "$PF_BEFORE" = "$PF_AFTER" ] && echo "  pf      : 一致 OK" || echo "  pf      : **不一致**"
[ "$NAT_BEFORE" = "$NAT_AFTER" ] && echo "  nat     : 一致 OK" || echo "  nat     : **不一致**"
[ "$RT_BEFORE" = "$RT_AFTER" ] && echo "  route   : 一致 OK" || echo "  route   : **不一致**"
[ "$UB_BEFORE" = "$UB_AFTER" ] && echo "  unbound : 一致 OK" || echo "  unbound : **不一致**"
echo "--- 与项目基线对照 ---"
echo "  pf 基线     b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6"
echo "  route 基线  46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619"

say "6. 仪表盘数据（服务已起，控制器应可达）"
API GET /api/mihomo/service/status | head -c 300; echo
API GET '/api/mihomo/dashboard/overview' | head -c 500; echo
echo "--- 代理分组 ---"
API GET /api/mihomo/dashboard/proxies | head -c 400; echo

say "7. 自检"
echo -n "  DNS: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  HTTP: "; curl -sk -o /dev/null -w '%{http_code}\n' "$BASE/ui/mihomo"
rm -f "$JAR"
echo
echo "########## 完成：服务已按「默认配置 + TUN 关闭」运行 ##########"
