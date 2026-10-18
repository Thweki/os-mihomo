#!/bin/sh
# 策略行模型 XML 原文 + 不同 payload 的返回 + PHP 错误日志
set -u
BASE=https://127.0.0.1
JAR=/tmp/p22_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. Mihomo.xml 里 policyRouting 原文 ##########"
sed -n '/<policyRouting/,/<\/policyRouting>/p' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml | head -60 | sed 's/^/  /'

echo
echo "########## 2. 不同 payload ##########"
for P in '{"rule":{"interface":"lan","target":"US-EXIT"}}' \
         '{"rule":{"enabled":"1","interface":"lan","scope":"foreign","target":"US-EXIT","firewall":"create"}}' \
         '{"rule":{"enabled":"1","interface":"lan","scope":"foreign","target":"US-EXIT","firewall":"0","source":"","descr":"t"}}'; do
    echo "  payload: $P"
    printf '    → '; POST /api/mihomo/routing/add_rule "$P"; echo
done

echo
echo "########## 3. 现有模型内容 ##########"
python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
n = r.find('OPNsense/mihomo/policyRouting')
print('  节点:', 'none' if n is None else ET.tostring(n, encoding='unicode')[:600])
"

echo
echo "########## 4. PHP 错误日志尾部 ##########"
tail -6 /var/lib/php/tmp/PHP_errors.log 2>/dev/null | sed 's/^/  /'
rm -f "$JAR"
