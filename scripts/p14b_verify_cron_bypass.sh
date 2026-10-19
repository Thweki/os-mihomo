#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 复核：④ cron 任务（正确的路径）+ ② 的 pf 规则
set -u
BASE=https://127.0.0.1
JAR=/tmp/p14b_jar.txt
rm -f "$JAR"

echo "########## 0. Cron 模板渲染到哪个文件 ##########"
cat /usr/local/opnsense/service/templates/OPNsense/Cron/+TARGETS 2>/dev/null | sed 's/^/  /'

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN_S=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST_S() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN_S" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo
echo "########## 1. 打开自动更新（每 6 小时） ##########"
POST_S /api/mihomo/settings/set '{"mihomo":{"subscription":{"updateEnabled":"1","updateInterval":"v6"}}}' | sed 's/^/  set: /'
POST_S /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('messages',[]):
    if '任务' in m or 'cron' in m.lower() or 'task' in m.lower(): print('  msg:', m)
"

echo
echo "########## 2. config.xml 的 <OPNsense><cron>（正确路径） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('OPNsense/cron')
if cron is None:
    print('  (无 <OPNsense><cron>)')
else:
    for job in cron.findall('jobs/job'):
        print('  ', {c.tag: (c.text or '') for c in job})
PY

echo
echo "########## 3. 生成的 crontab 文件 ##########"
for f in /etc/cron.d/*; do
    [ -f "$f" ] || continue
    if grep -q 'mihomo' "$f" 2>/dev/null; then
        echo "  --- $f ---"
        grep -n 'mihomo' "$f" | sed 's/^/    /'
    fi
done
echo "  (若上面为空，列出 cron.d 内容)"
ls -la /etc/cron.d/ 2>/dev/null | sed 's/^/    /'
grep -rn 'mihomo sub-update' /etc/cron.d/ /var/cron/tabs/ 2>/dev/null | sed 's/^/    /' || true

echo
echo "########## 4. ② 的 pf 规则（内网直达是否真的进了 pf） ##########"
echo "  --- igb0 上、目标为内网网段的 pass 规则 ---"
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -E '192\.168\.(2|10)\.0/24' | sed 's/^/    /' || echo "    (未找到)"
echo "  --- igb0 上带 route-to 的规则数（应为 1） ---"
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -c 'route-to' | sed 's/^/    /'
echo "  --- 规则顺序（route-to 应排在直达规则之后） ---"
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -nE '192\.168\.(2|10)\.0/24|route-to' | head -4 | sed 's/^/    /'

echo
echo "########## 5. 关闭自动更新（恢复原状） ##########"
POST_S /api/mihomo/settings/set '{"mihomo":{"subscription":{"updateEnabled":"0"}}}' >/dev/null
POST_S /api/mihomo/settings/apply '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('messages',[]):
    if '任务' in m or 'task' in m.lower(): print('  msg:', m)
"
python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('OPNsense/cron')
jobs = [] if cron is None else cron.findall('jobs/job')
print('   剩余 cron 任务数:', len(jobs))
"
rm -f "$JAR"
