#!/bin/sh
set -u
echo "=== php-fpm processes ==="
ps aux 2>/dev/null | grep -E 'php-fpm|lighttpd' | grep -v grep
echo
echo "=== php-fpm pool config: user/group ==="
grep -rn "user\|group\|listen" /usr/local/etc/php-fpm.d/*.conf 2>/dev/null | grep -v '^.*#' | head -20
echo
echo "=== disable_functions ==="
php -i 2>/dev/null | grep -i "disable_functions" | head -3
echo "--- from web sapi perspective (php-fpm ini) ---"
grep -rn "disable_functions" /usr/local/etc/php*.ini /usr/local/etc/php.d/* 2>/dev/null | head
echo
echo "=== who owns the web root ==="
ls -ld /usr/local/www /usr/local/opnsense/mvc/app/models /usr/local/etc/mihomo 2>/dev/null
echo
echo "=== configd socket / who runs configd ==="
ps aux 2>/dev/null | grep configd | grep -v grep | head -5
echo
echo "=== tmp dirs writable by web ==="
ls -ld /var/lib/php/tmp /tmp
echo
echo "=== check if wwwonly user exists ==="
id wwwonly 2>/dev/null || echo "(no wwwonly)"
id www 2>/dev/null || echo "(no www)"
echo
echo "=== opnsense scripts dir perms ==="
ls -ld /usr/local/opnsense/scripts/ 2>/dev/null
ls -ld /usr/local/opnsense/scripts/mihomo 2>/dev/null || echo "(no mihomo scripts dir yet)"
