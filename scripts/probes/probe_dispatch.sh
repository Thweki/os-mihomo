#!/bin/sh
set -u
echo "=== getRawBody / json usages ==="
grep -rn "getRawBody\|getJsonRawBody" /usr/local/opnsense/mvc/app/ | head -20
echo
echo "=== Dispatcher ==="
grep -n -B3 -A20 "POST\|json" /usr/local/opnsense/mvc/app/library/OPNsense/Mvc/Dispatcher.php | head -50
echo
echo "=== lighttpd webgui config ==="
cat /usr/local/etc/lighttpd_webgui/lighttpd.conf 2>/dev/null | head -60
echo
echo "=== where does /ui /api go? ==="
grep -rn "api\|ui" /usr/local/etc/lighttpd_webgui/lighttpd.conf 2>/dev/null | head -30
