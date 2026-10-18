#!/bin/sh
# 验证：① 体检横幅在“只有 info”时整块消失 ② 路由页空状态提示 ③ 新增行能在表格里出现
set -u
BASE=https://127.0.0.1
JAR=/tmp/p20_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 体检：现在最坏级别是什么（info => 横幅不显示） ##########"
GET /api/mihomo/service/safety | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for i in d.get('items',[]):
    print('   [%-7s] %s' % (i.get('level'), i.get('title')))
"

echo
echo "########## 2. 路由页空状态提示（中文是否就位） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p20-routing.html
python3 - <<'PY'
t = open('/tmp/p20-routing.html', encoding='utf-8').read()
i = t.find('policyEmptyHint')
print('  policyEmptyHint 位置:', i)
if i > 0:
    print('  ' + t[i-60:i+320].replace('\n', ' '))
PY
echo "  .mo 里的中文:"
grep -c '还没有绑定接口' /usr/local/share/opnsense/locale/zh_CN/LC_MESSAGES/OPNsense.mo 2>/dev/null | sed 's/^/    出现次数: /'

echo
echo "########## 3. 新增一行（防火墙规则=不创建，绝不动网络）→ 表格应能看到 ##########"
POST /api/mihomo/routing/add_rule '{"rule":{"enabled":"1","interface":"lan","scope":"foreign","target":"US-EXIT","firewall":"0","descr":"临时测试行"}}' | head -c 200; echo
GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  rows:', len(d.get('rows',[])), '| total:', d.get('total'))
for r in d.get('rows',[]):
    print('   ', {k:r.get(k) for k in ('uuid','enabled','interface','scope','target','firewall','descr')})
"

echo
echo "########## 4. 删除测试行 + 同步（应 nothing changed） ##########"
UUID=$(GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=d.get('rows',[])
print(rows[0]['uuid'] if rows else '')")
echo "  uuid: $UUID"
if [ -n "$UUID" ]; then
    POST "/api/mihomo/routing/del_rule/$UUID" '{}' | head -c 120; echo
fi
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  netapply:', d.get('status'))
for m in d.get('messages',[]): print('   msg:', m)
"
GET "/api/mihomo/routing/search_rule?rowCount=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  剩余行:', len(d.get('rows',[])))
"

echo
echo "########## 5. 安全 ##########"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo "  pf route-to(tun_mihomo): $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' || true)"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
