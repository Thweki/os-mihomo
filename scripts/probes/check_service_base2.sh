#!/bin/sh
# 基类的 statusAction 与 serviceEnabled
set -u
F=/usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ApiMutableServiceControllerBase.php

echo "=== statusAction 全文 ==="
sed -n '/public function statusAction/,/^    }/p' "$F"

echo
echo "=== serviceEnabled 全文 ==="
sed -n '/function serviceEnabled/,/^    }/p' "$F"

echo
echo "=== internalServiceEnabled 的用法 ==="
grep -n 'internalServiceEnabled\|serviceEnabled()' "$F"
