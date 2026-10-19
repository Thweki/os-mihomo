#!/usr/bin/env python3
"""policy_net.php：支持三段式调用（verify 标志），让网关先于浮动规则存在"""
import io

p = 'src/usr/local/opnsense/scripts/mihomo/policy_net.php'
t = io.open(p, encoding='utf-8').read()

# ---------- 1. 文档头：说明三段式 ----------
old_doc = """ * 用法:
 *   policy_net.php check                          只读：现状（接口/网关/规则/TUN 地址）
 *   policy_net.php apply <staging-json>           写入 config.xml（接口 + 网关 + 策略路由规则）并重载过滤器
 *   policy_net.php rollback                       还原最近一次本插件做的 config.xml 备份并重载
 *
 * staging JSON:
 *   {"interfaces": ["lan", "opt2"], "gateway": "198.18.0.2", "device": "tun_mihomo"}
 *   gateway 留空时自动从 `ifconfig <device>` 推断（/30 时取对端地址）
"""
new_doc = """ * 用法:
 *   policy_net.php check                          只读：现状（接口/网关/规则/TUN 地址）
 *   policy_net.php apply <staging-json>           写入 config.xml（接口 + 网关）并（按需）重载过滤器
 *   policy_net.php rollback                       还原最近一次本插件做的 config.xml 备份并重载
 *
 * staging JSON:
 *   {"interfaces": ["lan", "opt2"], "gateway": "198.18.0.2", "device": "tun_mihomo",
 *    "verify": true, "verify_only": false}
 *   gateway 留空时自动从 `ifconfig <device>` 推断（/30 时取对端地址）
 *
 * 为什么分三段（WebGUI 的「应用」按这个顺序调用）:
 *   ① verify=false     先建接口与网关 —— 防火墙的浮动规则带 gateway 字段，
 *                      网关还不存在时模型校验会直接报「网关无效」（实测踩过）
 *   ② 浮动规则         由 WebGUI 侧写入核心防火墙模块（本脚本不碰）
 *   ③ verify_only=true 只做 filter reload + 自检（pf 里必须出现 route-to），
 *                      失败时报错，由 WebGUI 撤销刚写的规则
"""
if old_doc in t:
    t = t.replace(old_doc, new_doc, 1)
    print('文档头已更新')
else:
    print('!! 文档头未匹配（跳过）')

# ---------- 2. 解析 verify / verify_only，并提前处理 verify_only ----------
old_parse = """$before = (string)file_get_contents($CONFIG_FILE);
$after = $before;
$messages = [];
"""
new_parse = """$verify = !array_key_exists('verify', $payload) || (bool)$payload['verify'];
$verifyOnly = (bool)($payload['verify_only'] ?? false);

$before = (string)file_get_contents($CONFIG_FILE);
$after = $before;
$messages = [];

/* 第三段：只重载 + 自检（不再改 config.xml —— 规则已由核心防火墙模块写入） */
if ($verifyOnly) {
    [$rc, $filterOut] = run_command('configctl filter reload');
    $messages[] = $rc === 0 ? 'filter reload: OK' : 'filter reload failed: ' . $filterOut;
    [$rc2, $routeOut] = run_command("pfctl -sr | grep 'route-to' | grep -c 'tun_mihomo'");
    $routeCount = (int)trim($routeOut);
    if ($interfaces !== [] && $routeCount < 1) {
        fail(
            'safety check failed: firewall rules are written but no pf route-to rule points at '
            . $DEFAULT_DEVICE . '. Check that the gateway interface is the TUN interface.',
            1
        );
    }
    $messages[] = $interfaces === []
        ? 'pf route-to rules into tun_mihomo after unbind: ' . $routeCount
        : 'pf route-to rules into tun_mihomo: ' . $routeCount;
    @unlink($staging);
    out(['status' => 'ok', 'messages' => $messages, 'state' => current_state()]);
    exit(0);
}
"""
if old_parse in t:
    t = t.replace(old_parse, new_parse, 1)
    print('verify_only 分支已插入')
else:
    raise SystemExit('!! 解析段落未匹配')

# ---------- 3. 结尾的重载 + 自检：第一段时跳过 ----------
old_tail = """/* ---------------- 6. 重载过滤器 + 安全自检（不通过就自动回滚） ----------------"""
new_tail = """/* ---------------- 6. 重载过滤器 + 安全自检（不通过就自动回滚） ----------------
 * 第一段（verify=false）时跳过：此时浮动规则还没写，pf 里当然没有 route-to，
 * 那一步由第三段（verify_only=true）负责。 */
if (!$verify) {
    @unlink($staging);
    $messages[] = 'filter reload skipped (first stage: firewall rules are written next)';
    out([
        'status' => 'ok',
        'messages' => $messages,
        'diff' => diff_text($before, $after, 'config.xml'),
        'state' => current_state(),
    ]);
    exit(0);
}
"""
if old_tail in t:
    t = t.replace(old_tail, new_tail, 1)
    print('第一段跳过重载已插入')
else:
    raise SystemExit('!! 结尾段落未匹配')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('policy_net.php 改造完成')
