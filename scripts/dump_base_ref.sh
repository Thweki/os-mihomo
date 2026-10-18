#!/bin/sh
# Pull the OPNsense base controller classes + ACL model for local study.
set -u
cd /tmp
rm -rf base_ref
mkdir -p base_ref
for f in \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiMutableServiceControllerBase.php \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiMutableModelControllerBase.php \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiControllerBase.php \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/IndexController.php \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerRoot.php \
  usr/local/opnsense/mvc/app/models/OPNsense/Core/ACL.php \
  usr/local/opnsense/mvc/app/controllers/OPNsense/Core/Api/DiagnosticsController.php \
  usr/local/opnsense/mvc/app/models/OPNsense/Base/BaseModel.php \
  usr/local/opnsense/mvc/app/models/OPNsense/Core/FieldTypes/JsonKeyValueStoreField.php ; do
  tar -cf - -C / "$f" 2>/dev/null | tar -xf - -C base_ref 2>/dev/null
done
find base_ref -type f | sort
