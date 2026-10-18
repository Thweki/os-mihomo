#!/bin/sh
set -u
echo "=== allowed_groups usage in configd ==="
grep -rn "allowed_groups" /usr/local/opnsense/service/*.py /usr/local/opnsense/service/**/*.py 2>/dev/null | head -20
echo
echo "=== how does configd resolve the calling user? ==="
grep -rn "SO_PEERCRED\|peercred\|getpeereid\|getuser\|pwd.getpwuid" /usr/local/opnsense/service/*.py 2>/dev/null | head -20
echo
echo "=== actions_monit.conf (full) ==="
cat /usr/local/opnsense/service/conf/actions.d/actions_monit.conf
echo
echo "=== actions_cron.conf (full) ==="
cat /usr/local/opnsense/service/conf/actions.d/actions_cron.conf
echo
echo "=== whoami / groups of php-fpm child ==="
id www
echo
echo "=== configd acl implementation detail ==="
grep -rn -A15 "def check_acl\|def _check_permission\|allowed_groups" /usr/local/opnsense/service/configd.py 2>/dev/null | head -40
echo
echo "=== configd lib dir ==="
ls -R /usr/local/opnsense/service/ 2>/dev/null | head -40
