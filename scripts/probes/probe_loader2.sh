#!/bin/sh
set -u
echo "=== loader.php ==="
cat /usr/local/opnsense/mvc/app/config/loader.php
echo
echo "=== config.php head ==="
sed -n '1,80p' /usr/local/opnsense/mvc/app/config/config.php
