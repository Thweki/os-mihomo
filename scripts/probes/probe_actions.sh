#!/bin/sh
set -u
echo "=== actions with %s placeholders (format reference) ==="
grep -rn -B3 -A3 '%s' /usr/local/opnsense/service/conf/actions.d/actions_unbound.conf /usr/local/opnsense/service/conf/actions.d/actions_dns.conf /usr/local/opnsense/service/conf/actions.d/actions_template.conf 2>/dev/null | head -60
echo
echo "=== full actions_dns.conf (short) ==="
cat /usr/local/opnsense/service/conf/actions.d/actions_dns.conf 2>/dev/null
echo
echo "=== full actions_template.conf ==="
cat /usr/local/opnsense/service/conf/actions.d/actions_template.conf 2>/dev/null
echo
echo "=== tail binary path ==="
ls -l /usr/bin/tail 2>/dev/null || which tail
