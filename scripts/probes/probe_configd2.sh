#!/bin/sh
set -u
echo "=== search allowed_groups everywhere ==="
find /usr/local/opnsense/service -type f -name '*.py' -exec grep -ln "allowed_groups" {} \; 2>/dev/null
echo "--- context ---"
find /usr/local/opnsense/service -type f -name '*.py' -exec grep -n -B5 -A20 "allowed_groups" {} \; 2>/dev/null | head -60
echo
echo "=== configd.conf (socket perms) ==="
cat /usr/local/opnsense/service/conf/configd.conf 2>/dev/null
echo
echo "=== does configctl exist / how it connects ==="
ls -l /usr/local/sbin/configctl
head -30 /usr/local/sbin/configctl 2>/dev/null
