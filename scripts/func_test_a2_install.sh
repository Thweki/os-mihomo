#!/bin/sh
# 功能测试 · A2：用合法的 staging 路径装入真实节点配置 → 应用设置 → 应用策略 → 重启
set -u
BASE=https://127.0.0.1
JAR=/tmp/func_jar2.txt
PASS='${OPN_PW}'
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 装入真实节点配置（合法 staging 路径） ##########"
STAGE=$(mktemp /tmp/mihomo-XXXXXX)
cp /tmp/mihomo-test/config-new.yaml "$STAGE"
chmod 0600 "$STAGE"
echo "  staging: $STAGE ($(wc -l < "$STAGE" | tr -d ' ') 行)"
configctl mihomo config-install "$STAGE" 2>&1 | sed 's/^/  /' | head -5
echo "  落盘后：$(grep -c . "$CFG") 行，proxies 条目 $(grep -c '^\s*- { name:' "$CFG")"
echo "  备份：$(ls -1t /usr/local/etc/mihomo/config.yaml.bak.* | head -1)"

echo
echo "########## 2. 应用设置（受管键：allow-lan=false / 控制器回环 / DNS 回环 / TUN 关） ##########"
POST /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
grep -nE '^(allow-lan|bind-address|external-controller|mixed-port):|^(tun|dns):|^\s+(enable|listen):' "$CFG" | head -14 | sed 's/^/    /'

echo
echo "########## 3. 策略行：lan → 🇺🇸 United States（仅国外） ##########"
UUID=$(GET /api/mihomo/routing/search_rule | python3 -c "import json,sys; print(json.load(sys.stdin)['rows'][0]['uuid'])")
POST "/api/mihomo/routing/set_rule/$UUID" '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"manual","descr":"lan 走美国组（测试）"}}' | sed 's/^/  /'

echo
echo "########## 4. 预览（可选分组里应能看到真实分组名） ##########"
GET /api/mihomo/routing/options | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  targets:', [t['value'] for t in d.get('targets',[])][:12])
"
GET /api/mihomo/routing/preview | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('rules',[]): print('  -', r)
print('  warnings:', d.get('warnings'))
"

echo
echo "########## 5. 应用策略 ##########"
POST /api/mihomo/routing/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
if d.get('message'): print('  message:', str(d['message'])[:400])
"
echo "  --- 受管块 ---"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /'

echo
echo "########## 6. 重启并确认内核加载 ##########"
POST /api/mihomo/service/restart '{}' >/dev/null
sleep 15
service mihomo status 2>&1 | head -1 | sed 's/^/  /'
SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print(m.group(1).strip().strip(chr(34)).strip(chr(39)) if m else '')
")
curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/rules | python3 -c "
import json,sys
d=json.load(sys.stdin); rules=d.get('rules',[])
print('  规则总数:', len(rules))
for r in rules[:5]:
    print('   ', r.get('type'), r.get('payload'), '->', r.get('proxy'))
" 2>/dev/null || echo "  (读规则失败)"
echo "  代理组数量:"
curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/proxies | python3 -c "
import json,sys
d=json.load(sys.stdin).get('proxies',{})
names=[k for k,v in d.items() if v.get('type') in ('Selector','URLTest','Fallback','LoadBalance')]
print('   ', len(names), '个:', names[:10])
" 2>/dev/null || echo "  (读分组失败)"
rm -f "$JAR"
