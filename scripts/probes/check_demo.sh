#!/bin/sh
set -u
echo "=== mihomo 进程 ==="
ps -ax -o pid,command 2>/dev/null | grep -v grep | grep mihomo | head -5 || echo "(none)"
echo
echo "=== pidfile / demo 目录 ==="
ls -la /var/run/mihomo-demo.pid 2>/dev/null || echo "(no pidfile)"
ls -la /tmp/mihomo-demo/ 2>/dev/null | head -5 || echo "(no demo dir)"
echo
echo "=== 9090 / 17890 ==="
sockstat -4 -l 2>/dev/null | grep -E '9090|17890' || echo "(nothing listening)"
echo
echo "=== 负载 ==="
uptime
echo
echo "=== 日志尾部 ==="
tail -5 /var/log/mihomo.log 2>/dev/null || echo "(empty)"
