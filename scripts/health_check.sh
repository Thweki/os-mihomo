#!/bin/sh
# 体检：确认递归事故未影响网络功能
set -u

echo "=== 1. 残留进程 ==="
ps -ax -o pid,command 2>/dev/null | grep '[_]remote.sh' && echo "!! 仍有残留" || echo "无残留"
echo "总进程数: $(ps -ax 2>/dev/null | wc -l)"

echo
echo "=== 2. 负载 ==="
uptime

echo
echo "=== 3. DNS 解析（走本机 Unbound）==="
host www.baidu.com 127.0.0.1 2>&1 | head -3 || echo "(host failed)"
drill @127.0.0.1 www.baidu.com 2>/dev/null | grep -E 'rcode|ANSWER' | head -3 || true

echo
echo "=== 4. Unbound 进程与套接字 ==="
ps -ax -o pid,command 2>/dev/null | grep '[u]nbound' | head -3
sockstat -4 -l 2>/dev/null | grep -c ':53 '

echo
echo "=== 5. 出网测试 ==="
curl -s -o /dev/null -m 8 -w 'HTTP %{http_code} in %{time_total}s\n' http://www.baidu.com/ || echo "(curl failed)"

echo
echo "=== 6. 客户端网段连通性（LAN 网关自身）==="
ifconfig igb1 2>/dev/null | grep -E 'inet |status' | head -3

echo
echo "=== 7. 防火墙 / 路由 / DNS 指纹（应与基线一致）==="
printf 'pf rules   %s (baseline b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6)\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'routes     %s (baseline 46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619)\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'ifconfig   %s (baseline ded302a7054170e2567dd059d2630a16c1dfea8b54b98459fa7ee2055bef67c0)\n' "$(ifconfig -a 2>/dev/null | sha256 -q)"
printf 'unbound    %s (baseline 1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532)\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
printf 'config.xml %s\n' "$(sha256 -q /conf/config.xml)"

echo
echo "=== 8. 关键服务 ==="
for s in unbound configd lighttpd; do
    printf '%-10s %s\n' "$s" "$(service $s status 2>&1 | head -1)"
done
