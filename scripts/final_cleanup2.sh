#!/bin/sh
# 清理多余备份与 /tmp 残留，并给出最终状态
set -u

echo "=== 1. 保留最新 3 组备份 ==="
cd /usr/local/opnsense/_bak/os-mihomo/ || exit 1
ls -1d */ | sort | sed -n '1,$p' | awk 'NR>3' | while read -r d; do
    echo "  removing $d"
    rm -rf "$d"
done
echo "剩余备份："
ls -1d */ 2>/dev/null

echo
echo "=== 2. 清理 /tmp 上的临时配置文件 ==="
rm -f /tmp/mihomo-* 2>/dev/null || true
ls -d /tmp/mihomo* 2>/dev/null || echo "(clean)"

echo
echo "=== 3. 最终状态 ==="
echo "--- 服务 ---"; service mihomo status
echo "--- 自启 ---"; cat /etc/rc.conf.d/mihomo
echo "--- 监听 ---"; sockstat -4 -l 2>/dev/null | egrep ':9090|:17890|:1053' || echo "(无 mihomo 监听)"
echo "--- TUN ---"; ifconfig -l | tr ' ' '\n' | grep -i tun || echo "(无 tun 接口)"
echo "--- config.yaml 受管键 ---"
grep -nE '^(log-level|mode|allow-lan|external-controller|secret):' /usr/local/etc/mihomo/config.yaml
echo "--- 配置备份数 ---"; ls -1 /usr/local/etc/mihomo/config.yaml.bak.* 2>/dev/null | wc -l

echo
echo "=== 4. 网络指纹比对 ==="
printf 'pf rules  %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'baseline  b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6\n'
printf 'pf nat    %s\n' "$(pfctl -sn 2>/dev/null | sha256 -q)"
printf 'baseline  3bc6b546843e7c1857ccfd12be7df053525e20e79a32e7e7454702cd05afd385\n'
printf 'routes    %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'baseline  46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619\n'
printf 'unbound   %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
printf 'baseline  1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532\n'

echo
echo "=== 5. 负载 / 进程 ==="
uptime
echo "processes: $(ps -ax 2>/dev/null | wc -l)"
echo
echo "=== 6. DNS 与出网自检 ==="
host www.baidu.com 127.0.0.1 > /dev/null 2>&1 && echo "DNS: OK" || echo "DNS: FAIL"
curl -s -o /dev/null -m 8 -w 'HTTP %{http_code}\n' http://www.baidu.com/ || echo "HTTP: FAIL"
