#!/usr/bin/env python3
"""policy_net.php：不再写规则（改由新防火墙模块的浮动规则负责），但保留清理旧版遗留规则的能力"""
import io

p = 'src/usr/local/opnsense/scripts/mihomo/policy_net.php'
t = io.open(p, encoding='utf-8').read()

start = t.find('/* ---------------- 4. ')
end = t.find('/* ---------------- 4b.')
if start == -1 or end == -1:
    raise SystemExit('定位失败')

new_block = '''/* ---------------- 4. 旧版遗留规则的清理（规则本体改由核心防火墙模块的浮动规则负责） ----------------
 * 说明：本脚本早先版本把规则写进旧版根 <filter>，实测会被接口的默认放行规则抢先
 * （pf 里顺序在后、Evaluations=0），因此规则改由 Api\\RoutingController::syncFloatingRules()
 * 以「浮动规则」形式写入核心防火墙模块。这里只负责把旧版遗留清掉。 */
$dropped = [];
$after = remove_all_our_rules($after, $RULE_MARKER, $RULE_MARKER_LOCAL, $GATEWAY_NAME, $dropped);
if ($dropped !== []) {
    $messages[] = 'legacy inline rules removed: ' . implode(', ', array_unique($dropped));
}

'''

t = t[:start] + new_block + t[end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('policy_net.php 第 4 步已改为「仅清理旧版规则」')
