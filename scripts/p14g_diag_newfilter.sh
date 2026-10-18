#!/bin/sh
# 取证：新防火墙模块的规则存放在哪、如何排序
set -u
echo "########## 1. 默认放行规则所在的父节点（config.xml 395-410 行） ##########"
sed -n '395,412p' /conf/config.xml | sed 's/^/  /'

echo
echo "########## 2. 该节点的完整路径 ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()

def walk(node, path=''):
    for child in node:
        p = path + '/' + child.tag
        if child.tag == 'description' and 'Default allow' in (child.text or ''):
            print('  规则所在的 filter 节点路径:', p.rsplit('/', 1)[0])
            return True
        if walk(child, p):
            return True
    return False
walk(r)

# 统计两个位置的规则数
legacy = r.find('filter')
print('  根 <filter> 下 rule 数:', 0 if legacy is None else len(legacy.findall('rule')))
for node in r.iter('Firewall'):
    f = node.find('filter')
    if f is not None:
        print('  <OPNsense><Firewall><filter> 下 rule 数:', len(f.findall('rule')))
PY

echo
echo "########## 3. Filter 模型（新）是否有 rule + sequence ##########"
M=/usr/local/opnsense/mvc/app/models/OPNsense/Firewall/Filter.xml
grep -n '<rule type\|<sequence\|<description\|<descr\|<gateway\|<interface type\|<type type' $M | head -12 | sed 's/^/  /'

echo
echo "########## 4. moveRuleBefore 的实现（排序怎么算） ##########"
grep -n -A18 'function moveRuleBeforeAction' /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/Api/FilterController.php | head -26 | sed 's/^/  /'

echo
echo "########## 5. 模型里 sequence 的默认值与生成逻辑 ##########"
grep -rn 'sequence' /usr/local/opnsense/mvc/app/models/OPNsense/Firewall/Filter.php 2>/dev/null | head -10 | sed 's/^/  /'
grep -rn 'DNatSequenceField\|SequenceField' /usr/local/opnsense/mvc/app/models/OPNsense/Firewall/Filter.xml 2>/dev/null | head -3 | sed 's/^/  /'
