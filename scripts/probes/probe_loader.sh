#!/bin/sh
set -u
echo "=== mvc config: loader namespaces ==="
find /usr/local/opnsense/mvc -maxdepth 3 -name 'config*.php' -o -maxdepth 3 -name '*.ini' | head
echo "---"
grep -n "registerNamespaces\|OPNsense" /usr/local/opnsense/mvc/config/config.php 2>/dev/null
echo
echo "=== app config ==="
sed -n '1,60p' /usr/local/opnsense/mvc/config/config.php 2>/dev/null
echo
echo "=== php yaml ext? ==="
php -m 2>/dev/null | grep -i -E 'yaml|curl|json|dom|simplexml|openssl' 
echo
echo "=== jq / curl binaries ==="
which jq curl python3 2>/dev/null
echo
echo "=== AppConfig defaults (tempDir / application) ==="
grep -rn "tempDir" /usr/local/opnsense/mvc/app/config/*.ini 2>/dev/null | head
ls /usr/local/opnsense/mvc/app/config/ 2>/dev/null
