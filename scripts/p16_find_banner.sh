#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 定位路由策略页上那个红色横幅（“启动服务前请先确认以下风险”）的来源
set -u
BASE=https://127.0.0.1
JAR=/tmp/p16_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p16-routing.html
curl -sk -b "$JAR" "$BASE/ui/mihomo/" -o /tmp/p16-index.html
echo "  抓取大小: routing=$(wc -c < /tmp/p16-routing.html) index=$(wc -c < /tmp/p16-index.html)"

python3 - <<'PY'
for name in ('/tmp/p16-routing.html', '/tmp/p16-index.html'):
    t = open(name, encoding='utf-8', errors='ignore').read()
    print()
    print('##########', name, '| 长度', len(t), '##########')
    for kw in ('风险', 'alert-danger', 'confirm'):
        i = t.find(kw)
        print('  ', kw, '位置:', i)
        if i > 0 and kw == '风险':
            print(t[max(0, i - 1500):i + 500])
PY
rm -f "$JAR"
