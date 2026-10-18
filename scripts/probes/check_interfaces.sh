#!/bin/sh
# 只读取证：这台机器上有哪些接口/网段/网关，做策略路由要动哪些地方
set -u
CFG=/conf/config.xml

echo "########## 1. 物理/逻辑接口 ##########"
ifconfig -l

echo
echo "########## 2. config.xml 里启用的接口（接口块 → if → IP） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
ifs = r.find('interfaces')
if ifs is None:
    print('  (无 interfaces 节点)')
else:
    for node in ifs:
        name = node.tag
        descr = node.findtext('descr') or ''
        ifname = node.findtext('if') or ''
        ip = node.findtext('ipaddr') or node.findtext('ipaddrv6') or ''
        subnet = node.findtext('subnet') or ''
        print(f'  {name:8s} if={ifname:10s} ip={ip:16s}/{subnet:4s} {descr}')
PY

echo
echo "########## 3. 已配置的网关（做策略路由要在这里加一个） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
gws = r.find('gateways')
if gws is None or len(gws) == 0:
    print('  (没有自定义网关项)')
else:
    for item in gws.findall('gateway_item'):
        print('  name=%-16s interface=%-8s gw=%-16s descr=%s' % (
            item.findtext('name') or '', item.findtext('interface') or '',
            item.findtext('gateway') or '', item.findtext('descr') or ''))
PY

echo
echo "########## 4. 当前默认路由 ##########"
netstat -rn -f inet | awk '$1=="default" || $2=="default"' | head -5

echo
echo "########## 5. 现有转发/DNS 策略相关配置（只读） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
# NAT
nat = r.find('nat')
n = 0
if nat is not None:
    for rule in nat.findall('.//rule'):
        iface = rule.findtext('interface') or ''
        dst = (rule.findtext('target') or '') + ':' + (rule.findtext('local-port') or '')
        descr = rule.findtext('descr') or ''
        n += 1
        print(f'  NAT  {iface:8s} -> {dst:24s} {descr}')
print(f'  (NAT 规则数: {n})')
# Unbound 转发
ub = r.find('OPNsense/unboundplus')
if ub is not None:
    fwd = ub.findtext('forwarding/enabled')
    print(f'  Unbound forwarding.enabled = {fwd}')
    dots = ub.find('dots')
    if dots is not None:
        for d in dots.findall('dot'):
            print('    dot: %s server=%s port=%s descr=%s' % (
                d.findtext('type') or '', d.findtext('server') or '',
                d.findtext('port') or '', d.findtext('description') or ''))
PY

echo
echo "########## 6. 有没有引用 tun_mihomo 的接口/规则 ##########"
grep -c 'tun_mihomo' "$CFG" 2>/dev/null | sed 's/^/  config.xml 中出现次数: /'
grep -n 'tun_mihomo' "$CFG" 2>/dev/null | head -5

echo
echo "########## 7. pf 里现有的 route-to / reply-to（策略路由的样子） ##########"
pfctl -sr 2>/dev/null | grep -c 'route-to\|reply-to' | sed 's/^/  rule 里的 route-to 数量: /'
pfctl -sr 2>/dev/null | grep 'route-to' | head -5

echo
echo "########## 8. mihomo 二进制里与 tun 地址相关的默认值 ##########"
strings /usr/local/bin/mihomo 2>/dev/null | grep -E '^(172\.19|198\.18|inet4-address|auto-route|strict-route)' | sort -u | head -10
