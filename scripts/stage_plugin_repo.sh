#!/bin/sh
# 整理保留物：把插件仓库放到 _bak 下（与备份/构建产物同一区），配置指向它
set -u

ABI="$(env -u ABI pkg config ABI)"
SRC=/usr/local/opnsense/_bak/pkgbuild/dist/repo/$ABI
DST=/usr/local/opnsense/_bak/os-mihomo-repo
CONF=/usr/local/etc/pkg/repos/os-mihomo.conf

echo "########## 1. 当前状态 ##########"
echo "--- /usr/local/opnsense/_repo ---"
find /usr/local/opnsense/_repo 2>/dev/null | head -10
echo "--- 构建区里的仓库 ---"
ls -la "$SRC" 2>/dev/null

echo
echo "########## 2. 重新整理 ##########"
rm -rf /usr/local/opnsense/_repo
rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRC" "$DST/"
ls -la "$DST/$ABI"
du -sh "$DST"

echo
echo "########## 3. 重写仓库配置（仍保持 enabled: no） ##########"
cat > "$CONF" <<EOF
# os-mihomo 插件仓库（本机目录形式）
#
# 启用后，「系统 > 固件 > 插件」就能一键安装/升级/卸载 os-mihomo。
#   · 现网设备若只是手工部署 WebUI（scripts/deploy.sh），保持 enabled: no 即可
#   · 想用插件管理器：把下面改成 enabled: yes，然后执行 pkg update
#
# 注意：经由插件管理器安装会执行包内 +POST_INSTALL，
#       它会向 config.xml 添加 tun_mihomo 接口与一条防火墙放行规则，
#       并把 Unbound 转发指向 127.0.0.1:1053 —— 请先确认你接受这些改动。
os-mihomo: {
  url: "file://$DST/$ABI",
  enabled: no,
  priority: 20
}
EOF
cat "$CONF"

echo
echo "########## 4. 校验：仓库元数据可读、包名版本一致 ##########"
pkg info -F "$DST/$ABI/os-mihomo-1.1.0.pkg" 2>&1 | head -6
echo "--- meta.conf ---"
head -3 "$DST/$ABI/meta.conf"
echo "--- 与实际文件对照 ---"
ls -1 "$DST/$ABI"

echo
echo "########## 5. 最终系统状态 ##########"
echo -n "启用中的仓库: "; pkg -vv 2>/dev/null | awk '/^Repositories:/,0' | grep -B0 -A1 'enabled *: "yes"\|enabled *: yes' | grep -E '^  \S+:' | tr '\n' ' '
echo
pkg update 2>&1 | tail -3
echo -n "pkg search os-mihomo: "; pkg search -q os-mihomo 2>&1 | tr '\n' ' '
echo
echo -n "mihomo 服务: "; service mihomo status 2>&1 | head -1
