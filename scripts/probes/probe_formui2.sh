#!/bin/sh
set -u
echo "=== find saveFormToEndpoint ==="
grep -rln "saveFormToEndpoint" /usr/local/opnsense/www/js/ /usr/local/opnsense/mvc/app/views/ 2>/dev/null | head
echo "--- definition ---"
grep -rn -A40 "saveFormToEndpoint = function\|function saveFormToEndpoint" /usr/local/opnsense/www/js/*.js 2>/dev/null | head -60
echo
echo "=== find mapDataToFormUI ==="
grep -rn -A45 "mapDataToFormUI = function\|function mapDataToFormUI" /usr/local/opnsense/www/js/*.js 2>/dev/null | head -70
echo
echo "=== which js bundles are loaded ==="
grep -rn "javascript_files\|addJs\|->js" /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerBase.php | head -20
