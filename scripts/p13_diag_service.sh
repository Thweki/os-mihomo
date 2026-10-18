#!/bin/sh
# 诊断：为何 restart 之后服务仍未运行
set -u
echo "########## 1. 进程与端口 ##########"
ps -ax -o pid,etime,command 2>/dev/null | grep '[m]ihomo' | sed 's/^/  /' || echo "  (无进程)"
sockstat -4 -l 2>/dev/null | egrep ':7890|:9090|:1053' | sed 's/^/  /' || echo "  (无监听)"
ls -la /var/run/mihomo.pid 2>/dev/null | sed 's/^/  /' || echo "  (无 pid 文件)"

echo
echo "########## 2. 日志尾部 ##########"
tail -20 /var/log/mihomo.log | sed 's/^/  /'

echo
echo "########## 3. 手工前台试跑（5 秒） ##########"
/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f /usr/local/etc/mihomo/config.yaml 2>&1 | tail -3 | sed 's/^/  /'
/usr/local/bin/mihomo -d /usr/local/etc/mihomo >/tmp/mihomo-fg.log 2>&1 &
FG=$!
sleep 4
if kill -0 "$FG" 2>/dev/null; then
    echo "  前台进程存活；输出："
    head -6 /tmp/mihomo-fg.log | sed 's/^/    /'
    kill "$FG" 2>/dev/null; sleep 1; echo "  已停止前台进程"
else
    echo "  前台进程退出；输出："
    head -12 /tmp/mihomo-fg.log | sed 's/^/    /'
fi

echo
echo "########## 4. 用 rc.d 启动（onestart） ##########"
sh /usr/local/etc/rc.d/mihomo onestart 2>&1 | head -5 | sed 's/^/  /'
sleep 3
service mihomo status 2>&1 | head -1 | sed 's/^/  /'

echo
echo "########## 5. 再确认 ##########"
echo "  TUN: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2" "$4}' || echo '(无)')"
echo -n "  控制器: "; curl -s --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9090/ || echo FAIL
tail -5 /var/log/mihomo.log | sed 's/^/  /'
