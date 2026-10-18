#!/bin/sh
set -u
echo "=== Mvc Request class ==="
find /usr/local/opnsense/mvc -name 'Request.php' | head
grep -rn -A20 "function getPost\|function getJsonRawBody\|json" /usr/local/opnsense/mvc/app/library/OPNsense/Mvc/Request.php 2>/dev/null | head -60
echo
echo "=== does phalcon parse json bodies? check Request.php full ==="
sed -n '1,120p' /usr/local/opnsense/mvc/app/library/OPNsense/Mvc/Request.php 2>/dev/null
