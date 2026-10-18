#!/bin/sh
# 三方对照：config.xml 模型值 / config.yaml 文件值 / mihomo 运行态值
set -u
CFG=/usr/local/etc/mihomo/config.yaml
BASE=https://127.0.0.1
JAR=/tmp/cmp_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

echo "########## 1. mihomo 相关 configd 动作 ##########"
grep -o '^\[[a-z-]*\]' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf | tr -d '[]' | tr '\n' ' '
echo; echo

echo "########## 2. WebUI 能改的键（模型 patchKeys）当前值 vs 文件值 ##########"
python3 - <<'PY'
import io, re, sys
sys.path.insert(0, '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo')
import xml.etree.ElementTree as ET

# 模型值
r = ET.parse('/conf/config.xml').getroot()
m = r.find('OPNsense/mihomo')
mdl = {}
if m is not None:
    for section in m:
        for f in section:
            mdl['%s.%s' % (section.tag, f.tag)] = (f.text or '').strip()
    for f in m:
        if len(f) == 0:
            mdl[f.tag] = (f.text or '').strip()

# 文件值（简单扫描顶层键）
t = io.open('/usr/local/etc/mihomo/config.yaml', encoding='utf-8').read()
def file_val(path):
    parts = path.split('.')
    indent = 0
    for i, key in enumerate(parts):
        pat = re.compile(r'^%s%s:[ \t]*(.*)$' % (' ' * indent, re.escape(key)), re.M)
        mm = pat.search(t)
        if not mm:
            return None
        val = mm.group(1).strip()
        if val == '' and i < len(parts) - 1:
            indent += 2
            continue
        return val
    return None

pairs = [
    ('general.logLevel', 'log-level'), ('general.mode', 'mode'), ('general.allowLan', 'allow-lan'),
    ('general.controllerBind', 'external-controller'), ('general.secret', 'secret'),
    ('tun.enabled', 'tun.enable'), ('tun.device', 'tun.device'), ('tun.stack', 'tun.stack'),
    ('tun.autoRoute', 'tun.auto-route'), ('tun.strictRoute', 'tun.strict-route'), ('tun.mtu', 'tun.mtu'),
    ('dns.enabled', 'dns.enable'), ('dns.listen', 'dns.listen'), ('dns.enhancedMode', 'dns.enhanced-mode'),
    ('general.sniffer', 'sniffer.enable'),
]
print('  %-26s %-22s %-22s %s' % ('键', 'config.xml（WebUI）', 'config.yaml（文件）', '一致?'))
for mp, yp in pairs:
    a = mdl.get(mp, '(无)')
    b = file_val(yp)
    b = '(无此键)' if b is None else (b if b else '(空)')
    same = '✅' if str(a).lower() in ('true','1') and str(b).lower() == 'true' or str(a) == b else '❌'
    print('  %-26s %-22s %-22s %s' % (yp, a, b, same))
PY

echo
echo "########## 3. 运行态（内核内存里的配置，与文件无关） ##########"
SECRET=$(python3 -c "
import re,io
t=io.open('/usr/local/etc/mihomo/config.yaml',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)$',t,re.M)
print((m.group(1).strip().strip('\"').strip(chr(39))) if m else '')")
curl -s -m 5 http://127.0.0.1:9090/configs -H "Authorization: Bearer $SECRET" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in ('port','socks-port','mixed-port','allow-lan','bind-address','mode','log-level','ipv6','tun'):
    if k in d: print('  %-14s %s' % (k, d[k]))
" 2>/dev/null || echo "  (读不到 /configs)"

echo
echo "########## 4. 受管区块（路由策略写进 config.yaml 的那段） ##########"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/  /'
echo "  （模板里同样有这份区块）:"
grep -c 'os-mihomo:policy-routing' /usr/local/etc/mihomo/sub/template_config.yaml | sed 's/^/    /'

echo
echo "########## 5. 服务层（不在 config.yaml 里） ##########"
echo "  开机自启(rc.conf.d): $(grep -h mihomo_enable /etc/rc.conf.d/mihomo 2>/dev/null || echo '(未设置)')"
echo "  进程: $(service mihomo status 2>&1 | head -1)"
rm -f "$JAR"
