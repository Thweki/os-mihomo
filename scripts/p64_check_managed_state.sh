#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
set -u
BASE=https://127.0.0.1
JAR=/tmp/p64_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 模型里「允许写入」的项（用户当前的选择） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/get" | python3 -c "
import json,sys
d=json.load(sys.stdin)
m=d.get('mihomo',{})
print('  managed =', repr(m.get('managed')))
"
echo
echo "########## config.xml 里的 mihomo 节点时间戳（看设置什么时候被保存过） ##########"
ls -lT /conf/config.xml | sed 's/^/  /'
grep -o '<managed>[^<]*</managed>' /conf/config.xml | sed 's/^/  /'
echo
echo "########## 对照表 19 行里哪些标了不修改 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | python3 -c "
import json,sys
d=json.load(sys.stdin)
leave=[r['label'] for r in d.get('rows',[]) if r.get('managed') is False]
own=[r['label'] for r in d.get('rows',[]) if r.get('managed') is True]
print('  不修改（插件不写）:', '、'.join(leave))
print('  交给插件写    :', '、'.join(own) or '(无)')
"
rm -f "$JAR"
