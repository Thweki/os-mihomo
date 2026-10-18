#!/bin/sh
# ============================================================================
# os-mihomo —— 「此刻真实配置」三方对照（只读，不改任何东西）
#
#   · WebUI 值  = /conf/config.xml 里 <OPNsense><mihomo> 的模型值
#   · 文件值    = /usr/local/etc/mihomo/config.yaml 里真正写着的值
#   · 运行值    = mihomo 进程内存里正在用的值（外部控制器 /configs）
#
# 用法：sh config_truth.sh
#   · 三方一致  → 配置已生效
#   · WebUI ≠ 文件 → 设置页改了但没点「应用」（或手工改了文件）
#   · 文件 ≠ 运行  → 应用/改文件后没重启服务（内核还在用旧配置）
# ============================================================================
set -u
CFG=/usr/local/etc/mihomo/config.yaml
TEMPLATE=/usr/local/etc/mihomo/sub/template_config.yaml

echo "=================================================================="
echo " 1) WebUI 值 vs 文件值（同一个键，两处都写得出来）"
echo "=================================================================="
python3 - <<'PY'
import io, re
import xml.etree.ElementTree as ET

def norm(v):
    if v is None:
        return '(无)'
    s = str(v).strip().strip('"').strip("'")
    if s.lower() in ('true', 'yes', 'on', '1'):
        return 'true'
    if s.lower() in ('false', 'no', 'off', '0'):
        return 'false'
    return s

# ---- 模型值 ----
root = ET.parse('/conf/config.xml').getroot()
node = root.find('OPNsense/mihomo')
mdl = {}
if node is not None:
    for section in node:
        if len(section) == 0:
            mdl[section.tag] = (section.text or '').strip()
            continue
        for field in section:
            mdl['%s.%s' % (section.tag, field.tag)] = (field.text or '').strip()

# ---- 文件值（按缩进找路径，只认第一个） ----
text = io.open('/usr/local/etc/mihomo/config.yaml', encoding='utf-8').read()
lines = text.split('\n')

def file_val(path):
    parts = path.split('.')
    indent = 0
    start = 0
    for step, key in enumerate(parts):
        pat = re.compile(r'^(%s)%s:[ \t]*(.*)$' % (' ' * indent, re.escape(key)))
        found = None
        for i in range(start, len(lines)):
            m = pat.match(lines[i])
            if m:
                found = (i, m.group(2))
                break
        if found is None:
            return None
        start, value = found
        value = value.split('#')[0].strip() if not value.strip().startswith('"') else value.strip()
        if step == len(parts) - 1:
            return value
        if value == '':
            indent += 2
            continue
        return value
    return None

checks = [
    ('日志等级', 'log-level', 'general.logLevel'),
    ('运行模式', 'mode', 'general.mode'),
    ('允许局域网', 'allow-lan', 'general.allowLan'),
    ('控制器地址', 'external-controller', None),
    ('控制器密钥', 'secret', 'general.secret'),
    ('TUN 开关', 'tun.enable', 'tun.enabled'),
    ('TUN 设备名', 'tun.device', 'tun.device'),
    ('TUN 协议栈', 'tun.stack', 'tun.stack'),
    ('TUN 抢默认路由', 'tun.auto-route', 'tun.autoRoute'),
    ('TUN 强制路由', 'tun.strict-route', 'tun.strictRoute'),
    ('TUN MTU', 'tun.mtu', 'tun.mtu'),
    ('DNS 开关', 'dns.enable', 'dns.enabled'),
    ('DNS 监听', 'dns.listen', 'dns.listen'),
    ('DNS 模式', 'dns.enhanced-mode', 'dns.enhancedMode'),
    ('域名嗅探', 'sniffer.enable', 'general.sniffer'),
]

print('  %-16s %-24s %-24s %s' % ('项目', 'WebUI（config.xml）', '文件（config.yaml）', '一致'))
print('  ' + '-' * 76)
diff = 0
for label, yaml_key, mdl_key in checks:
    a = '(不适用)'
    if yaml_key == 'external-controller':
        a = '%s:%s' % (mdl.get('general.controllerBind', ''), mdl.get('general.controllerPort', ''))
    elif mdl_key:
        a = mdl.get(mdl_key, '(无)')
    b = file_val(yaml_key)
    if b is None:
        b = '(文件里没有这个键 → 用内核默认值)'
    if isinstance(b, str) and b.startswith('(文件里没有'):
        ok = '—（用内核默认值）'
    else:
        ok = '✅' if norm(a) == norm(b) else '❌'
        if ok == '❌':
            diff += 1
    print('  %-16s %-24s %-24s %s' % (label, str(a)[:22], str(b)[:22], ok))
print()
print('  不一致项：%d 个' % diff)
if diff:
    print('  → WebUI 与文件不一致时：点设置页「应用」会把文件改成 WebUI 里的值；')
    print('    想让 WebUI 跟随文件，用设置页的「从配置导入」。')
PY

echo
echo "=================================================================="
echo " 2) 文件值 vs 运行值（内核内存里正在用的）"
echo "=================================================================="
SECRET=$(python3 -c "
import re,io
t=io.open('/usr/local/etc/mihomo/config.yaml',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print((m.group(1).strip().strip('\"').strip(chr(39))) if m else '')")
curl -s -m 5 http://127.0.0.1:9090/configs -H "Authorization: Bearer $SECRET" | python3 -c "
import json,sys,io,re
try:
    d=json.load(sys.stdin)
except Exception:
    print('  控制器读不到（服务没跑、或密钥不对）——运行值只能等它起来再看')
    sys.exit(0)
t=io.open('/usr/local/etc/mihomo/config.yaml',encoding='utf-8').read()
def fv(path, default='(无)'):
    parts=path.split('.'); indent=0; start=0; lines=t.split(chr(10))
    for step,key in enumerate(parts):
        pat=re.compile(r'^(%s)%s:[ \t]*(.*)\$' % (' '*indent, re.escape(key)))
        hit=None
        for i in range(start,len(lines)):
            m=pat.match(lines[i])
            if m: hit=(i,m.group(2)); break
        if hit is None: return default
        start,val=hit
        if step==len(parts)-1: return val.split('#')[0].strip()
        if val=='': indent+=2; continue
        return val
    return default
def b2s(v):
    return 'true' if v is True else ('false' if v is False else str(v))
rows=[
 ('运行模式','mode', d.get('mode')),
 ('日志等级','log-level', d.get('log-level')),
 ('允许局域网','allow-lan', b2s(d.get('allow-lan'))),
 ('mixed 端口','mixed-port', str(d.get('mixed-port'))),
 ('socks 端口','socks-port', str(d.get('socks-port'))),
 ('TUN 开关','tun.enable', b2s((d.get('tun') or {}).get('enable'))),
 ('TUN 抢默认路由','tun.auto-route', b2s((d.get('tun') or {}).get('auto-route'))),
 ('TUN 地址','(内核自算)', ','.join((d.get('tun') or {}).get('inet4-address') or ['-'])),
]
print('  %-16s %-22s %-22s %s' % ('项目','文件里写的','内核正在用的','一致'))
print('  ' + '-'*74)
bad=0
for label,key,runv in rows:
    f=fv(key, '(未写)') if not key.startswith('(') else '-'
    ok='✅' if (f in ('-', '(未写)') or str(f).lower()==str(runv).lower()) else '❌'
    if ok=='❌': bad+=1
    print('  %-16s %-22s %-22s %s' % (label, str(f)[:20], str(runv)[:20], ok))
print()
if bad:
    print('  有 %d 项不一致 → 改了文件但内核还在用旧配置。用仪表盘/设置页的「重启」或 `configctl mihomo restart` 让它生效。' % bad)
else:
    print('  文件与运行值一致 → 当前内核用的就是你文件里的配置。')
"

echo
echo "=================================================================="
echo " 3) 路由策略的受管区块（插件唯一会「整块替换」的地方）"
echo "=================================================================="
if grep -q 'os-mihomo:policy-routing' "$CFG" 2>/dev/null; then
    sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/  /'
else
    echo "  config.yaml 里没有受管区块（当前没有任何接口被绑定）"
fi
echo "  订阅模板里是否已有同一份区块：$(grep -c 'os-mihomo:policy-routing' "$TEMPLATE" 2>/dev/null | head -1) 处"

echo
echo "=================================================================="
echo " 4) 不在 config.yaml 里的东西（服务层 / 网络侧）"
echo "=================================================================="
echo "  开机自启（/etc/rc.conf.d/mihomo）： $(grep -h mihomo_enable /etc/rc.conf.d/mihomo 2>/dev/null || echo '(未设置 → 默认不启用)')"
echo "  服务进程： $(service mihomo status 2>&1 | head -1)"
echo "  OPNsense 侧网关 MIHOMO_TUN： $(grep -c 'MIHOMO_TUN' /conf/config.xml)"
echo "  OPNsense 侧浮动规则（本插件的）： $(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
f=r.find('OPNsense/Firewall/Filter')
print(0 if f is None else len([x for x in f.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]))")"
echo "  pf 里送进 TUN 的规则： $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' | head -1) 条"
echo
echo "  提醒：删掉策略行后必须回路由策略页点「应用」，网络侧（接口/网关/浮动规则）才会被回收。"
