#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 收尾：路由页 TUN 提醒存在且在 TUN 开着时隐藏；五页 0 报错
set -u
BASE=https://127.0.0.1
JAR=/tmp/p61_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p61-routing.html
echo "########## 路由页 ##########"
grep -o 'id="policyTunHint"[^>]*' /tmp/p61-routing.html | sed 's/^/  /'
grep -o 'TUN 模式关着[^<]*' /tmp/p61-routing.html | head -1 | sed 's/^/  /'
echo "  对话框表单字段（id 含点，验证渲染正常）:"
grep -o 'id="mihomo\.[a-z]*"' /tmp/p61-routing.html | sort -u | tr '\n' ' ' | sed 's/^/    /'
echo
echo "########## 五个页面 ##########"
for page in "" settings subscription routing log; do
    OUT=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/$page")
    SZ=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
    ERR=$(printf '%s' "$OUT" | grep -c -E 'Fatal error|Parse error|Uncaught' || true)
    echo "  /ui/mihomo/$page  ${SZ} 字节  报错: ${ERR}"
done
echo
echo "########## 设置页开关数量（服务端渲染出来的字段数） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | grep -c 'id="mihomo\.' | sed 's/^/  字段: /'
rm -f "$JAR"
