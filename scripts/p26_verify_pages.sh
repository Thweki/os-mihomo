#!/bin/sh
# 验收：三处界面文案（体检横幅标题、订阅页警告、路由页空状态）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p26_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

for page in "" "routing" "settings" "subscription" "log"; do
    url="$BASE/ui/mihomo/$page"
    out=/tmp/p26-$(echo "${page:-index}").html
    curl -sk -b "$JAR" -o "$out" "$url"
    printf '  %-14s %8s 字节  ' "${page:-index}" "$(wc -c < "$out" | tr -d ' ')"
    python3 - "$out" <<'PY'
import sys, re
t = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
hits = []
for kw in ('Fix these before starting', 'Check these before starting',
           '还没有绑定接口', '更新订阅会用订阅模板整份重写', '外部控制器未设置密钥（仅监听本机）',
           '启动服务前请先修正', '启动服务前请先确认以下事项'):
    if kw in t:
        hits.append(kw)
err = 'PHP Error' in t or 'Fatal error' in t
print('PHP 报错:', '有 ❌' if err else '无 ✅', '| 命中文案:', ', '.join(hits) if hits else '（无）')
PY
done
rm -f "$JAR"
