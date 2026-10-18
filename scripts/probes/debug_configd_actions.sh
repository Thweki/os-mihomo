#!/bin/sh
set -u
echo "=== actions file perms ==="
ls -la /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf
grep -c '^\[' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf

echo
echo "=== configd.conf.d content ==="
ls -la /usr/local/opnsense/service/conf/configd.conf.d/
for f in /usr/local/opnsense/service/conf/configd.conf.d/*; do
    echo "--- $f ---"
    cat "$f"
done

echo
echo "=== how processhandler loads config ==="
grep -n -A40 "def load_config" /usr/local/opnsense/service/modules/processhandler.py | head -60

echo
echo "=== actions count ==="
configctl configd actions 2>&1 | wc -l
configctl configd actions 2>&1 | grep -c -i mihomo || true

echo
echo "=== restart configd properly ==="
service configd restart 2>&1; echo "(exit=$?)"
sleep 3
configctl configd actions 2>&1 | grep -i mihomo | head -20
echo "--- count now ---"
configctl configd actions 2>&1 | wc -l
