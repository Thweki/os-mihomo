#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# ② 内网直达规则 + ④ 订阅自动更新（Cron）功能验证
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
XCFG=/conf/config.xml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
TOKEN_S=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }
POST_S() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN_S" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## ②-1. 计划（应出现内网直达） ##########"
GET /api/mihomo/routing/netplan | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('changes',[]): print('  ·', c)
print('  note:', d.get('note'))
"

echo
echo "########## ②-2. 应用 ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- config.xml 里我们加的规则（按顺序） ---"
python3 - <<'PY'
import re, io
t = io.open('/conf/config.xml', encoding='utf-8').read()
for block in re.findall(r'<rule\b[^>]*>.*?</rule>', t, re.S):
    if 'Mihomo' not in block:
        continue
    iface = re.search(r'<interface>([^<]+)</interface>', block)
    dest = re.search(r'<destination><network>([^<]+)</network></destination>', block)
    gw = re.search(r'<gateway>([^<]+)</gateway>', block)
    descr = re.search(r'<descr>([^<]+)</descr>', block)
    print('   %-8s %-28s gw=%-12s %s' % (
        iface.group(1) if iface else '?',
        ('→ ' + dest.group(1)) if dest else '→ any',
        gw.group(1) if gw else '—',
        descr.group(1) if descr else ''))
PY

echo
echo "  --- pf 规则（内网直达在前、策略路由在后） ---"
pfctl -sr 2>/dev/null | grep -n 'Mihomo\|route-to' | head -6 | sed 's/^/    /'

echo
echo "########## ②-3. 幂等：再应用一次 ##########"
POST /api/mihomo/routing/netapply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('messages',[]): print('  msg:', m)
"

echo
echo "########## ②-4. 代理路径未被破坏（自检） ##########"
POST /api/mihomo/routing/selftest '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results', []):
    print('  ', r.get('interface'), '出口 IP:', r.get('foreign_ip') or '(失败)',
          '| 规则:', (r.get('foreign_rule') or '—')[:60], '| 组:', (r.get('foreign_group') or '—')[:40])
"

echo
echo "########## ④-1. 打开「自动更新」（每 12 小时） ##########"
POST_S /api/mihomo/settings/set '{"mihomo":{"subscription":{"updateEnabled":"1","updateInterval":"v12"}}}' | sed 's/^/  set: /'
POST_S /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('  msg:', m)
"
echo "  --- config.xml 里的 cron 任务 ---"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('cron')
if cron is None:
    print('   (无)')
else:
    for job in cron.findall('job'):
        print('   ', {c.tag: (c.text or '') for c in job})
PY
echo "  --- 生成的 crontab ---"
grep -rn 'mihomo' /etc/cron.d/ 2>/dev/null | sed 's/^/    /' || echo "    (cron.d 里没有)"

echo
echo "########## ④-2. 关闭「自动更新」→ 任务应被删除 ##########"
POST_S /api/mihomo/settings/set '{"mihomo":{"subscription":{"updateEnabled":"0"}}}' >/dev/null
POST_S /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('messages',[]): print('  msg:', m)
"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('cron')
jobs = [] if cron is None else cron.findall('job')
print('   剩余 cron 任务数:', len(jobs))
PY
grep -rn 'mihomo' /etc/cron.d/ 2>/dev/null | sed 's/^/    /' || echo "    crontab 里已无 mihomo ✅"

echo
echo "########## ⑤ 安全自检（LanDirect 侧） ##########"
printf '  igb4 route-to 数（应 0）: %s\n' "$(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 || true)"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo -n "  服务: "; service mihomo status 2>&1 | head -1
rm -f "$JAR"
