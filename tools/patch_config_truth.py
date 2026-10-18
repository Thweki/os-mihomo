#!/usr/bin/env python3
"""修补 scripts/config_truth.sh 的三个小问题"""
import io

p = 'scripts/config_truth.sh'
t = io.open(p, encoding='utf-8').read()
before = t

# 1) 文件里没有该键 -> 标为「未写」，不参与一致性判定
t = t.replace(
    """    ok = '✅' if norm(a) == norm(b) else '❌'
    if ok == '❌':
        diff += 1""",
    """    if isinstance(b, str) and b.startswith('(文件里没有'):
        ok = '—（用内核默认值）'
    else:
        ok = '✅' if norm(a) == norm(b) else '❌'
        if ok == '❌':
            diff += 1""")

# 2) 运行值对比：文件里没写该键时不算不一致
t = t.replace(
    """    f=fv(key) if not key.startswith('(') else '-'
    ok='✅' if (f=='-' or str(f).lower()==str(runv).lower()) else '❌'""",
    """    f=fv(key, '(未写)') if not key.startswith('(') else '-'
    ok='✅' if (f in ('-', '(未写)') or str(f).lower()==str(runv).lower()) else '❌'""")

# 3) 去掉重复输出的 0
t = t.replace(
    """$(grep -c 'os-mihomo:policy-routing' "$TEMPLATE" 2>/dev/null || echo 0) 处""",
    """$(grep -c 'os-mihomo:policy-routing' "$TEMPLATE" 2>/dev/null | head -1) 处""")
t = t.replace(
    """echo "  订阅模板里是否已有同一份区块：$(grep -c 'os-mihomo:policy-routing' "$TEMPLATE" 2>/dev/null || echo 0) 处\"""",
    """echo "  订阅模板里是否已有同一份区块：$(grep -c 'os-mihomo:policy-routing' "$TEMPLATE" 2>/dev/null | head -1) 处\"""")
t = t.replace(
    """echo "  MIHOMO_TUN 网关： $(grep -c 'MIHOMO_TUN' /conf/config.xml)\"""",
    """echo "  OPNsense 侧网关 MIHOMO_TUN： $(grep -c 'MIHOMO_TUN' /conf/config.xml | head -1) 处\"""")
t = t.replace(
    """echo "  pf 里送进 TUN 的规则： $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' || echo 0) 条\"""",
    """echo "  pf 里送进 TUN 的规则： $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' | head -1) 条\"""")

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('config_truth.sh 已修:', 'OK' if t != before else '未变化')
for kw in ['(文件里没有', '(未写)', 'head -1) 处']:
    print('  ', kw, '->', t.count(kw), '处')
