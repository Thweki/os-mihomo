#!/bin/sh
# 前端服务控件如何消费 status（决定「未启用自启」时能否点启动）
set -u

echo "=== 找 updateServiceControlUI 的实现 ==="
grep -rln 'updateServiceControlUI' /usr/local/opnsense/www/js/ /usr/local/opnsense/mvc/app/views/ 2>/dev/null | head -5

echo
echo "=== 相关片段 ==="
for f in $(grep -rln 'function updateServiceControlUI' /usr/local/opnsense/www/js/ 2>/dev/null | head -2); do
    echo "--- $f ---"
    awk '/function updateServiceControlUI/,/^}/' "$f" | head -60
done
