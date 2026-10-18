#!/bin/sh
# 功能测试 · B：真实出网验证
#   · 环回出口（127.0.0.1 源）→ 按全局规则
#   · 绑定 LAN 源（192.168.1.1）→ 命中我们的策略规则 → 走美国组
#   · 国内目标 → 直连
#   · LanDirect（192.168.2.0/24）零规则、指纹不变
set -u
CFG=/usr/local/etc/mihomo/config.yaml
LOG=/var/log/mihomo.log
PROXY=socks5h://127.0.0.1:7890

SECRET=$(python3 -c "
import re,io
t=io.open('$CFG',encoding='utf-8').read()
m=re.search(r'^secret:\s*(.+)\$',t,re.M)
print(m.group(1).strip().strip(chr(34)).strip(chr(39)) if m else '')
")
echo "########## 0. 现状 ##########"
sockstat -4 -l 2>/dev/null | grep mihomo | sed 's/^/  /'
echo "  本机公网 IP（直连基线）: $(curl -s --max-time 10 https://api.ipify.org || echo FAIL)"
echo "  config.yaml 里 192.168.2.0/24 出现次数（必须 0）: $(grep -c '192\.168\.2\.0/24' "$CFG")"
echo "  受管块:"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /'

echo
echo "########## 1. 环回出口（源 127.0.0.1，走全局规则） ##########"
OUT1=$(curl -s --max-time 25 -x "$PROXY" https://api.ipify.org || echo FAIL)
echo "  exit IP: $OUT1"

echo
echo "########## 2. 绑定 LAN 源（源 192.168.1.1，应命中我们的 AND 规则 → 美国组） ##########"
OUT2=$(curl -s --max-time 25 --interface 192.168.1.1 -x "$PROXY" https://api.ipify.org || echo FAIL)
echo "  exit IP: $OUT2"
if [ "$OUT2" = "FAIL" ]; then
    echo "  (源绑定到回环目标失败，换用显式 --local-port / 二次确认)"
    curl -sv --max-time 15 --interface 192.168.1.1 -x "$PROXY" https://api.ipify.org 2>&1 | head -12 | sed 's/^/    /'
fi

echo
echo "########## 3. 国内目标（源 192.168.1.1，应直连、不走美国组） ##########"
echo -n "  baidu.com HTTP: "
curl -s --max-time 20 --interface 192.168.1.1 -x "$PROXY" -o /dev/null -w '%{http_code}\n' https://www.baidu.com || echo FAIL

echo
echo "########## 4. 美国组与全局组的当前选择 ##########"
for g in '🇺🇸 United States' 'Auto'; do
    echo -n "  $g -> "
    curl -s -H "Authorization: Bearer $SECRET" "http://127.0.0.1:9090/proxies/$(python3 -c "
import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$g")" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('now'), '| 可用节点', len(d.get('all',[])))" 2>/dev/null || echo "(读取失败)"
done

echo
echo "########## 5. 内核日志里的规则命中（证据） ##########"
tail -400 "$LOG" | grep -E 'match|using' | tail -12 | sed 's/^/  /'

echo
echo "########## 6. 安全复核（应与测试前完全一致） ##########"
echo "  pf     $(pfctl -sr 2>/dev/null | sha256 -q)   (基线 b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6)"
echo "  nat    $(pfctl -sn 2>/dev/null | sha256 -q)   (基线 3bc6b546843e7c1857ccfd12be7df053525e20e79a32e7e7454702cd05afd385)"
echo "  route  $(netstat -rn 2>/dev/null | sha256 -q)   (基线 46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619)"
echo "  unbound $(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)   (基线 1d1849c339e65579f132559b8d46e68ec35e12c056570107b97f2571955cf532)"
echo "  TUN 接口: $(ifconfig 2>/dev/null | grep -c tun_mihomo)"
echo "  LanDirect 侧是否有 mihomo 监听（应为 0）: $(sockstat -4 -l 2>/dev/null | grep mihomo | grep -c '192.168.2')"
echo -n "  本机（LanDirect）出网自检: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://www.freebsd.org/ || echo FAIL
