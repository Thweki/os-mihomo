#!/bin/sh
# 在目标机上构建 os-mihomo 包（只构建，不安装）
set -u

BUILD=/usr/local/opnsense/_bak/pkgbuild
EXPECTED=fd4ffdd64d379f046dc1863df91329b1ab37e4fc8bb0aac95a1ef97c69c3d290

echo "=== 1. 内核二进制摘要核对 ==="
ACTUAL=$(sha256 -q "$BUILD/src/usr/local/bin/clash-meta-freebsd-amd64.xz")
echo "  actual  : $ACTUAL"
echo "  expected: $EXPECTED"
if [ "$ACTUAL" = "$EXPECTED" ]; then echo "  => 匹配"; else echo "  => 不匹配（构建会失败）"; fi

echo
echo "=== 2. 版本号 ==="
grep -n 'VERSION' "$BUILD/Makefile"
cat "$BUILD/src/usr/local/opnsense/version/mihomo"
echo

echo "=== 3. 开始构建（make package）==="
cd "$BUILD" || exit 1
make package 2>&1 | tail -40
RC=$?
echo "make exit=$RC"

echo
echo "=== 4. 产物 ==="
ls -la "$BUILD/dist/" 2>/dev/null || echo "(no dist)"