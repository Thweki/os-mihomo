#!/bin/sh
set -u
echo "=== 1. Menu.xml 内容 ==="
cat /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml
echo
echo "=== 2. xml 是否合法 ==="
python3 -c "import xml.etree.ElementTree as ET; ET.parse('/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml'); print('XML OK')"
echo
echo "=== 3. 菜单缓存中是否有 mihomo ==="
ls -la /var/lib/php/tmp/opnsense_menu_cache.xml 2>/dev/null || echo "(no cache file)"
grep -c -i mihomo /var/lib/php/tmp/opnsense_menu_cache.xml 2>/dev/null || echo 0
echo
echo "=== 4. 缓存中 VPN 段 ==="
python3 - <<'PY'
import xml.etree.ElementTree as ET
try:
    t = ET.parse('/var/lib/php/tmp/opnsense_menu_cache.xml')
except Exception as e:
    print('parse error:', e)
    raise SystemExit
for vpn in t.getroot().iter('VPN'):
    for child in vpn:
        print('  %-20s %s' % (child.tag, child.get('VisibleName') or ''))
        for sub in child:
            print('    %-18s url=%s' % (sub.tag, sub.get('url')))
PY
echo
echo "=== 5. Menu 模型如何收集插件菜单 ==="
grep -n -A25 "function loadMenu\|glob" /usr/local/opnsense/mvc/app/models/OPNsense/Core/Menu/Menu.php | head -50
