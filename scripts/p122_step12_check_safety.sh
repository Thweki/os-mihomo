#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 安全体检横幅是否包含"策略路由已启用"的告警
set -u
BASE=https://127.0.0.1
JAR=/tmp/p122_safety_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${PASS}&$N=$V" "$BASE/index.php"
echo "=== 安全体检（/api/mihomo/service/safety）==="
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  总体状态:', d.get('status'))
for i in d.get('items', []):
    print('   [%s] %s' % (i.get('level'), i.get('title')))
    print('        %s' % (i.get('detail') or '')[:160])
"
rm -f "$JAR"
