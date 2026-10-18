#!/bin/sh
# 功能测试 · A：装入真实节点配置（脱敏）→ 应用设置 → 应用策略 → 重启服务
set -u
BASE=https://127.0.0.1
JAR=/tmp/func_jar.txt
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

echo "########## 0. 测试前的安全指纹（用于事后比对） ##########"
PF0=$(pfctl -sr 2>/dev/null | sha256 -q)
NAT0=$(pfctl -sn 2>/dev/null | sha256 -q)
RT0=$(netstat -rn 2>/dev/null | sha256 -q)
UB0=$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)
echo "  pf=$PF0"
echo "  nat=$NAT0"
echo "  route=$RT0"
echo "  unbound=$UB0"
echo "  进 mihomo 的接口（应只有测试用的 lan）："
grep -c '192\.168\.2\.0/24' "$CFG" 2>/dev/null | sed 's/^/    config.yaml 里 192.168.2.0\/24 出现次数（应为 0）: /'

echo
echo "########## 1. 装入脱敏后的真实节点配置（走插件的 configd 通道：校验+备份+落盘） ##########"
chmod 0600 /tmp/mihomo-test/config-new.yaml
configctl mihomo config-install /tmp/mihomo-test/config-new.yaml 2>&1 | sed 's/^/  /' | head -5
echo "  新配置：$(grep -c . "$CFG") 行 / proxies: $(grep -c '^\s*- { name:' "$CFG") 个"

echo
echo "########## 2. 应用「设置」（写入受管键：allow-lan=false / 控制器 / DNS 回环 / TUN 关闭） ##########"
POST /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  受管键现值："
grep -nE '^(allow-lan|bind-address|external-controller|dns):|^tun:|^\s+(enable|listen):' "$CFG" | head -12 | sed 's/^/    /'

echo
echo "########## 3. 策略行改成真实存在的分组（🇺🇸 United States） ##########"
UUID=$(GET /api/mihomo/routing/search_rule | python3 -c "import json,sys; print(json.load(sys.stdin)['rows'][0]['uuid'])")
POST "/api/mihomo/routing/set_rule/$UUID" '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🇺🇸 United States","firewall":"manual","descr":"lan 走美国组（测试）"}}' | sed 's/^/  /'
echo

echo "########## 4. 应用策略 ##########"
POST /api/mihomo/routing/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- 受管块 ---"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /'

echo
echo "########## 5. 重启服务加载新配置 ##########"
POST /api/mihomo/service/restart '{}' >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'
echo "  --- 控制器 ---"
sleep 3
GET /api/mihomo/dashboard/overview | head -c 260; echo

echo
echo "########## 6. 规则是否真的加载进内核（直查控制器 /rules） ##########"
SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)$',t,re.M)
print(m.group(1).strip().strip(chr(34)).strip(chr(39)) if m else '')
")
curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/rules | python3 -c "
import json,sys
d=json.load(sys.stdin)
rules=d.get('rules',[])
print('  规则总数:', len(rules))
for r in rules[:6]:
    print('   ', r.get('type'), r.get('payload'), '->', r.get('proxy'), '|', r.get('size'))
print('   ...')
print('  最后一条:', rules[-1].get('type'), rules[-1].get('payload'), '->', rules[-1].get('proxy') if rules else '')
" 2>/dev/null || echo "  (读取规则失败)"

echo
echo "########## 7. 监听面（必须只有 127.0.0.1） ##########"
sockstat -4 -l 2>/dev/null | egrep 'mihomo' | sed 's/^/  /'
rm -f "$JAR"
