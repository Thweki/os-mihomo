#!/bin/sh
# 最终收尾：停 demo、清日志、复位、体检
set -u

echo "=== 1. 停止 demo 与长连接 ==="
pkill -f 'speed.cloudflare.com' 2>/dev/null || true
if [ -f /var/run/mihomo-demo.pid ]; then
    pid=$(cat /var/run/mihomo-demo.pid 2>/dev/null || echo '')
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    sleep 2
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
    rm -f /var/run/mihomo-demo.pid
fi
pkill -f 'mihomo-demo' 2>/dev/null || true
sleep 2
ps -ax -o pid,command 2>/dev/null | grep -v grep | grep mihomo || echo "(no mihomo process)"

echo
echo "=== 2. 清日志与临时文件 ==="
configctl mihomo log-clear mihomo
configctl mihomo log-clear subscription
rm -rf /tmp/mihomo-demo /tmp/mihomo-test /tmp/mihomo-stage /tmp/conn.json /tmp/menu_page.html /tmp/menu_test_jar.txt 2>/dev/null || true
ls -d /tmp/mihomo* 2>/dev/null || echo "(clean)"
wc -l /var/log/mihomo.log /var/log/mihomo_sub.log 2>/dev/null

echo
echo "=== 3. 保留最近 3 组备份，清理更早的 ==="
ls -1d /usr/local/opnsense/_bak/os-mihomo/*/ 2>/dev/null | head -n -3 | while read -r d; do
    echo "  removing $d"
    rm -rf "$d"
done
ls -1d /usr/local/opnsense/_bak/os-mihomo/*/ 2>/dev/null

echo
echo "=== 4. 最终状态 ==="
echo "--- 服务 ---"; service mihomo status
echo "--- 自启 ---"; cat /etc/rc.conf.d/mihomo
echo "--- 端口 ---"; sockstat -4 -l 2>/dev/null | egrep ':9090|:17890' || echo "(无 mihomo 监听)"
echo "--- TUN ---"; ifconfig -l | tr ' ' '\n' | grep -i tun || echo "(无 tun)"
echo "--- config.yaml 受管键 ---"
grep -nE '^(log-level|mode|allow-lan|external-controller|secret):' /usr/local/etc/mihomo/config.yaml
echo "--- 备份数 ---"; ls -1 /usr/local/etc/mihomo/config.yaml.bak.* 2>/dev/null | wc -l

echo
echo "=== 5. 网络指纹（与基线比对）==="
printf 'pf rules  %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'baseline  b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6\n'
printf 'routes    %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'baseline  46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619\n'
printf 'unbound   %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
printf 'baseline  1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532\n"

echo
echo "=== 6. 负载与进程 ==="
uptime
echo "processes: $(ps -ax 2>/dev/null | wc -l)"
