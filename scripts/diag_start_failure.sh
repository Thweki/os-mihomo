#!/bin/sh
# 诊断：为什么服务没起来
set -u

echo "########## 1. rc.d 脚本全文 ##########"
cat -n /usr/local/etc/rc.d/mihomo

echo
echo "########## 2. 直接调用 rc.d（configd 用的方式） ##########"
sh /usr/local/etc/rc.d/mihomo start 2>&1 | head -20
echo "退出码: $?"
sleep 2
sh /usr/local/etc/rc.d/mihomo status 2>&1 | head -3

echo
echo "########## 3. 内核日志（/var/log/mihomo.log 末尾） ##########"
tail -30 /var/log/mihomo.log 2>/dev/null || echo "(无日志)"

echo
echo "########## 4. 手工前台试跑（3 秒，看真实报错） ##########"
timeout 5 /usr/local/bin/mihomo -d /usr/local/etc/mihomo -t 2>&1 | tail -15
echo "--- 前台启动 3 秒 ---"
( /usr/local/bin/mihomo -d /usr/local/etc/mihomo >/tmp/mihomo-fg.log 2>&1 & echo $! > /tmp/mihomo-fg.pid )
sleep 3
if kill -0 "$(cat /tmp/mihomo-fg.pid)" 2>/dev/null; then
    echo "  进程存活，输出如下："
    head -20 /tmp/mihomo-fg.log
    kill "$(cat /tmp/mihomo-fg.pid)" 2>/dev/null
    sleep 1
    echo "  已停止"
else
    echo "  进程已退出，输出："
    cat /tmp/mihomo-fg.log | head -20
fi
rm -f /tmp/mihomo-fg.pid

echo
echo "########## 5. 进程与端口 ##########"
ps -ax -o pid,etime,command 2>/dev/null | grep '[m]ihomo' | head -5 || echo "  (无进程)"
sockstat -4 -l 2>/dev/null | egrep ':9090|:7891|:1053' || echo "  (无监听)"
