#!/bin/sh
set -u
echo "########## 1. 有没有 CSVListField ##########"
ls /usr/local/opnsense/mvc/app/models/OPNsense/Base/FieldTypes/ | sed 's/^/  /'

echo
echo "########## 2. base_form 局部模板 ##########"
cat /usr/local/opnsense/mvc/app/views/layout_partials/base_form.volt | sed 's/^/  /'

echo
echo "########## 3. settings/get 的实现 ##########"
grep -n -A12 'function getAction' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php | sed 's/^/  /'
