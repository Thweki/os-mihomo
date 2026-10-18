#!/bin/sh
# 取证 8：firmware local/remote 动作打印哪些字段 + 本包是否已进 pkg 数据库
set -u

echo "=== [local] / [remote] 动作定义 ==="
sed -n '/^\[local\]/,/^$/p;/^\[remote\]/,/^$/p;/^\[plugin\]/,/^$/p' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf

echo
echo "=== remote.sh / local.sh ==="
for f in remote.sh local.sh; do
    p=/usr/local/opnsense/scripts/firmware/$f
    if [ -f "$p" ]; then echo "--- $p ---"; cat "$p"; else echo "--- $p (不存在) ---"; fi
done

echo
echo "=== os-mihomo 是否在 pkg 数据库里 ==="
pkg info os-mihomo 2>&1 | head -5 || true
pkg query -g '%n %v' 'os-mihomo' 2>&1 | head -3 || true

echo
echo "=== 已安装插件 ==="
pkg query -g '%n %v' 'os-*' 2>&1 | tr '\n' ' '
echo
