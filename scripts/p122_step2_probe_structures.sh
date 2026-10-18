#!/bin/sh
# P12-2 · 步骤 2：config.xml 里「网关」「带网关的防火墙规则」的准确结构
set -u
CFG=/conf/config.xml

echo "########## 1. 核心如何解析 gateway_item ##########"
grep -rn "gateway_item\['" /usr/local/etc/inc/*.inc /usr/local/etc/inc/**/*.inc 2>/dev/null | head -12
echo "--- 网关字段名（monitor / disabled / defaultgw 等） ---"
grep -rn "monitor_disable\|'monitor'\|\['disabled'\]\|defaultgw" /usr/local/etc/inc/gwlb.inc 2>/dev/null | head -12

echo
echo "########## 2. 过滤器如何用规则里的 gateway（route-to 是不是它生成） ##########"
grep -rn "gateway" /usr/local/etc/inc/filter.inc 2>/dev/null | head -14

echo
echo "########## 3. 现有 LAN 规则在 config.xml 里的完整结构（照抄用） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
flt = r.find('filter')
if flt is None:
    print('  (no filter)')
else:
    n = 0
    for rule in flt.findall('rule'):
        if (rule.findtext('interface') or '') in ('lan', 'opt1', 'opt2'):
            print('  --- rule ---')
            print('   ', ET.tostring(rule, encoding='unicode').strip()[:600])
            n += 1
            if n >= 2:
                break
PY

echo
echo "########## 4. pf 里 pass 规则样式（是否 quick） ##########"
pfctl -sr 2>/dev/null | grep '^pass' | head -3 | sed 's/^/  /'

echo
echo "########## 5. 现有 nat 结构（DNS 重定向要用） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
nat = r.find('nat')
print('  nat 节点:', 'present' if nat is not None else 'absent')
if nat is not None:
    for child in list(nat)[:4]:
        print('   ', child.tag, ET.tostring(child, encoding='unicode').strip()[:200])
PY

echo
echo "########## 6. 接口块结构（tun_mihomo 要加的那段） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
ifs = r.find('interfaces')
for node in list(ifs)[:4]:
    print('  ', ET.tostring(node, encoding='unicode').strip()[:220])
print('  现有 optN:', [n.tag for n in ifs])
PY
