#!/bin/sh
set -u
echo "########## base_form.volt 的行结构（去掉版权头） ##########"
awk 'NR>34' /usr/local/opnsense/mvc/app/views/layout_partials/base_form.volt | sed 's/^/  /' | head -70

echo
echo "########## form_input_tr（每行的渲染） ##########"
grep -rn 'form_input_tr' /usr/local/opnsense/mvc/app/views/layout_partials/*.volt | sed 's/^/  /'
F=/usr/local/opnsense/mvc/app/views/layout_partials/form_input_tr.volt
[ -f "$F" ] && awk 'NR>0' "$F" | sed 's/^/  /' | head -60

echo
echo "########## settings/get ##########"
grep -n -B2 -A14 'function getAction' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php | sed 's/^/  /'
