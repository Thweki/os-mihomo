#!/bin/sh
# os-mihomo —— 交付前状态复位（安全默认）
set -u

echo "=== 1. 模型 enabled 复位为 0 ==="
php -r '
require_once("/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.php");
$m = new \OPNsense\Mihomo\Mihomo();
$m->general->enabled = "0";
if ($m->serializeToConfig()) {
    OPNsense\Core\Config::getInstance()->save();
    echo "model saved\n";
} else {
    echo "no change needed\n";
}
' 2>&1

echo
echo "=== 2. rc.conf.d/mihomo 保持 NO ==="
printf 'mihomo_enable="NO"\n' > /etc/rc.conf.d/mihomo
chmod 0644 /etc/rc.conf.d/mihomo
cat /etc/rc.conf.d/mihomo

echo
echo "=== 3. 停止隔离 demo 实例 ==="
if [ -f /var/run/mihomo-demo.pid ]; then
    pid=$(cat /var/run/mihomo-demo.pid 2>/dev/null || echo '')
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    sleep 1
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
    rm -f /var/run/mihomo-demo.pid
fi
pkill -f 'mihomo-demo' 2>/dev/null || true
pkill -f 'speed.cloudflare.com' 2>/dev/null || true
sleep 1
ps aux | grep -v grep | grep mihomo || echo "(no mihomo process)"

echo
echo "=== 4. 清空演示日志 ==="
configctl mihomo log-clear mihomo 2>&1 || true
configctl mihomo log-clear subscription 2>&1 || true

echo
echo "=== 5. 清理临时目录 ==="
rm -rf /tmp/mihomo-demo /tmp/mihomo-test /tmp/mihomo-stage /tmp/menu_page.html /tmp/menu_test_jar.txt /tmp/x.sh 2>/dev/null || true
ls -d /tmp/mihomo* 2>/dev/null || echo "(no /tmp/mihomo* left)"

echo
echo "=== 6. 最终状态 ==="
echo "--- 服务 ---"
service mihomo status
echo "--- 控制器端口（应为空）---"
sockstat -4 -l 2>/dev/null | egrep ':9090|:17890|:17891' || echo "(nothing listening)"
echo "--- TUN 接口（应为空）---"
ifconfig -l | tr ' ' '\n' | grep -i tun || echo "(no tun interface)"
echo "--- 路由指纹 ---"
netstat -rn | sha256 -q
echo "--- pf 规则指纹 ---"
pfctl -sr 2>/dev/null | sha256 -q
echo "--- config.xml 指纹 ---"
sha256 -q /conf/config.xml
