#!/bin/sh
# 用本地 curl 登录并抓取左侧菜单 HTML，确认 Proxy Suite 是否渲染出来
set -u
BASE=https://127.0.0.1
JAR=/tmp/menu_test_jar.txt
rm -f "$JAR"

# 1. 取登录页 + CSRF
LOGIN_PAGE=$(curl -sk -c "$JAR" "$BASE/index.php")
NAME=$(printf '%s' "$LOGIN_PAGE" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
VALUE=$(printf '%s' "$LOGIN_PAGE" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
echo "csrf field: $NAME"

# 2. 登录
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$NAME=$VALUE" "$BASE/index.php"

# 3. 抓页面
curl -sk -b "$JAR" "$BASE/ui/mihomo" -o /tmp/menu_page.html
echo "page bytes: $(wc -c < /tmp/menu_page.html)"
echo
echo "=== 菜单中是否含 Proxy Suite / Mihomo ==="
grep -o -i 'proxysuite\|proxy suite\|/ui/mihomo[a-z/]*' /tmp/menu_page.html | sort | uniq -c
echo
echo "=== 菜单片段（VPN 部分）==="
python3 - <<'PY'
import re
html = open('/tmp/menu_page.html', encoding='utf-8', errors='replace').read()
i = html.find('IPsec')
j = html.find('Power', i if i > 0 else 0)
for m in re.finditer(r'<a[^>]*href="(/ui/[^"]*)"[^>]*>\s*([^<]{0,40})', html):
    if 'mihomo' in m.group(1) or 'Mihomo' in m.group(2):
        print('  menu link:', m.group(1), '|', m.group(2).strip())
print('  ---- Proxy Suite 出现次数:', html.lower().count('proxy suite'))
print('  ---- mihomo 出现次数:', html.lower().count('mihomo'))
PY
echo
echo "=== root 用户权限 ==="
python3 - <<'PY'
import xml.etree.ElementTree as ET
t = ET.parse('/conf/config.xml')
for u in t.getroot().iter('user'):
    if (u.findtext('name') or '') == 'root':
        privs = [p.text for p in u.findall('priv')]
        print('root privs:', privs)
for g in t.getroot().iter('group'):
    print('group:', g.findtext('name'), '| members:', g.findtext('member'), '| privs:', [p.text for p in g.findall('priv')])
PY
