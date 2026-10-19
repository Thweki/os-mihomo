#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 正确重启 WebGUI（lighttpd + php-cgi），让新词库生效，然后复检
set -u

echo "=== 1. 重启 WebGUI ==="
service lighttpd onerestart 2>&1 | head -5
sleep 3
curl -sk -o /dev/null -w 'webgui 自检: %{http_code}\n' https://127.0.0.1/ || true

echo
echo "=== 2. 新的 php-cgi 进程（etime 应很短）==="
ps -ax -o pid,etime,command 2>/dev/null | grep '[p]hp-cgi' | head -6

echo
echo "=== 3. 复检各页面中文 ==="
BASE=https://127.0.0.1
JAR=/tmp/i18n_jar3.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${PASS}&$N=$V" "$BASE/index.php"

check() {
    url="$1"; shift
    html=$(curl -sk -b "$JAR" "$BASE$url")
    printf '%-30s ' "$url"
    for pat in "$@"; do
        if printf '%s' "$html" | grep -q "$pat"; then printf '[%s] ' "$pat"; else printf '[-%s-] ' "$pat"; fi
    done
    echo
}

check /ui/mihomo '代理分组' '活动连接' '全部断开' '未知'
check /ui/mihomo/settings '配置文件' '访问密钥' '订阅地址' '校验'
check /ui/mihomo/subscription '订阅管理' '开始订阅' '日志视图' '访问密钥'
check /ui/mihomo/log '内核日志' '订阅日志' '清空日志' '字节'
check /ui/unbound/overview '概况' '详细' '设置'

rm -f "$JAR"
