#!/bin/sh
# 复核：服务 / 仓库 / 指纹 / 缓存
set -u
echo "--- 服务自启开关 ---"
cat /etc/rc.conf.d/mihomo
echo "--- 仓库配置的 enabled 行 ---"
grep enabled /usr/local/etc/pkg/repos/os-mihomo.conf | tail -1
echo "--- pf 指纹（应与基线一致）---"
echo "current:  $(pfctl -sr 2>/dev/null | sha256 -q)"
echo "baseline: b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6"
echo "--- 仓库缓存 ---"
ls -1 /var/db/pkg/repos/
echo "--- pkg search ---"
pkg search -q os-mihomo
echo "--- /tmp 残留 ---"
ls -d /tmp/mihomo-* /tmp/os-mihomo-* /tmp/drill-* /tmp/repo-test 2>/dev/null || echo "(clean)"
