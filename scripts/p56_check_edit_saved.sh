#!/bin/sh
set -u
BASE=https://127.0.0.1
JAR=/tmp/p56_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 策略行现在的内容（浏览器里改过之后） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/search_rule/?rowCount=10&current=1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('rows',[]):
    print('  interface=%s scope=%s target=%s firewall=%s descr=%r enabled=%s' % (
        r.get('interface'), r.get('scope'), r.get('target'), r.get('firewall'), r.get('descr'), r.get('enabled')))
"
echo
echo "########## config.xml 里的那一行 ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
node = r.find('OPNsense/mihomo/policyRouting')
for rule in (node.findall('rule') if node is not None else []):
    print('  ', {c.tag: (c.text or '') for c in rule})
PY
