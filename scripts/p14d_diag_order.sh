#!/bin/sh
# 诊断：lan 接口上各规则的 sequence 与命中计数（判断谁先生效）
set -u
echo "########## 1. config.xml 里 lan 接口规则的 sequence ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
for rule in r.find('filter').findall('rule'):
    if (rule.findtext('interface') or '') != 'lan':
        continue
    print('  seq=%-8s descr=%-40s gw=%s' % (
        rule.findtext('sequence') or '(none)',
        (rule.findtext('descr') or '')[:40],
        rule.findtext('gateway') or '—'))
PY

echo
echo "########## 2. pf 里 igb0 规则的评估/命中计数（看我们的规则有没有被评估） ##########"
pfctl -vvsr 2>/dev/null | grep -A3 'db8330058668e6ef26e238953f13ae6a\|1767226427009c251ff1a9a490d81709' | sed 's/^/  /' | head -20

echo
echo "########## 3. 默认放行规则的计数 ##########"
pfctl -vvsr 2>/dev/null | grep -A3 'cd0e458a-88ec-4752-b73b-2b9814b3a8e6' | sed 's/^/  /' | head -8

echo
echo "########## 4. 现有状态里有没有 route-to tun_mihomo 的会话 ##########"
pfctl -ss 2>/dev/null | grep -c 'tun_mihomo' | sed 's/^/  含 tun_mihomo 的状态数: /'
pfctl -ss 2>/dev/null | grep 'tun_mihomo' | head -3 | sed 's/^/    /'
