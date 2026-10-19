#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 让内核加载当前配置（文件比进程新则重启），并复核 pf 顺序 + 自检
set -u
CFG=/usr/local/etc/mihomo/config.yaml
PID=$(pgrep -f '/usr/local/bin/mihomo -d /usr/local/etc/mihomo/' | head -1)

echo "########## 1. 进程启动时间 vs 配置文件修改时间 ##########"
echo "  mihomo pid: ${PID:-无}"
[ -n "${PID:-}" ] && ps -o lstart= -p "$PID" | sed 's/^/  进程启动: /'
stat -f '  配置改动: %Sm' -t '%a %b %e %T %Y' "$CFG" 2>/dev/null || ls -lT "$CFG" | sed 's/^/  /'

NEED=0
if [ -z "${PID:-}" ]; then
    NEED=1
elif [ "$(stat -f %m "$CFG")" -gt "$(ps -o lstart= -p "$PID" | xargs -I{} date -j -f '%a %b %e %T %Y' '{}' '+%s' 2>/dev/null || echo 0)" ]; then
    NEED=1
fi
echo "  结论: $([ "$NEED" = 1 ] && echo '文件比进程新 → 需要重启' || echo '已是当前配置')"

if [ "$NEED" = 1 ]; then
    echo
    echo "########## 2. 重启服务（加载当前配置） ##########"
    service mihomo restart 2>&1 | sed 's/^/  /'
    sleep 3
    echo "  状态: $(service mihomo status 2>&1 | head -1)"
fi

echo
echo "########## 3. pf 顺序：浮动策略路由必须在接口默认放行之前 ##########"
RT=$(pfctl -sr 2>/dev/null | grep -n 'route-to' | head -1 | cut -d: -f1)
DEF=$(pfctl -sr 2>/dev/null | grep -n 'label "cd0e458a' | head -1 | cut -d: -f1)
echo "  第一条 route-to 行号: ${RT:-无}"
echo "  接口默认放行行号    : ${DEF:-无}"
if [ -n "${RT:-}" ] && [ -n "${DEF:-}" ] && [ "$RT" -lt "$DEF" ]; then
    echo "  => 顺序正确 ✅（真实转发流量会被送进 mihomo）"
else
    echo "  => 顺序可疑，需要检查 ⚠️"
fi
echo "  --- 浮动规则在 pf 里的样子（前 8 条含 route-to 或内网直达） ---"
pfctl -sr 2>/dev/null | grep -E 'route-to|to \(igb[0-9]+:network\)' | head -8 | sed 's/^/    /'
echo "  igb4（LanDirect）route-to: $(pfctl -sr 2>/dev/null | grep route-to | grep -c igb4 | head -1) 条（必须 0）"

echo
echo "########## 4. 内核现在认得的受管规则（日志/规则列表） ##########"
SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print((m.group(1).strip().strip('\"').strip(chr(39))) if m else '')")
curl -s -m 5 http://127.0.0.1:9090/rules -H "Authorization: Bearer $SECRET" | python3 -c "
import json,sys
d=json.load(sys.stdin); rules=d.get('rules',[])
print('  规则总数:', len(rules))
for r in rules[:6]:
    print('   %-16s %-46s → %s' % (r.get('type'), (r.get('payload') or '')[:44], r.get('proxy')))
"

echo
echo "########## 5. 端到端：自检（应命中受管规则） ##########"
JAR=/tmp/p34_jar.txt; BASE=https://127.0.0.1
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/selftest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('status') != 'ok': print('  status:', d.get('status'), d.get('message',''))
for r in d.get('results', []):
    print('   %-6s 出口 IP: %-16s 组: %-20s 规则: %s' % (
        r.get('interface'), r.get('foreign_ip') or '(失败)',
        (r.get('foreign_group') or '—')[:18], (r.get('foreign_rule') or '—')[:52]))
"

echo
echo "########## 6. 安全 ##########"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  TUN: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2}')"
rm -f "$JAR"
