#!/usr/bin/env python3
"""把 policy_net.php 的第 4 步替换成「含内网直达规则」的双向对账版本"""
import io

p = 'src/usr/local/opnsense/scripts/mihomo/policy_net.php'
t = io.open(p, encoding='utf-8').read()

start = t.find('/* ---------------- 4. ')
end = t.find('/* ---------------- 4b.')
if start == -1 or end == -1 or end <= start:
    raise SystemExit('定位失败')

new_block = '''/* ---------------- 4. 规则对账：内网直达（bypass）+ 策略路由（policy） ----------------
 * 期望顺序：对每个绑定接口，先放「目标＝其它内网网段」的直达规则，再放策略路由规则。
 * 只要现有规则与期望不一致（缺、多、顺序不对），就整体重建本插件的规则 —— 保证幂等。 */
$localNets = local_networks($after);
$desired = [];
foreach ($interfaces as $iface) {
    foreach ($localNets as $destName => $destCidr) {
        if ($destName === $iface) {
            continue;
        }
        $desired[] = ['kind' => 'bypass', 'iface' => $iface, 'dest' => $destName];
    }
    $desired[] = ['kind' => 'policy', 'iface' => $iface, 'dest' => ''];
}

$existingRules = our_rules($after, $RULE_MARKER, $RULE_MARKER_LOCAL, $GATEWAY_NAME);
$key = fn (array $r): string => $r['kind'] . ':' . $r['iface'] . ':' . $r['dest'];
$wantKeys = array_map($key, $desired);
$haveKeys = array_map($key, array_map(fn ($r) => ['kind' => $r['kind'], 'iface' => $r['iface'], 'dest' => $r['dest']], $existingRules));

$missing = array_diff($wantKeys, $haveKeys);
$extra = array_diff($haveKeys, $wantKeys);

/* 顺序检查：同一接口的 bypass 必须在 policy 之前（pf 的 quick 语义下顺序即优先级） */
$misordered = false;
foreach ($interfaces as $iface) {
    $policyOffset = null;
    foreach ($existingRules as $rule) {
        if ($rule['iface'] !== $iface || $rule['kind'] !== 'policy') {
            continue;
        }
        $policyOffset = $rule['offset'];
    }
    if ($policyOffset === null) {
        continue;
    }
    foreach ($existingRules as $rule) {
        if ($rule['iface'] === $iface && $rule['kind'] === 'bypass' && $rule['offset'] > $policyOffset) {
            $misordered = true;
        }
    }
}

if ($missing !== [] || $extra !== [] || $misordered) {
    $dropped = [];
    $after = remove_all_our_rules($after, $RULE_MARKER, $RULE_MARKER_LOCAL, $GATEWAY_NAME, $dropped);
    if ($dropped !== []) {
        $messages[] = 'existing rules rebuilt: ' . implode(', ', array_unique($dropped));
    }

    $block = '';
    foreach ($desired as $rule) {
        $block .= $rule['kind'] === 'bypass'
            ? bypass_rule_xml($rule['iface'], $rule['dest'], $RULE_MARKER_LOCAL)
            : policy_rule_xml($rule['iface'], $GATEWAY_NAME, $RULE_MARKER);
    }
    if (preg_match('@^(\\s*)<filter\\s*/>@m', $after)) {
        $after = preg_replace('@^(\\s*)<filter\\s*/>@m', '$1<filter>' . "\\n" . $block . '$1</filter>', $after, 1);
    } elseif (preg_match('@^(\\s*)<filter>@m', $after, $mm)) {
        $after = preg_replace('@^(\\s*)<filter>@m', '$0' . "\\n" . $block, $after, 1);
    } else {
        fail('config.xml has no <filter> section', 3);
    }

    $bypassCount = count(array_filter($desired, fn ($r) => $r['kind'] === 'bypass'));
    $messages[] = sprintf(
        'rules written: %d policy + %d local bypass (%s)',
        count($interfaces),
        $bypassCount,
        implode(', ', $interfaces)
    );
} else {
    $messages[] = 'rules already in place (' . count($interfaces) . ' policy + '
        . count(array_filter($desired, fn ($r) => $r['kind'] === 'bypass')) . ' bypass)';
}

'''

t = t[:start] + new_block + t[end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('第 4 步已替换')
