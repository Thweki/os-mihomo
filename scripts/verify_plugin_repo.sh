#!/bin/sh
# 验证：本插件包是否被 OPNsense 自带的插件管理器识别
#
# 做法：
#   1) 把标准插件仓库目录放到本机 /usr/local/opnsense/_repo/<ABI>
#   2) 写一份仓库配置（临时 enabled: yes）
#   3) 跑「系统 > 固件 > 插件」页面所用的同一批命令，检查 os-mihomo 是否出现
set -u

BUILD=/usr/local/opnsense/_bak/pkgbuild
ABI="$(env -u ABI pkg config ABI)"
REPO_ROOT=/usr/local/opnsense/_repo
CONF=/usr/local/etc/pkg/repos/os-mihomo.conf
VER=1.1.0

echo "########## 1. 部署本地仓库目录 ##########"
rm -rf "$REPO_ROOT"
mkdir -p "$REPO_ROOT"
cp -a "$BUILD/dist/repo/$ABI" "$REPO_ROOT/"
ls -la "$REPO_ROOT/$ABI"

echo
echo "########## 2. 写仓库配置（临时启用） ##########"
mkdir -p /usr/local/etc/pkg/repos
cat > "$CONF" <<EOF
# os-mihomo 插件仓库（本机目录形式）
# 只在需要「系统 > 固件 > 插件」里一键安装/升级时才启用；
# 现网设备上若只是手工部署 WebUI，保持 enabled: no 即可。
os-mihomo: {
  url: "file://$REPO_ROOT/$ABI",
  enabled: yes,
  priority: 20
}
EOF
cat "$CONF"

echo
echo "########## 3. pkg update（只拉索引） ##########"
pkg update 2>&1 | tail -6

echo
echo "########## 4. 插件页面的数据源：configctl firmware remote ##########"
configctl firmware remote 2>&1 | grep -i mihomo || echo "(remote 列表里没有 mihomo)"
echo "--- 该条目的 9 个字段（页面按 name|||version|||comment|||flatsize|||locked|||automatic|||license|||repository|||origin 解析）---"
configctl firmware remote 2>&1 | grep -i '^os-mihomo' | awk -F'\\|\\|\\|' '{printf "  name=%s\n  version=%s\n  comment=%s\n  flatsize=%s\n  locked=%s\n  automatic=%s\n  license=%s\n  repository=%s\n  origin=%s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9}'

echo
echo "########## 5. 本地（已安装）列表应不含 mihomo ##########"
configctl firmware local 2>&1 | grep -i mihomo || echo "  正确：local 里没有 os-mihomo（本插件是手工部署的，没走 pkg）"

echo
echo "########## 6. 仓库查询（pkg rquery） ##########"
pkg rquery -r os-mihomo '%n %v %o' 'os-mihomo' 2>&1 | head -3
echo "--- 版本比较：仓库 1.1.0 vs 上游 1.0.4 ---"
pkg version -t "$VER" 1.0.4

echo
echo "########## 7. 插件存在性探测动作 ##########"
configctl firmware plugin os-mihomo 2>&1 | head -3

echo
echo "########## 8. 收尾：关闭仓库（保留文件与配置，仅改 enabled） ##########"
sed -i '' 's/^  enabled: yes,/  enabled: no,/' "$CONF"
grep -n 'enabled' "$CONF"
pkg update 2>&1 | tail -4
echo "--- 关闭后确认仓库不再被查询 ---"
pkg rquery -r os-mihomo '%n %v' 'os-mihomo' 2>&1 | head -2 || echo "  (已按预期不可用)"
