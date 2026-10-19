#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
set -u
BASE=https://127.0.0.1
JAR=/tmp/p49_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## /api/mihomo/routing/options ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/options" | python3 -m json.tool | head -50

echo
echo "########## config.xml 里的 interfaces 节点（只列 ipaddr/subnet/if） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
node = r.find('interfaces')
if node is None:
    print('  没有 interfaces 节点')
else:
    for iface in node:
        print('  %-8s if=%-10s ipaddr=%-14s subnet=%-4s descr=%s' % (
            iface.tag, iface.findtext('if') or '-', iface.findtext('ipaddr') or '-',
            iface.findtext('subnet') or '-', iface.findtext('descr') or '-'))
PY
