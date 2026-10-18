#!/bin/sh
set -u
echo "=== JS 里设置 maxWidth 的地方 ==="
grep -rn 'maxWidth' /usr/local/opnsense/www/js/*.js | head -20
echo
echo "=== 主题 CSS 里的 max-width ==="
grep -rn 'max-width' /usr/local/opnsense/www/themes/opnsense-dark/build/css/*.css 2>/dev/null | grep -i 'textarea\|348\|20em' | head -10
echo
echo "=== textarea 相关规则 ==="
grep -rn 'textarea' /usr/local/opnsense/www/themes/opnsense-dark/build/css/*.css 2>/dev/null | head -10
echo
echo "=== 是否有 20em/348 相关内容 ==="
grep -rn '20em\|348px' /usr/local/opnsense/www/themes/opnsense-dark/build/css/*.css 2>/dev/null | head -10
