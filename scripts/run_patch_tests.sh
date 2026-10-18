#!/bin/sh
# 项目回归测试：Config 补丁器 + 路由策略（只用确定性夹具，绝不读取线上配置）
#
# 夹具: /tmp/mihomo-test/fixture-config.yaml  ← 由 tools/remote.ps1 推送仓库里的随包配置
set -u
DIR=/tmp/mihomo-test
FIXTURE="$DIR/fixture-config.yaml"

mkdir -p "$DIR"

if [ ! -f "$DIR/test_patch.php" ]; then
    echo "missing $DIR/test_patch.php — push it first (tools/remote.ps1 -Push)"
    exit 2
fi
if [ ! -f "$FIXTURE" ]; then
    echo "missing $FIXTURE — push src/usr/local/etc/mihomo/config.yaml first"
    exit 2
fi

echo "=== php version / gettext ==="
php -v | head -1
php -r 'echo function_exists("gettext") ? "gettext: yes\n" : "gettext: NO\n";'

echo
echo "=== fixture ==="
echo "  $FIXTURE ($(grep -c . "$FIXTURE") 行, sha256 $(sha256 -q "$FIXTURE"))"

echo
echo "=== run tests ==="
php "$DIR/test_patch.php" "$FIXTURE"
echo "EXIT=$?"
