#!/bin/sh
# Dump the author's existing MVC plugins (Ddnsgo, Ttyd) for style reference.
set -u
cd /tmp
rm -rf mvc_ref
mkdir -p mvc_ref
for d in \
  usr/local/opnsense/mvc/app/models/OPNsense/Ddnsgo \
  usr/local/opnsense/mvc/app/models/OPNsense/Ttyd \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Ddnsgo \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Ttyd \
  usr/local/opnsense/mvc/app/views/OPNsense/Ddnsgo \
  usr/local/opnsense/mvc/app/views/OPNsense/Ttyd \
  usr/local/opnsense/service/conf/actions.d/actions_ddnsgo.conf \
  usr/local/opnsense/service/conf/actions.d/actions_ttyd.conf ; do
  if [ -e "/$d" ]; then
    tar -cf - -C / "$d" 2>/dev/null | tar -xf - -C mvc_ref 2>/dev/null
  else
    echo "MISSING: /$d"
  fi
done
echo "=== TREE ==="
find mvc_ref -type f | sort
echo
echo "=== SIZES ==="
find mvc_ref -type f -exec wc -l {} \; | sort -k2
