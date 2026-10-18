#!/bin/sh
set -u
echo "=== views referencing security/token ==="
grep -rn "getToken\|csrf" /usr/local/opnsense/mvc/app/views/ 2>/dev/null | head -20
echo
echo "=== layouts ==="
ls -la /usr/local/opnsense/mvc/app/views/layouts/ 2>/dev/null
echo "--- default.volt (head 80) ---"
sed -n '1,80p' /usr/local/opnsense/mvc/app/views/layouts/default.volt 2>/dev/null
echo
echo "=== opnsense.js ajaxCall ==="
grep -n -A25 "function ajaxCall" /usr/local/opnsense/www/js/opnsense.js | head -60
echo
echo "=== where is ajaxCall defined (maybe opnsense_ui.js) ==="
grep -rln "function ajaxCall" /usr/local/opnsense/www/js/ /usr/local/opnsense/mvc/ 2>/dev/null
