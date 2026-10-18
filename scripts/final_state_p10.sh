#!/bin/sh
# 本轮（P10：插件包格式 + 插件管理器验证）之后的终态复核
set -u

echo "########## 1. 网络指纹 vs 基线 ##########"
printf 'pf rules  %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'baseline  b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6\n'
printf 'pf nat    %s\n' "$(pfctl -sn 2>/dev/null | sha256 -q)"
printf 'baseline  3bc6b546843e7c1857ccfd12be7df053525e20e79a32e7e7454702cd05afd385\n'
printf 'routes    %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'baseline  46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619\n'
printf 'unbound   %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
printf 'baseline  1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532\n'

echo
echo "########## 2. 服务与自启 ##########"
cat /etc/rc.conf.d/mihomo
service mihomo status 2>&1 | head -1
echo "--- 监听 / TUN / 进程 ---"
sockstat -4 -l 2>/dev/null | egrep 'mihomo|:9090|:7891|:1053' || echo "  (无 mihomo 监听)"
ifconfig 2>/dev/null | grep -c tun_mihomo | sed 's/^/  tun_mihomo 接口数: /'
pgrep -l -f '/usr/local/bin/mihomo' | head -3 || echo "  (无 mihomo 进程)"

echo
echo "########## 3. 插件包/仓库状态（本轮改动） ##########"
echo "--- 仓库配置 ---"
cat /usr/local/etc/pkg/repos/os-mihomo.conf
echo "--- 本插件是否进了 pkg 数据库 ---"
pkg info os-mihomo 2>&1 | head -2
echo "--- 启用中的仓库 ---"
pkg -vv 2>/dev/null | awk '/^Repositories:/,0' | grep -E '^  [A-Za-z0-9_-]+: \{' | tr '\n' ' '
echo
echo "--- 仓库缓存目录 ---"
ls -1 /var/db/pkg/repos/
echo "--- pkg search 结果（应只剩上游 1.0.4）---"
pkg search -q os-mihomo 2>&1

echo
echo "########## 4. 保留物 ##########"
du -sh /usr/local/opnsense/_bak/os-mihomo-repo 2>/dev/null
ls -1 /usr/local/opnsense/_bak/os-mihomo-repo/*/ 2>/dev/null | head -8
echo "--- 部署备份集 ---"
ls -1 /usr/local/opnsense/_bak/os-mihomo/
echo "--- 词库备份 ---"
ls -1 /usr/local/opnsense/_bak/os-mihomo-i18n/ 2>/dev/null

echo
echo "########## 5. 临时残留 ##########"
ls -d /tmp/drill-* /tmp/mihomo-* /tmp/repo-test /tmp/os-mihomo-* /tmp/script-check.sh 2>/dev/null || echo "  (clean)"

echo
echo "########## 6. 负载与出网 ##########"
uptime | sed 's/^/  /'
echo -n "  进程数: "; ps -ax | wc -l | tr -d ' '
echo -n "  DNS 自检: "; host -W 3 -t a www.freebsd.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  HTTP 自检: "; curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/ui/mihomo
