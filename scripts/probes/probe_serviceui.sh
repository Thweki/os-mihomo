#!/bin/sh
set -u
echo "=== updateServiceControlUI / updateServiceStatusUI ==="
grep -n -A55 "function updateServiceControlUI" /usr/local/opnsense/www/js/opnsense_ui.js
echo
echo "=== updateServiceStatusUI ==="
grep -n -A45 "function updateServiceStatusUI" /usr/local/opnsense/www/js/opnsense_ui.js
