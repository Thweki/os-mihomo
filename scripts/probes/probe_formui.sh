#!/bin/sh
set -u
echo "=== saveFormToEndpoint / mapDataToFormUI ==="
grep -n -A35 "function saveFormToEndpoint" /usr/local/opnsense/www/js/opnsense.js
echo
echo "=== mapDataToFormUI ==="
grep -n -A40 "function mapDataToFormUI" /usr/local/opnsense/www/js/opnsense.js
echo
echo "=== setAction in ApiMutableModelControllerBase ==="
grep -n -A30 "public function setAction" /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiMutableModelControllerBase.php
