#!/bin/sh
# 诊断：国旗 emoji 到底是哪一层被改写的
set -u
CFG=/conf/config.xml
BASE=https://127.0.0.1
JAR=/tmp/emoji_jar.txt
rm -f "$JAR"

echo "########## 1. config.xml 里存的值（模型侧） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
m = r.find('OPNsense/mihomo/policyRouting/rule')
if m is None:
    print('  (没有策略行)')
else:
    t = m.findtext('target') or ''
    print('  target repr:', repr(t))
    print('  码点:', [hex(ord(c)) for c in t[:12]])
PY

echo
echo "########## 2. PHP 自己序列化是否正确 ##########"
php -r '$s="🇺🇸 United States"; echo "  json: ", json_encode($s, JSON_UNESCAPED_UNICODE), "\n";'

echo
echo "########## 3. API 返回的原始字节（status / search） ##########"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" "$BASE/index.php"
echo "--- /search_rule 原始输出（前 300 字节）---"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/search_rule" | head -c 300 | sed 's/^/    /'
echo
echo "--- /status 原始输出（target 部分）---"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/status" | python3 -c "
import sys, json
raw = sys.stdin.read()
i = raw.find('\"target\"')
print('    raw slice:', raw[max(0,i-10):i+40])
try:
    d = json.loads(raw)
    for r in d.get('rows', []):
        print('    parsed target:', repr(r.get('target')), [hex(ord(c)) for c in (r.get('target') or '')[:12]])
except Exception as e:
    print('    parse error:', e)
"
rm -f "$JAR"
