#!/bin/sh
set -u
cd /tmp
rm -rf form_ref
mkdir -p form_ref
for f in \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerBase.php \
  usr/local/opnsense/mvc/app/library/OPNsense/Base/Form.php \
  usr/local/opnsense/mvc/app/library/OPNsense/Base/FieldTypes/BaseField.php ; do
  tar -cf - -C / "$f" 2>/dev/null | tar -xf - -C form_ref 2>/dev/null
done
find form_ref -type f
echo "--- getForm implementation ---"
grep -n -A20 "function getForm" form_ref/usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerBase.php
