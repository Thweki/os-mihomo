#!/bin/sh
# 看清用户那两行策略的真实字段，以及 config.yaml 里的受管区块
set -u
echo "########## 1. 策略表两行的字段 ##########"
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
echo "########## 2. config.yaml 的受管区块 ##########"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' /usr/local/etc/mihomo/config.yaml | sed 's/^/  /'
echo "  （无输出 = 文件里没有受管区块）"

echo
echo "########## 3. 模板里有没有同一份 ##########"
grep -c 'os-mihomo:policy-routing' /usr/local/etc/mihomo/sub/template_config.yaml | sed 's/^/  /'

echo
echo "########## 4. rules: 段开头 ##########"
awk '/^rules:/{f=1} f{print; n++} n>=8{exit}' /usr/local/etc/mihomo/config.yaml | sed 's/^/  /'

echo
echo "########## 5. 分组名 ##########"
sed -n '/^proxy-groups:/,/^rules:/p' /usr/local/etc/mihomo/config.yaml | grep -o "name: .*" | sed 's/^/  /'
