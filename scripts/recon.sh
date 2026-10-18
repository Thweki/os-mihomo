#!/bin/sh
# Read-only reconnaissance of the target OPNsense appliance.
set -u

echo "=== OS / PRODUCT ==="
opnsense-version 2>&1
uname -a

echo
echo "=== PHP ==="
php -v 2>&1 | head -n 2

echo
echo "=== INSTALLED PLUGIN PACKAGES (mihomo-ish) ==="
pkg info 2>/dev/null | egrep -i 'mihomo|clash|sing-box|lucky|ttyd|staticarp|unboundcustom|ddns' || echo "(none)"

echo
echo "=== MIHOMO SERVICE STATUS ==="
if [ -f /usr/local/etc/rc.d/mihomo ]; then
  service mihomo status 2>&1 || true
else
  echo "(rc.d/mihomo missing)"
fi

echo
echo "=== LISTENING PORTS (53/1053/7891/9090/9091/8080) ==="
sockstat -4 -l 2>/dev/null | egrep ':53|:1053|:7891|:9090|:9091|:8080' || echo "(none matching)"

echo
echo "=== TUN INTERFACE ==="
ifconfig tun_mihomo 2>&1 | head -n 5 || true

echo
echo "=== MIHOMO FILES ON DISK ==="
for p in /usr/local/bin/mihomo /usr/local/bin/clash-meta /usr/local/etc/mihomo /usr/local/www/mihomo.php /usr/local/www/mihomo_sub.php /usr/local/www/mihomo_logs.php /usr/local/www/mihomo_sub_log.php /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo /usr/local/etc/rc.d/mihomo /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf /usr/local/etc/inc/plugins.inc.d/mihomo.inc /usr/local/opnsense/version/mihomo; do
  if [ -e "$p" ]; then printf '%-70s EXISTS\n' "$p"; else printf '%-70s MISSING\n' "$p"; fi
done

echo
echo "=== EXISTING MVC PLUGIN DIRS (controllers/views/models) ==="
ls -1 /usr/local/opnsense/mvc/app/controllers/OPNsense/ 2>/dev/null
echo "--- views ---"
ls -1 /usr/local/opnsense/mvc/app/views/OPNsense/ 2>/dev/null
echo "--- models ---"
ls -1 /usr/local/opnsense/mvc/app/models/OPNsense/ 2>/dev/null

echo
echo "=== MENU / ACL CACHE ==="
ls -la /var/lib/php/tmp/ 2>/dev/null

echo
echo "=== CONFIG.XML: mihomo-related only (read-only peek) ==="
grep -n -i -E 'tun_mihomo|mihomo' /conf/config.xml 2>/dev/null | head -n 20 || echo "(no mihomo references)"

echo
echo "=== STOPPED? check state (no changes) ==="
echo "rc.conf.d/mihomo:"; cat /etc/rc.conf.d/mihomo 2>/dev/null || echo "(missing)"

echo
echo "=== LOGS ==="
ls -la /var/log/mihomo*.log 2>/dev/null || echo "(no mihomo logs)"

echo
echo "=== DONE ==="
