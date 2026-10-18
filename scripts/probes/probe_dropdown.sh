#!/bin/sh
set -u
echo "=== forms using dropdown vs select_multiple ==="
grep -rl "<type>dropdown</type>" /usr/local/opnsense/mvc/app/controllers/OPNsense/*/forms/*.xml | head -5
echo "--- example: an OptionField-backed dropdown ---"
grep -rn -B4 -A2 "<type>dropdown</type>" /usr/local/opnsense/mvc/app/controllers/OPNsense/Unbound/forms/*.xml | head -30
echo
echo "=== ids used with dropdown in Unbound forward.xml ==="
sed -n '1,40p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Unbound/forms/forward.xml
echo
echo "=== corresponding model field type ==="
grep -n -A12 "<forwarding>" /usr/local/opnsense/mvc/app/models/OPNsense/Unbound/Unbound.xml | head -25
