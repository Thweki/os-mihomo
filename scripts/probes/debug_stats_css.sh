#!/bin/sh
set -u
echo "=== dns-overview.css 是否存在 ==="
for t in opnsense opnsense-dark opnsense-auto; do
    p=/usr/local/opnsense/www/themes/$t/build/css/dns-overview.css
    if [ -f "$p" ]; then echo "EXISTS $p ($(wc -c < "$p") bytes)"; else echo "MISSING $p"; fi
done
echo
echo "=== 关键类名 ==="
grep -o '\.stats-[a-z-]*\|\.banner\|\.large-icon\|\.stats-element\|\.stats-text\|\.stats-icon\|\.stats-counter-text\|\.stats-inner-text' \
    /usr/local/opnsense/www/themes/opnsense-dark/build/css/dns-overview.css 2>/dev/null | sort -u
echo
echo "=== 主题映射（theme_file_or_default 用的目录）==="
ls /usr/local/opnsense/www/themes/ 2>/dev/null
