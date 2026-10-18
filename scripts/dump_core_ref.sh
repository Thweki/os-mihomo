#!/bin/sh
# Dump OPNsense core MVC reference files (views/controllers/models/partials).
set -u
cd /tmp
rm -rf core_ref
mkdir -p core_ref
for d in \
  usr/local/opnsense/mvc/app/views/layout_partials \
  usr/local/opnsense/mvc/app/views/OPNsense/Monit \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Monit \
  usr/local/opnsense/mvc/app/models/OPNsense/Monit \
  usr/local/opnsense/mvc/app/views/OPNsense/Unbound \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Unbound \
  usr/local/opnsense/mvc/app/models/OPNsense/Unbound \
  usr/local/opnsense/mvc/app/views/OPNsense/Caddy \
  usr/local/opnsense/mvc/app/models/OPNsense/Core/Menu \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Core/Menu \
  usr/local/opnsense/mvc/app/views/OPNsense/Core ; do
  if [ -e "/$d" ]; then
    tar -cf - -C / "$d" 2>/dev/null | tar -xf - -C core_ref 2>/dev/null
  else
    echo "MISSING: /$d"
  fi
done
echo "=== TREE (files) ==="
find core_ref -type f | sort
