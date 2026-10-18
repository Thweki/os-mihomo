#!/bin/sh
set -u
echo "=== service_status_container in views/layouts ==="
grep -rn "service_status_container" /usr/local/opnsense/mvc/app/views/ | head -10
echo
echo "=== ControllerBase service_name ==="
grep -n -B5 -A20 "service_status_container\|service_name" /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerBase.php | head -60
echo
echo "=== layout default.volt around status ==="
grep -n -B8 -A12 "service_status_container" /usr/local/opnsense/mvc/app/views/layouts/default.volt
