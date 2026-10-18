#!/bin/sh
# Locate the OPNsense MVC base library and inspect key classes.
set -u

echo "=== library root ==="
ls -la /usr/local/opnsense/mvc/app/ 2>/dev/null
echo
echo "=== find Base classes ==="
find /usr/local/opnsense/mvc -maxdepth 6 -type d -name Base 2>/dev/null
echo
echo "=== find ApiMutableModelControllerBase ==="
find /usr/local/opnsense -name 'ApiMutableModelControllerBase.php' -o -name 'ApiMutableServiceControllerBase.php' -o -name 'ApiControllerBase.php' -o -name 'IndexController.php' -o -name 'BaseModel.php' -o -name 'BaseController.php' 2>/dev/null
echo
echo "=== ACL matching code ==="
grep -rln "isPageAccessible\|checkPageAccess" /usr/local/opnsense/mvc/app /usr/local/opnsense/scripts 2>/dev/null | head -10
