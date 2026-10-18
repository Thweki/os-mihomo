#!/bin/sh
# 语言/翻译环境（精简版）
set -u

echo "=== 1. config.xml 语言设置 ==="
grep -o '<language>[^<]*</language>' /conf/config.xml || echo "(无 <language>)"
echo "用户级语言："
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
for u in r.iter('user'):
    name = u.findtext('name')
    lang = u.findtext('language') or '(继承系统)'
    print('  %-10s %s' % (name, lang))
PY

echo
echo "=== 2. 已安装的 OPNsense.mo ==="
find /usr/local/share/locale -name 'OPNsense.mo' 2>/dev/null | sort

echo
echo "=== 3. 是否存在 zh_CN 目录 ==="
ls -la /usr/local/share/locale/ 2>/dev/null

echo
echo "=== 4. 语言包插件（哪来的 zh 翻译）==="
pkg info 2>/dev/null | egrep -i 'lang|i18n' || echo "(无)"
ls -la /usr/local/share/opnsense/ 2>/dev/null | head

echo
echo "=== 5. 相关命令 ==="
for c in msgfmt msgunfmt msgcat xgettext; do printf '  %-10s %s\n' "$c" "$(command -v $c 2>/dev/null || echo MISSING)"; done
