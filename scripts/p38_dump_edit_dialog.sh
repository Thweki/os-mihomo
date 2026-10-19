#!/bin/sh
set -u
echo "########## opnsense_bootgrid.js: show_edit_dialog + 填表 ##########"
sed -n '2040,2160p' /usr/local/opnsense/www/js/opnsense_bootgrid.js | sed 's/^/  /'

echo
echo "########## 填表函数（setFormValues / fillForm 之类） ##########"
grep -n 'set_values\|fillForm\|setForm\|each(function\|checkbox\|selectpicker' /usr/local/opnsense/www/js/opnsense_bootgrid.js | sed -n '1,40p' | sed 's/^/  /'
