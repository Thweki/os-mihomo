#!/bin/sh
# 代理组扫描结果 vs 配置里的实际分组
set -u
CFG=/usr/local/etc/mihomo/config.yaml
BASE=https://127.0.0.1
JAR=/tmp/grp_jar.txt
rm -f "$JAR"

echo "########## 1. config.yaml 里 proxy-groups 段的样子（前 12 行） ##########"
awk '/^proxy-groups:/{f=1;print;next} f{print; n++} n>=11{exit}' "$CFG" | sed 's/^/  /'

echo
echo "########## 2. 段内 name: 出现次数 ##########"
awk '/^proxy-groups:/{f=1;next} f&&/^[a-z]/{exit} f{print}' "$CFG" | grep -c 'name:' | sed 's/^/  /'

echo
echo "########## 3. options 接口返回的代理组 ##########"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/options" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  interfaces:', [i['value'] for i in d.get('interfaces',[])])
print('  targets   :', [t['value'] for t in d.get('targets',[])])
"
rm -f "$JAR"
