#!/bin/sh
# 诊断（精简）：为什么 start 没起进程
set -u

echo "########## 1. 配置校验（rc.d 的 prestart 会先跑这个） ##########"
/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f /usr/local/etc/mihomo/config.yaml 2>&1 | tail -12
echo "退出码: $?"

echo
echo "########## 2. 直接 start（configd 的方式） ##########"
sh /usr/local/etc/rc.d/mihomo start 2>&1 | tail -12
echo "退出码: $?"
sleep 2
sh /usr/local/etc/rc.d/mihomo status 2>&1 | tail -2

echo
echo "########## 3. 日志末尾 ##########"
tail -20 /var/log/mihomo.log 2>/dev/null || echo "(无日志)"

echo
echo "########## 4. 前台启动 3 秒看真实输出 ##########"
/usr/local/bin/mihomo -d /usr/local/etc/mihomo >/tmp/mihomo-fg.log 2>&1 &
FG=$!
sleep 3
if kill -0 "$FG" 2>/dev/null; then
    echo "  进程存活 (pid $FG)，输出："
    head -15 /tmp/mihomo-fg.log
    kill "$FG" 2>/dev/null
    sleep 1
    echo "  已停止"
else
    echo "  进程已退出，输出："
    head -25 /tmp/mihomo-fg.log
fi

echo
echo "########## 5. 残留检查 ##########"
ps -ax -o pid,command 2>/dev/null | grep '[m]ihomo' | head -5 || echo "  (无残留进程)"
