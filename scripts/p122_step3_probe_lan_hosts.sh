#!/bin/sh
# P12-2 · 步骤 3：LAN 段上有无主机 + OPNsense 可用 API/模型
set -u
echo "########## 1. LAN 段（192.168.1.0/24）上的邻居 ##########"
arp -an 2>/dev/null | grep '192.168.1.' | sed 's/^/  /' || echo "  (ARP 表里没有 192.168.1.x)"
echo "  --- igb0 收发计数（看是否有流量） ---"
netstat -I igb0 -b 2>/dev/null | head -3 | sed 's/^/  /'

echo
echo "########## 2. 其他网段（对照） ##########"
arp -an 2>/dev/null | awk '{print $2}' | tr -d '()' | sed 's/\.[0-9]*$//' | sort | uniq -c | sed 's/^/  /'

echo
echo "########## 3. 网关字段的核心解析位置 ##########"
grep -rln 'gateway_item' /usr/local/etc/inc/ /usr/local/opnsense/mvc/app/models/ 2>/dev/null | head -5
echo "--- 网关条目的字段名 ---"
grep -rn "'monitor_disable'\|'defaultgw'\|'ipprotocol'" /usr/local/etc/inc/*.inc 2>/dev/null | head -6

echo
echo "########## 4. 可用 MVC 模型（找 nat / firewall） ##########"
ls -1 /usr/local/opnsense/mvc/app/models/OPNsense/ 2>/dev/null | tr '\n' ' '
echo
ls -1 /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/Api/ 2>/dev/null | tr '\n' ' '

echo
echo "########## 5. 防火墙规则 API 的动作名（若可用则用它建规则） ##########"
grep -o '^\[[a-z.]*\]' /usr/local/opnsense/service/conf/actions.d/actions_filter.conf 2>/dev/null | head -10 | tr '\n' ' '
echo
grep -rn 'function .*Action' /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/Api/FilterController.php 2>/dev/null | head -12 | sed 's/^/  /'

echo
echo "########## 6. 当前策略行（模型） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
node = r.find('OPNsense/mihomo/policyRouting')
if node is None:
    print('  (无策略行)')
else:
    for rule in node.findall('rule'):
        print('  ', {c.tag: (c.text or '') for c in rule})
PY
