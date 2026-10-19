#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 交付前最终清理与复位
set -u

echo "=== 1. 复位模型 enabled=0（经 Web API，避免 PHP 引导问题）==="
python3 - <<'PY'
import json, ssl, http.cookiejar, urllib.request, urllib.parse, re

BASE = 'https://127.0.0.1'
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj), urllib.request.HTTPSHandler(context=ctx))

page = opener.open(BASE + '/index.php', timeout=20).read().decode('utf-8', 'replace')
m = re.search(r'<input type="hidden" name="([^"]+)" value="([^"]+)"', page)
form = {'login': '1', 'usernamefld': 'root', 'passwordfld': __import__('os').environ.get('OPN_PW', '')}
if m:
    form[m.group(1)] = m.group(2)
opener.open(BASE + '/index.php', urllib.parse.urlencode(form).encode(), timeout=20).read()

# 取 csrf token
page2 = opener.open(BASE + '/ui/mihomo', timeout=20).read().decode('utf-8', 'replace')
t = re.search(r'X-CSRFToken", "([^"]+)"', page2)
token = t.group(1) if t else ''

payload = json.dumps({'mihomo': {'general': {'enabled': '0'}}}).encode()
req = urllib.request.Request(BASE + '/api/mihomo/settings/set', data=payload,
                             headers={'Content-Type': 'application/json', 'X-CSRFToken': token})
try:
    print('set response:', opener.open(req, timeout=20).read().decode()[:200])
except Exception as e:
    print('set failed:', e)

import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
n = r.find('OPNsense/mihomo/general/enabled')
print('model enabled now =', n.text if n is not None else 'missing')
PY

echo
echo "=== 2. 清空日志 ==="
configctl mihomo log-clear mihomo
configctl mihomo log-clear subscription
wc -l /var/log/mihomo.log /var/log/mihomo_sub.log 2>/dev/null

echo
echo "=== 3. 清理临时目录 ==="
rm -rf /tmp/mihomo-demo /tmp/mihomo-stage /tmp/mihomo-test /tmp/menu_page.html /tmp/menu_test_jar.txt 2>/dev/null || true
ls -d /tmp/mihomo* 2>/dev/null || echo "(clean)"

echo
echo "=== 4. 最终确认 ==="
service mihomo status
cat /etc/rc.conf.d/mihomo
echo "--- 接口清单（无 tun）---"
ifconfig -l
echo "--- 监听 53/9090 ---"
sockstat -4 -l 2>/dev/null | egrep ':53 |:9090' | head -4
