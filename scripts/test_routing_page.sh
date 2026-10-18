#!/bin/sh
# 路由策略页 + 接口验证（只写插件自己的文件；不动网络配置）
set -u
BASE=https://127.0.0.1
JAR=/tmp/routing_jar.txt
PASS='${OPN_PW}'
CFG=/usr/local/etc/mihomo/config.yaml
TPL=/usr/local/etc/mihomo/sub/template_config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

GET() { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 页面与菜单 ##########"
printf '  /ui/mihomo/routing          %s\n' "$(curl -sk -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/ui/mihomo/routing")"
printf '  /ui/mihomo                  %s\n' "$(curl -sk -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/ui/mihomo")"
echo "  菜单里的入口："
GET /ui/mihomo | grep -o 'href="/ui/mihomo[^"]*"' | sort -u | sed 's/^/    /'
echo "  页面里的关键元素："
GET /ui/mihomo/routing | grep -o 'grid-policy_rule\|Policy Routing\|policyStatusBody\|applyPolicyAct' | sort -u | sed 's/^/    /'

echo
echo "########## 2. options（接口 + 代理组） ##########"
GET /api/mihomo/routing/options | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  interfaces:', [i['label'] for i in d.get('interfaces',[])])
print('  targets   :', [t['value'] for t in d.get('targets',[])][:8])
print('  tun_enabled:', d.get('tun_enabled'), '| auto_route:', d.get('auto_route'))
"

echo
echo "########## 3. preview（当前无策略行） ##########"
GET /api/mihomo/routing/preview | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status  :', d.get('status'))
print('  rules   :', d.get('rules'))
print('  warnings:', d.get('warnings'))
"
