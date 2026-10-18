#!/bin/sh
# Verify OPNsense framework semantics we depend on (read-only).
set -u

echo "=== ACL match implementation ==="
grep -rn "isPageAccessible\|function matchAcl\|preg_match.*pattern" /usr/local/opnsense/mvc/app/library/OPNsense/Auth/ 2>/dev/null | head -20
echo "--- Access.php sources ---"
ls /usr/local/opnsense/mvc/app/library/OPNsense/Auth/ 2>/dev/null
sed -n '1,200p' /usr/local/opnsense/mvc/app/library/OPNsense/Auth/Access.php 2>/dev/null | grep -n "pattern" | head -20

echo
echo "=== Base ApiMutableModelControllerBase methods ==="
grep -n "public function" /usr/local/opnsense/mvc/app/library/OPNsense/Base/ApiMutableModelControllerBase.php 2>/dev/null | head -30
echo "--- ApiMutableServiceControllerBase ---"
grep -n "public function\|protected function" /usr/local/opnsense/mvc/app/library/OPNsense/Base/ApiMutableServiceControllerBase.php 2>/dev/null | head -30

echo
echo "=== Base IndexController (getForm) ==="
grep -n "function" /usr/local/opnsense/mvc/app/library/OPNsense/Base/IndexController.php 2>/dev/null

echo
echo "=== Unbound settings API controller (reference) ==="
sed -n '30,80p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Unbound/Api/SettingsController.php 2>/dev/null

echo
echo "=== A model xml sample (Cron) head ==="
sed -n '1,40p' /usr/local/opnsense/mvc/app/models/OPNsense/Cron/Cron.xml 2>/dev/null

echo
echo "=== Menu.xml core VPN section ==="
sed -n '112,132p' /usr/local/opnsense/mvc/app/models/OPNsense/Core/Menu/Menu.xml 2>/dev/null

echo
echo "=== does /ui/js/bootstrap-dialog exist? theme files ==="
ls /usr/local/opnsense/www/themes/ 2>/dev/null
ls /usr/local/opnsense/www/js/ 2>/dev/null | head -30

echo
echo "=== configd actions: is 'mihomo' registered? (os-ddns-go for comparison) ==="
ls /usr/local/opnsense/service/conf/actions.d/ 2>/dev/null

echo
echo "=== DONE ==="
