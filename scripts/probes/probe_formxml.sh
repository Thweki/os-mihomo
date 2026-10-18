#!/bin/sh
set -u
echo "=== ControllerBase::parseFormNode ==="
grep -n -A70 "private function parseFormNode" /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerBase.php
echo
echo "=== a form xml WITH sections (example) ==="
grep -rln "<section>" /usr/local/opnsense/mvc/app/controllers/OPNsense/*/forms/*.xml | head -5
