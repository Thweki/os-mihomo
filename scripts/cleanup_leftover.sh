#!/bin/sh
# 杀掉残留的 __remote.sh 进程，并对比"仅配置类"的接口指纹
set -u

echo "=== 1. 逐个清理残留 ==="
for i in 1 2 3 4 5; do
    pids=$(ps -ax -o pid,command 2>/dev/null | awk '/[ _]remote\.sh/ && !/awk/ {print $1}')
    [ -z "$pids" ] && break
    echo "round $i: killing $pids"
    kill -9 $pids 2>/dev/null || true
    sleep 1
done
ps -ax -o pid,command 2>/dev/null | grep '[_]remote.sh' || echo "clean: no leftover"

echo
echo "=== 2. 进程总数与负载 ==="
echo "processes: $(ps -ax 2>/dev/null | wc -l)"
uptime

echo
echo "=== 3. 接口「配置」指纹（排除计数器/状态）==="
ifconfig -a 2>/dev/null | grep -E '^[a-z0-9_.]+:|inet |inet6 |ether |mtu |flags|status:' | sha256 -q
echo "(baseline-cfg see below)"

echo
echo "=== 4. 接口清单 ==="
ifconfig -l

echo
echo "=== 5. 接口地址 ==="
ifconfig -a 2>/dev/null | grep -E '^[a-z0-9_.]+:|inet ' | head -40
