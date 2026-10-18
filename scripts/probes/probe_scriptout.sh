#!/bin/sh
set -u
echo "=== actions module dir ==="
ls /usr/local/opnsense/service/modules/actions/
echo
echo "=== script_output.py ==="
cat /usr/local/opnsense/service/modules/actions/script_output.py 2>/dev/null
echo
echo "=== ApiControllerBase (head 120) ==="
sed -n '30,140p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiControllerBase.php
