#!/bin/sh
set -u
echo "=== ApiMutableModelControllerBase: save/validate/getModel/hasPost ==="
grep -n "protected function save\|public function save\|protected function validate\|public function validate\|private function save\|function getModel" -A12 /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiMutableModelControllerBase.php | head -70
echo
echo "=== getFormData definition ==="
grep -rn "getFormData" /usr/local/opnsense/www/js/*.js | head -5
grep -rn -A30 "getFormData = " /usr/local/opnsense/www/js/opnsense_ui.js | head -45
