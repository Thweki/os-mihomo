#!/bin/sh
# 列出设置页里所有 mihomo.* 的字段 id（用于核对静态清单与运行时锁的数量差）
set -u
grep -o 'id="mihomo[^"]*"' /tmp/p65-settings.html 2>/dev/null | sort -u | tr '\n' ' '
echo
echo "---- 计数 ----"
grep -o 'id="mihomo[^"]*"' /tmp/p65-settings.html 2>/dev/null | sort -u | wc -l
