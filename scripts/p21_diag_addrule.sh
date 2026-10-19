#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 抓完整响应：新增策略行为什么失败
set -u
BASE=https://127.0.0.1
JAR=/tmp/p21_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 模型字段（策略行） ##########"
python3 - <<'PY'
import re, io
t = io.open('/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml', encoding='utf-8').read()
i = t.find('<policyRouting')
seg = t[i:i+2600]
for m in re.finditer(r'<(\w+) type="(\w+)"[^>]*>(.*?)</\1>', seg, re.S):
    name, typ, body = m.group(1), m.group(2), m.group(3)
    dflt = re.search(r'<Default>([^<]*)</Default>', body)
    opts = re.findall(r'<(\w+)>([^<]*)</\1>', re.search(r'<OptionValues>(.*?)</OptionValues>', body, re.S).group(1)) if '<OptionValues>' in body else []
    print('  %-12s %-16s default=%-8s %s' % (name, typ, dflt.group(1) if dflt else '-', ['%s=%s' % o for o in opts]))
PY

echo
echo "########## 2. 对话框里各字段的 name（前端提交的名字） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p21-routing.html
python3 - <<'PY'
import re
t = open('/tmp/p21-routing.html', encoding='utf-8').read()
for m in re.finditer(r'id="(mihomo\.[\w.]+)"', t):
    print('  ', m.group(1))
PY

echo
echo "########## 3. 新增（完整响应） ##########"
POST /api/mihomo/routing/add_rule '{"rule":{"enabled":"1","interface":"lan","scope":"foreign","target":"US-EXIT","firewall":"0","descr":"临时测试行"}}'; echo
rm -f "$JAR"
