#!/bin/sh
# 紧急：清除由脚本递归产生的 __remote.sh 进程，并确认系统恢复正常
set -u

echo "=== 当前 __remote.sh 进程数 ==="
ps -ax -o pid,command 2>/dev/null | grep -c '[_]remote.sh' || true

echo "=== 强制清理 ==="
pkill -9 -f '__remote.sh' 2>/dev/null || true
sleep 2
pkill -9 -f '__remote.sh' 2>/dev/null || true
sleep 2

echo "=== 清理后进程数 ==="
ps -ax -o pid,command 2>/dev/null | grep -c '[_]remote.sh' || true

echo
echo "=== 系统负载 ==="
uptime
echo
echo "=== 磁盘 /tmp 占用 ==="
df -h /tmp | tail -1

echo
echo "=== 网络与关键服务是否正常 ==="
echo "--- 默认路由 ---"
netstat -rn -f inet | awk '$1=="default" {print}' | head -3
echo "--- 防火墙状态 ---"
pfctl -s info 2>/dev/null | head -3
echo "--- Unbound ---"
service unbound status 2>&1 | head -2
echo "--- 监听 53（DNS）---"
sockstat -4 -l 2>/dev/null | grep ':53 ' | head -3
echo
echo "=== mihomo/demo 进程 ==="
ps -ax -o pid,command 2>/dev/null | grep '[m]ihomo' || echo "(none)"
