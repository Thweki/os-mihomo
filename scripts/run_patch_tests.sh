#!/bin/sh
# 在目标机上跑 Config::patchKeys 回归测试（只读真实配置，产出物都在 /tmp）
set -u
DIR=/tmp/mihomo-test
mkdir -p "$DIR"

if [ ! -f "$DIR/test_patch.php" ]; then
    echo "missing $DIR/test_patch.php — push it first (tools/remote.ps1 -Push)"
    exit 2
fi

echo "=== php version / gettext ==="
php -v | head -1
php -r 'echo function_exists("gettext") ? "gettext: yes\n" : "gettext: NO\n";'

echo
echo "=== run tests ==="
php "$DIR/test_patch.php" /usr/local/etc/mihomo/config.yaml
echo "EXIT=$?"
