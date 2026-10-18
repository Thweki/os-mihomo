#!/bin/sh
set -u
echo "=== 直接运行脚本（绕过 configd）==="
echo "--- config_apply.php current ---"
php /usr/local/opnsense/scripts/mihomo/config_apply.php current; echo "(exit=$?)"
echo
echo "--- env.php get ---"
php /usr/local/opnsense/scripts/mihomo/env.php get; echo "(exit=$?)"
echo
echo "--- logtail.php mihomo 20 ---"
php /usr/local/opnsense/scripts/mihomo/logtail.php mihomo 20; echo "(exit=$?)"
echo
echo "--- logclear.php subscription ---"
php /usr/local/opnsense/scripts/mihomo/logclear.php subscription; echo "(exit=$?)"
echo
echo "=== php extensions (posix?) ==="
php -m | grep -i -E '^(posix|pcntl|curl|gettext)$'

echo
echo "=== configd syslog 最近错误 ==="
tail -40 /var/log/configd.log 2>/dev/null || true
grep -i 'mihomo' /var/log/system/latest.log 2>/dev/null | tail -20 || true
echo "--- messages ---"
tail -30 /var/log/messages 2>/dev/null || true
