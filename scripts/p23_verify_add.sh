#!/bin/sh
# 用正确的 payload 键（mihomo + firewall=manual/auto）验证新增行；再验证空状态提示
set -u
BASE=https://127.0.0.1
JAR=/tmp/p23_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 新增一行（正确的键名与选项值） ##########"
POST /api/mihomo/routing/add_rule '{"mihomo":{"enabled":"1","interface":"lan","scope":"foreign","target":"US-EXIT","firewall":"manual","descr":"临时测试行"}}'; echo

echo
echo "########## 2. 表格数据 ##########"
GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  rows:', len(d.get('rows',[])), '| total:', d.get('total'))
for r in d.get('rows',[]):
    print('   ', {k:r.get(k) for k in ('uuid','enabled','interface','scope','target','firewall','descr','state')})
"

echo
echo "########## 3. 空状态提示的中文（页面 + .mo） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p23-routing.html
python3 - <<'PY'
t = open('/tmp/p23-routing.html', encoding='utf-8').read()
i = t.find('policyEmptyHint')
seg = t[i - 40:i + 400].replace('\n', ' ')
import re
seg = re.sub(r'\s+', ' ', seg)
print('  ' + seg[:300])
PY
python3 - <<'PY'
import struct, io
p = '/usr/local/share/opnsense/locale/zh_CN/LC_MESSAGES/OPNsense.mo'
data = open(p, 'rb').read()
for kw in ('还没有绑定接口', '启动服务前请先修正以下问题', '外部控制器未设置密钥（仅监听本机）'):
    print('  .mo 含 %-14s : %s' % (kw, kw.encode('utf-8') in data))
PY

echo
echo "########## 4. 删除测试行 ##########"
UUID=$(GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=d.get('rows',[])
print(rows[0]['uuid'] if rows else '')")
if [ -n "$UUID" ]; then
    printf '  删除 %s → ' "$UUID"; POST "/api/mihomo/routing/del_rule/$UUID" '{}'; echo
fi
GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  剩余行:', len(d.get('rows',[])))
"
echo "  同步: "; POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('   status:', d.get('status'))
for m in d.get('messages',[]): print('   msg:', m)
"
rm -f "$JAR"
