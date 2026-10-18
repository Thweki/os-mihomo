#!/bin/sh
set -u
sed -n '118,175p' /usr/local/opnsense/mvc/app/library/OPNsense/Mvc/Request.php
echo "=== UserException present? ==="
ls -la /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ | head -20
echo "=== UserException class ==="
find /usr/local/opnsense/mvc -name 'UserException.php' -exec sed -n '1,60p' {} \;
