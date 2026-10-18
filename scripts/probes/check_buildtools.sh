#!/bin/sh
# 检查目标机的 pkg 构建工具链
set -u

echo "=== 构建工具 ==="
for cmd in pkg tar make xz sha256 curl fetch install sed awk find wc mktemp; do
    p=$(command -v "$cmd" 2>/dev/null || echo "")
    if [ -n "$p" ]; then printf '  %-8s %s\n' "$cmd" "$p"; else printf '  %-8s MISSING\n' "$cmd"; fi
done

echo
echo "=== 版本 ==="
pkg -v 2>/dev/null || echo "(pkg -v failed)"
freebsd-version 2>/dev/null

echo
echo "=== 磁盘空间 ==="
df -h /usr/local | tail -1
df -h /tmp | tail -1

echo
echo "=== 是否已有构建目录 ==="
ls -la /usr/local/opnsense/_bak/ 2>/dev/null
