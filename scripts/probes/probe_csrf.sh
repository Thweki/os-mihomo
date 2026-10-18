#!/bin/sh
set -u
echo "=== Security class ==="
find /usr/local/opnsense/mvc -name 'Security.php' -exec grep -n "function \|csrf\|CSRF" {} \; 2>/dev/null | head -40
echo
echo "=== ControllerRoot doAuth ==="
sed -n '100,200p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerRoot.php
echo
echo "=== opnsense.js: csrf handling ==="
grep -n "csrf\|CSRF" /usr/local/opnsense/www/js/opnsense.js | head -20
