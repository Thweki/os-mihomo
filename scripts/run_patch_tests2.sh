#!/bin/sh
# 把改进后的补丁器 + 测试推到临时目录并跑回归
set -u
DIR=/tmp/mihomo-test
mkdir -p "$DIR"
echo "=== php -l ==="
php -l "$DIR/Config.php"
php -l "$DIR/test_patch.php"
echo
echo "=== 回归测试（对已安装的真实 config.yaml）==="
php "$DIR/test_patch.php" /usr/local/etc/mihomo/config.yaml
echo "EXIT=$?"
