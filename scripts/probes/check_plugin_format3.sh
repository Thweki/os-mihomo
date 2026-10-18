#!/bin/sh
# 取证 3：固件/插件管理器侧细节 + pkg repo 生成能力
set -u

echo "########## 1. 固件系统对 os-* 包的分支处理 ##########"
sed -n '25,70p' /usr/local/opnsense/scripts/firmware/install.sh

echo
echo "########## 2. 插件页面实现（列表来源） ##########"
ls -1 /usr/local/www/ | grep -i 'firmware' | head
echo "--- firmware_plugins.php 关键行 ---"
grep -nE 'configd|pkg |plugins|search' /usr/local/www/firmware_plugins.php 2>/dev/null | head -15
echo "--- 对应的 configd 动作 ---"
grep -n -A5 'plugins' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf 2>/dev/null | head -30

echo
echo "########## 3. opnwall 仓库里都有什么（含 os-mihomo） ##########"
pkg rquery -r opnwall '%n %v %c' 'os-*' 2>&1 | sort | head -20
echo "--- 官方 OPNsense 仓库里的 os-mihomo ---"
pkg rquery -r OPNsense '%n %v %c' 'os-mihomo' 2>&1 | head -5

echo
echo "########## 4. ABI ##########"
echo -n "pkg config abi : "; pkg config abi
echo -n "pkg config arch: "; pkg config arch 2>/dev/null || echo "(n/a)"
echo -n "uname -K       : "; uname -K

echo
echo "########## 5. pkg repo 能否生成仓库元数据 ##########"
rm -rf /tmp/repo-test && mkdir -p /tmp/repo-test
cp /usr/local/opnsense/_bak/pkgbuild/dist/os-mihomo.pkg /tmp/repo-test/ 2>/dev/null
pkg repo /tmp/repo-test 2>&1 | head -10
echo "--- 生成结果 ---"
ls -la /tmp/repo-test

echo
echo "########## 6. 我们的 +POST_INSTALL 结尾（是否重启 configd） ##########"
tail -20 /usr/local/opnsense/_bak/pkgbuild/packaging/freebsd/+POST_INSTALL

echo
echo "########## 7. 本机 build.sh 的 ABI/ARCH 处理 ##########"
grep -nE 'ABI|ARCH|pkg create|--abi|-o ' /usr/local/opnsense/_bak/pkgbuild/build.sh | head -20
