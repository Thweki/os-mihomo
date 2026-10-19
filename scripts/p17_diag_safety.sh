#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 诊断：dashboard 体检横幅为什么只剩标题（items 内容）+ 路由表数据
set -u
BASE=https://127.0.0.1
JAR=/tmp/p17_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 1. /api/mihomo/service/safety 原始返回 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | python3 -m json.tool --no-ensure-ascii | sed 's/^/  /' | head -60

echo
echo "########## 2. 路由表数据（search_rule） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/search_rule?rowCount=20" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  rows:', len(d.get('rows',[])), '| total:', d.get('total'))
for r in d.get('rows',[]):
    print('  ', {k:r.get(k) for k in ('uuid','enabled','interface','scope','target','firewall','descr','state')})
"

echo
echo "########## 3. service/status ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/status" | python3 -m json.tool --no-ensure-ascii | sed 's/^/  /' | head -20
rm -f "$JAR"
