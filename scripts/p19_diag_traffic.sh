#!/bin/sh
# 细看 overview 与 traffic（traffic 只返回 errorMessage）
set -u
BASE=https://127.0.0.1
JAR=/tmp/p19_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## overview 全文 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/overview" | python3 -m json.tool --no-ensure-ascii | head -40 | sed 's/^/  /'

echo
echo "########## traffic 全文 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/dashboard/traffic" | python3 -m json.tool --no-ensure-ascii | head -20 | sed 's/^/  /'

echo
echo "########## 直接问内核（对照组） ##########"
SECRET=$(python3 -c "
import re,io
t=io.open('/usr/local/etc/mihomo/config.yaml',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)$',t,re.M)
print((m.group(1).strip().strip('\"').strip(chr(39))) if m else '')")
echo "  secret = '${SECRET}'（空=无鉴权）"
echo -n "  /traffic: "; curl -s -m 5 http://127.0.0.1:9090/traffic -H "Authorization: Bearer $SECRET" | head -c 200; echo
echo -n "  /version: "; curl -s -m 5 http://127.0.0.1:9090/version -H "Authorization: Bearer $SECRET" | head -c 160; echo
echo -n "  /memory:  "; curl -s -m 5 http://127.0.0.1:9090/memory -H "Authorization: Bearer $SECRET" | head -c 160; echo
rm -f "$JAR"
