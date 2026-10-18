#!/bin/sh
# 恢复上游原始 config.yaml（含中文注释），用于验证「最小改动」的 Apply
set -u

ORIG=/usr/local/opnsense/_bak/os-mihomo/20261018_112302/usr/local/etc/mihomo/config.yaml
echo "=== 备份中的原始文件 ==="
ls -la "$ORIG"
grep -n '^log-level' "$ORIG"
grep -n '^external-controller' "$ORIG"

echo
echo "=== 恢复 ==="
cp -a "$ORIG" /usr/local/etc/mihomo/config.yaml
chmod 0644 /usr/local/etc/mihomo/config.yaml
chown root:wheel /usr/local/etc/mihomo/config.yaml
grep -n '^log-level' /usr/local/etc/mihomo/config.yaml
grep -n '^external-controller' /usr/local/etc/mihomo/config.yaml

echo
echo "=== 重跑补丁器回归（夹具现在带中文注释）==="
php /tmp/mihomo-test/test_patch.php /usr/local/etc/mihomo/config.yaml 2>&1 | grep -E 'FAIL|汇总'
