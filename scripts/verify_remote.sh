#!/bin/sh
# os-mihomo —— 部署后体检（只读）
set -u

echo "=== 1. configd actions 注册情况 ==="
configctl configd actions 2>/dev/null | grep -E '^mihomo ' || \
    (echo "trying list..." ; configctl configd actions 2>/dev/null | head -5)

echo
echo "=== 2. configd 调用测试 ==="
echo "--- mihomo status ---"
configctl mihomo status; echo "(exit=$?)"
echo "--- mihomo config-current（校验已安装配置）---"
configctl mihomo config-current; echo "(exit=$?)"
echo "--- mihomo log-tail mihomo 20 ---"
configctl mihomo log-tail mihomo 20; echo "(exit=$?)"
echo "--- mihomo env-get ---"
configctl mihomo env-get; echo "(exit=$?)"

echo
echo "=== 3. 菜单缓存中的 mihomo ==="
python3 - <<'PY' 2>/dev/null || grep -o 'mihomo[^<]*' /var/lib/php/tmp/opnsense_menu_cache.xml 2>/dev/null | head
import xml.etree.ElementTree as ET
t = ET.parse('/var/lib/php/tmp/opnsense_menu_cache.xml')
for e in t.iter():
    if e.tag.lower().startswith('mihomo') or (e.get('url') and 'mihomo' in (e.get('url') or '')):
        print('%s  url=%s  visname=%s' % (e.tag, e.get('url'), e.get('VisibleName')))
PY

echo
echo "=== 4. ACL 缓存中的 mihomo ==="
python3 - <<'PY'
import json
d = json.load(open('/var/lib/php/tmp/opnsense_acl_cache.json'))
for k, v in d.items():
    if 'mihomo' in k:
        print(k, '=>', json.dumps(v))
PY

echo
echo "=== 5. 安装后的文件与权限 ==="
ls -la /usr/local/bin/mihomo /usr/local/etc/rc.conf.d/mihomo /usr/local/etc/mihomo/config.yaml
ls -la /usr/local/opnsense/scripts/mihomo/
echo "--- mihomo 内核自检 ---"
/usr/local/bin/mihomo -v

echo
echo "=== 6. 内核能否通过当前配置 ==="
/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f /usr/local/etc/mihomo/config.yaml; echo "(exit=$?)"

echo
echo "=== 7. 服务状态（应为 not running / disabled）==="
service mihomo status; echo "(exit=$?)"
cat /etc/rc.conf.d/mihomo

echo
echo "=== 8. MVC 文件语法复检 ==="
for f in /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/*.php \
         /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/*.php \
         /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/*.php \
         /usr/local/opnsense/scripts/mihomo/*.php \
         /usr/local/www/mihomo*.php; do
    out=$(php -l "$f" 2>&1) || echo "FAIL $f: $out"
done
echo "(仅显示失败项)"

echo
echo "=== DONE ==="
