#!/bin/sh
# 取证：FilterSequenceField 如何赋值 + 新模块规则的展开顺序
set -u
echo "########## 1. FilterSequenceField 实现 ##########"
F=$(find /usr/local/opnsense/mvc/app/models/OPNsense/Firewall -name 'FilterSequenceField.php' | head -1)
echo "  $F"
grep -n 'function \|sequence\|min\|max' "$F" | head -25 | sed 's/^/  /'

echo
echo "########## 2. 新模块里 lan 的规则与它们的 sequence ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('OPNsense/Firewall/Filter')
if flt is None:
    print('  (没有新模块节点)')
else:
    for rule in flt.findall('rules/rule'):
        print('  seq=%-6s iface=%-8s action=%-5s gw=%-12s %s' % (
            rule.findtext('sequence') or '-', rule.findtext('interface') or '-',
            rule.findtext('action') or '-', rule.findtext('gateway') or '-',
            (rule.findtext('description') or '')[:40]))
PY

echo
echo "########## 3. 旧版根 <filter> 里的规则 ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('filter')
for rule in ([] if flt is None else flt.findall('rule')):
    print('  iface=%-8s gw=%-12s %s' % (
        rule.findtext('interface') or '-', rule.findtext('gateway') or '-',
        (rule.findtext('descr') or rule.findtext('description') or '')[:40]))
PY

echo
echo "########## 4. 生成器如何合并两处规则（谁先谁后） ##########"
grep -rn "OPNsense/Firewall\|Firewall\\\\Filter\|OPNsense\\\\Firewall" /usr/local/etc/inc/filter.inc 2>/dev/null | head -6 | sed 's/^/  /'
grep -rn 'legacy\|backwards\|filter.*rule' /usr/local/etc/inc/filter.lib.inc 2>/dev/null | head -6 | sed 's/^/  /'
