#!/bin/sh
# 最终状态确认
set -u

echo "=== 1. 模型中的 enabled ==="
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
for path in ('OPNsense/mihomo/general/enabled', 'OPNsense/mihomo/tun/enabled', 'OPNsense/mihomo/general/controllerBind'):
    n = r.find(path)
    print('%-45s = %s' % (path, n.text if n is not None else 'missing'))
PY

echo
echo "=== 2. 自启开关（必须是 NO）==="
cat /etc/rc.conf.d/mihomo

echo
echo "=== 3. 服务与进程 ==="
service mihomo status
ps -ax -o pid,command 2>/dev/null | grep '[m]ihomo' || echo "(no mihomo process)"

echo
echo "=== 4. 端口（9090/17890/17891 应为空）==="
sockstat -4 -l 2>/dev/null | egrep ':9090|:17890|:17891' || echo "(nothing listening)"

echo
echo "=== 5. TUN 接口 ==="
ifconfig -l | tr ' ' '\n' | grep -i tun || echo "(no tun interface)"

echo
echo "=== 6. 接口配置指纹（排除计数器）==="
ifconfig -a 2>/dev/null | grep -E '^[a-z0-9_.]+:|inet |inet6 |ether |mtu |flags|status:' | sha256 -q

echo
echo "=== 7. 网络配置指纹（必须与基线一致）==="
printf 'pf rules   %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'pf nat     %s\n' "$(pfctl -sn 2>/dev/null | sha256 -q)"
printf 'routes     %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'unbound    %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
echo "baselines:"
echo "  pf rules b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6"
echo "  pf nat   3bc6b546843e7c1857ccfd12be7df053525e20e79a32e7e7454702cd05afd385"
echo "  routes   46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619"
echo "  unbound  1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532"

echo
echo "=== 8. 日志（已清空）==="
ls -la /var/log/mihomo*.log 2>/dev/null
echo "--- 内容行数 ---"
wc -l /var/log/mihomo.log /var/log/mihomo_sub.log 2>/dev/null

echo
echo "=== 9. /tmp 残留 ==="
ls -d /tmp/mihomo* 2>/dev/null || echo "(clean)"

echo
echo "=== 10. 负载 ==="
uptime
