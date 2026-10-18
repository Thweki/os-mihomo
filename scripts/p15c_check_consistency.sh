#!/bin/sh
# 检查：换配置后，策略行/受管块/规则是否还一致
set -u
CFG=/usr/local/etc/mihomo/config.yaml

echo "########## 1. 服务与配置 ##########"
service mihomo status 2>&1 | head -1 | sed 's/^/  /'
echo "  config.yaml: $(grep -c . "$CFG") 行 / proxy-groups: $(awk '/^proxy-groups:/{f=1;next} f&&/^[a-z]/{exit} f{print}' "$CFG" | grep -c 'name:')"
echo "  --- 受管块是否还在 ---"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /' || true

echo
echo "########## 2. 策略行（模型） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
node = r.find('OPNsense/mihomo/policyRouting')
if node is None:
    print('  (无)')
else:
    for rule in node.findall('rule'):
        print('  ', {c.tag: (c.text or '') for c in rule})
PY

echo
echo "########## 3. 分组名（供对照） ##########"
awk '/^proxy-groups:/{f=1;next} f&&/^[a-z]/{exit} f{print}' "$CFG" | grep -o 'name: .*' | sed 's/^/  /'

echo
echo "########## 4. mihomo 内核里的规则（前 4 条） ##########"
SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print(m.group(1).strip().strip(chr(34)).strip(chr(39)) if m else '')")
curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/rules 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); rules=d.get('rules',[])
print('  规则总数:', len(rules))
for r in rules[:4]:
    print('   ', r.get('type'), r.get('payload'), '->', r.get('proxy'))
" 2>/dev/null || echo "  (读取失败)"

echo
echo "########## 5. 校验当前配置 ##########"
configctl mihomo config-current 2>&1 | tail -2 | sed 's/^/  /'
