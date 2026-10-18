#!/bin/sh
set -u
echo "=== getFormData ==="
grep -n -A25 "function getFormData" /usr/local/opnsense/www/js/opnsense_ui.js
echo
echo "=== who fills \$_POST ? ==="
grep -rn '\$_POST\s*\[.*\]\s*=' /usr/local/opnsense/mvc/app/library/ /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ 2>/dev/null | head -20
echo
echo "=== Application bootstrap ==="
find /usr/local/opnsense/mvc/app/library/OPNsense/Mvc -name '*.php' | head -20
grep -rn 'json' /usr/local/opnsense/mvc/app/library/OPNsense/Mvc/Application.php 2>/dev/null | head
echo
echo "=== index.php entry for /ui and /api ==="
ls /usr/local/www/
echo "---"
cat /usr/local/www/index.php 2>/dev/null | head -40
