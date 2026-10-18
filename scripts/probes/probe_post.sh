#!/bin/sh
set -u
echo "=== find code that fills \$_POST from the raw body ==="
grep -rn 'php://input' /usr/local/opnsense/mvc/app /usr/local/www/*.php 2>/dev/null | head -20
echo
echo "=== opnsense_gui entry ==="
ls -la /usr/local/www/ | head -30
echo
grep -rn 'php://input\|\$_POST' /usr/local/opnsense/mvc/app/config/*.php 2>/dev/null | head
echo
echo "=== check ui.ini / di ==="
ls /usr/local/opnsense/mvc/app/config/
echo
echo "=== grep json in mvc config ==="
grep -rn 'json' /usr/local/opnsense/mvc/app/config/*.php | head
