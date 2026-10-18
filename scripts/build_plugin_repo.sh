#!/bin/sh
# 在设备上重新构建（原生 ABI）+ 生成标准插件仓库目录，并审计清单
set -u
BUILD=/usr/local/opnsense/_bak/pkgbuild
cd "$BUILD" || exit 1
chmod 0755 build.sh scripts/make_repo.sh

echo "########## 1. make package（ABI=native）##########"
make package 2>&1 | tail -12

echo
echo "########## 2. make repo ##########"
make repo 2>&1 | tail -25

echo
echo "########## 3. 包清单审计（插件管理器关心的字段）##########"
pkg info -F "$BUILD/dist/os-mihomo.pkg" 2>&1 | head -14
echo "--- 原始清单里的关键字段 ---"
tar -xOf "$BUILD/dist/os-mihomo.pkg" +MANIFEST 2>/dev/null | \
    grep -E '^(name|origin|version|comment|maintainer|www|abi|arch|prefix|flatsize|licenses)|^annotations|repo_type|repository|^scripts' | head -20

echo
echo "########## 4. 仓库目录 ##########"
ls -la "$BUILD/dist/repo/" 2>/dev/null
ls -la "$BUILD/dist/repo/"*/ 2>/dev/null

echo
echo "########## 5. 仓库能否被 pkg 索引读取（用 file:// 试探，不安装）##########"
if [ -f "$BUILD/dist/repo/$(env -u ABI pkg config ABI)/meta.conf" ]; then
    echo "meta.conf 存在"
    head -5 "$BUILD/dist/repo/$(env -u ABI pkg config ABI)/meta.conf"
fi
