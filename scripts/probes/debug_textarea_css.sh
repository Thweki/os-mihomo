#!/bin/sh
set -u
echo "=== main.css 2715-2760 ==="
sed -n '2715,2760p' /usr/local/opnsense/www/themes/opnsense-dark/build/css/main.css
echo
echo "=== 核心页面怎样做大文本框（找 max-width 覆盖）==="
grep -rn 'max-width: *none\|max-width: *100%\|max-width:none' /usr/local/www/*.php /usr/local/opnsense/mvc/app/views/OPNsense/*/*.volt 2>/dev/null | head -10
echo
echo "=== 主题 CSS 里 textarea 的宽度类 ==="
grep -rn 'textarea' /usr/local/opnsense/www/themes/opnsense-dark/build/css/main.css | sed -n '1,6p'
sed -n '144,150p;210,220p;1148,1156p' /usr/local/opnsense/www/themes/opnsense-dark/build/css/main.css
