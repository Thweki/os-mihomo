#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# CRUD + 应用 + 状态（写 config.yaml 与订阅模板；mihomo -t 校验）
set -u
BASE=https://127.0.0.1
JAR=/tmp/routing_jar2.txt
CFG=/usr/local/etc/mihomo/config.yaml
TPL=/usr/local/etc/mihomo/sub/template_config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)

GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 0. 表格 id（页面里实际渲染的） ##########"
GET /ui/mihomo/routing | grep -o 'id="policy_rule"' | sort -u | sed 's/^/  /'

echo
echo "########## 1. 通过接口新增一行（lan → 🌍选择节点，仅国外） ##########"
ADD=$(POST /api/mihomo/routing/add_rule '{"mihomo":{"enabled":"1","interface":"lan","source":"","scope":"foreign","target":"🌍选择节点","firewall":"manual","descr":"lan 走默认选择组"}}')
echo "  add: $ADD"
UUID=$(printf '%s' "$ADD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)
echo "  uuid: $UUID"

echo
echo "########## 2. search（表格数据源） ##########"
GET /api/mihomo/routing/search_rule | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  rowCount:', d.get('rowCount'))
for r in d.get('rows',[]):
    print('   ', {k: r.get(k) for k in ('uuid','enabled','interface','scope','target','firewall')})
"

echo
echo "########## 3. preview（应生成 2 条 AND 规则） ##########"
GET /api/mihomo/routing/preview | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('rules',[]): print('  -', r)
print('  warnings:', d.get('warnings'))
"

echo
echo "########## 4. 应用（configd → policy_apply.php） ##########"
echo "  --- 应用前 hash ---"
echo "    config.yaml:   $(sha256 -q "$CFG")"
echo "    template.yaml: $(sha256 -q "$TPL" 2>/dev/null || echo 'n/a')"
POST /api/mihomo/routing/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status  :', d.get('status'))
for m in d.get('messages',[]): print('  msg     :', m)
if d.get('diff'): print('  diff:\n' + d['diff'])
"

echo
echo "########## 5. 应用后：受管区块内容 ##########"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /'
echo "  --- 模板里同样应有 ---"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$TPL" 2>/dev/null | sed 's/^/    /' || echo "    (模板无)"
echo "  --- 其它内容是否原样（对比备份） ---"
BAK=$(ls -1t /usr/local/etc/mihomo/config.yaml.bak.* | head -1)
echo "    备份: $BAK"
grep -v 'os-mihomo:policy-routing' "$BAK" | grep -v 'SRC-IP-CIDR,192.168.1.0/24' > /tmp/rt_before.txt
grep -v 'os-mihomo:policy-routing' "$CFG" | grep -v 'SRC-IP-CIDR,192.168.1.0/24' > /tmp/rt_after.txt
if diff /tmp/rt_before.txt /tmp/rt_after.txt > /tmp/rt_diff.txt 2>&1; then
    echo "    除受管块外完全一致 OK"
else
    echo "    差异："
    head -10 /tmp/rt_diff.txt | sed 's/^/      /'
fi
rm -f /tmp/rt_before.txt /tmp/rt_after.txt /tmp/rt_diff.txt

echo
echo "########## 6. 幂等：再应用一次 ##########"
H1=$(sha256 -q "$CFG")
POST /api/mihomo/routing/apply '{}' | python3 -c "import json,sys; d=json.load(sys.stdin); print('  status:', d.get('status'), '|', ' '.join(d.get('messages',[])))"
H2=$(sha256 -q "$CFG")
[ "$H1" = "$H2" ] && echo "  第二次应用字节不变 OK" || echo "  **第二次应用改变了文件**"

echo
echo "########## 7. status（只读状态表） ##########"
GET /api/mihomo/routing/status | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  tun_enabled:', d.get('tun_enabled'), '| gateway:', d.get('gateway'), '| firewall_rule:', d.get('firewall_rule'))
for r in d.get('rows',[]):
    print('   ', r.get('interface'), r.get('source'), '->', r.get('target'), '|', r.get('state'), '|', r.get('note'))
"
rm -f "$JAR"
