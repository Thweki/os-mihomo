#!/bin/sh
# Fetch configd + Backend implementation for local study.
set -u
cd /tmp
rm -rf ctl_ref
mkdir -p ctl_ref
for f in \
  usr/local/opnsense/mvc/app/library/OPNsense/Core/Backend.php \
  usr/local/opnsense/service/modules/actions/base.py \
  usr/local/opnsense/service/modules/processhandler.py ; do
  tar -cf - -C / "$f" 2>/dev/null | tar -xf - -C ctl_ref 2>/dev/null
done
find ctl_ref -type f | sort
