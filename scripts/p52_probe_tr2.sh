#!/bin/sh
set -u
echo "########## form_input_tr.volt: 行结构 ##########"
grep -n '<tr\|<td\|control_label_\|id="' /usr/local/opnsense/mvc/app/views/layout_partials/form_input_tr.volt | sed -n '1,40p' | sed 's/^/  /'

echo
echo "########## SettingsController 里的动作清单 ##########"
grep -n 'public function .*Action' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php | sed 's/^/  /'

echo
echo "########## get/set 动作的实现 ##########"
grep -n -A16 'function getAction\|function setAction' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php | sed 's/^/  /'
