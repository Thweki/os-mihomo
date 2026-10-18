#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 路由策略「网络侧」同步器（由 configd 以 root 身份调用）
 *
 * 用法:
 *   policy_net.php check                          只读：现状（接口/网关/规则/TUN 地址）
 *   policy_net.php apply <staging-json>           写入 config.xml（接口 + 网关 + 策略路由规则）并重载过滤器
 *   policy_net.php rollback                       还原最近一次本插件做的 config.xml 备份并重载
 *
 * staging JSON:
 *   {"interfaces": ["lan", "opt2"], "gateway": "198.18.0.2", "device": "tun_mihomo"}
 *   gateway 留空时自动从 `ifconfig <device>` 推断（/30 时取对端地址）
 *
 * 设计要点（安全第一）:
 *   · 全程**只增不改**：已存在的接口块/网关/规则不重复添加，不删除任何既有配置；
 *   · 改动前把 /conf/config.xml 备份到 /conf/config.xml.mihomo-bak.<ts>（可一键还原）；
 *   · 文本级插入（不做 DOM 重新序列化），其余内容逐字节保留 —— 与本项目「最小 diff」原则一致；
 *   · 只处理 <policy>路由规则</policy>：仅为请求里列出的接口创建规则；其他接口（例如 LanDirect）一条都不加；
 *   · 结束后执行 `configctl filter reload`，并回报生成的 pf 规则里是否出现 route-to。
 *
 * 退出码: 0 成功 / 1 校验失败 / 2 参数或环境错误 / 3 写入失败
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部 BSD 许可条款。
 */

$CONFIG_FILE = '/conf/config.xml';
$BACKUP_GLOB = '/conf/config.xml.mihomo-bak.*';
$GATEWAY_NAME = 'MIHOMO_TUN';
$RULE_MARKER = 'Mihomo policy routing';
$DEFAULT_DEVICE = 'tun_mihomo';

function out(array $data): void
{
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
}

function fail(string $message, int $code): void
{
    out(['status' => 'failed', 'message' => $message]);
    fwrite(STDERR, $message . "\n");
    exit($code);
}

function run_command(string $command): array
{
    $output = [];
    $rc = 0;
    exec($command . ' 2>&1', $output, $rc);
    return [$rc, implode("\n", $output)];
}

function diff_text(string $before, string $after, string $label): string
{
    $a = preg_split("/\r\n|\n|\r/", $before) ?: [];
    $b = preg_split("/\r\n|\n|\r/", $after) ?: [];
    $lines = [];
    $shown = 0;
    $max = max(count($a), count($b));
    for ($i = 0; $i < $max; $i++) {
        $left = $a[$i] ?? null;
        $right = $b[$i] ?? null;
        if ($left === $right) {
            continue;
        }
        if ($shown >= 60) {
            $lines[] = '...';
            break;
        }
        $no = $i + 1;
        if ($left !== null && !in_array($left, $b, true)) {
            $lines[] = sprintf('%-5d - %s', $no, $left);
        }
        if ($right !== null && !in_array($right, $a, true)) {
            $lines[] = sprintf('%-5d + %s', $no, $right);
        }
        $shown++;
    }
    return $lines === [] ? '' : $label . ":\n" . implode("\n", $lines);
}

/** 从 ifconfig 推断 TUN 的对端地址（网关） */
function detect_gateway(string $device): string
{
    [$rc, $output] = run_command('ifconfig ' . escapeshellarg($device));
    if ($rc !== 0) {
        return '';
    }
    if (!preg_match('/inet (\d+\.\d+\.\d+\.\d+) netmask (0x[0-9a-f]+)/i', $output, $m)) {
        return '';
    }
    $addr = ip2long($m[1]);
    $mask = hexdec($m[2]);
    if ($addr === false || $mask === 0 || ((~$mask) & 0x3) !== 0x3) {
        return '';
    }
    /* /30：本地 .1、对端 .2 */
    return long2ip($addr + 1);
}

/**
 * 找到**根** <interfaces> 段的范围（config.xml 里 webgui 也有个同名的 <interfaces> 列表，
 * 必须靠"内部含有 <if> 设备赋值"来区分，否则会写错地方 —— 这是实测踩过的坑）。
 * @return array{0:int,1:int,2:string} [start, end, inner]
 */
function root_interfaces_range(string $xml): array
{
    $best = [0, 0, ''];
    $bestCount = -1;
    $offset = 0;
    while (($start = strpos($xml, '<interfaces>', $offset)) !== false) {
        $end = strpos($xml, '</interfaces>', $start);
        if ($end === false) {
            break;
        }
        $inner = substr($xml, $start, $end - $start);
        $count = substr_count($inner, '<if>');
        if ($count > $bestCount) {
            $bestCount = $count;
            $best = [$start, $end, $inner];
        }
        $offset = $end + 1;
    }
    if ($bestCount <= 0) {
        fail('config.xml has no root <interfaces> section with device assignments', 3);
    }
    return $best;
}

/** 在根 interfaces 段里，取设备名对应的接口名（如 tun_mihomo -> opt3） */
function interface_name_for_device(string $xml, string $device): string
{
    [$start, $end] = root_interfaces_range($xml);
    $inner = substr($xml, $start, $end - $start);
    if (preg_match('@<(\w+)>\s*<if>' . preg_quote($device, '@') . '</if>@s', $inner, $m)) {
        return $m[1];
    }
    return '';
}

function current_state(): array
{
    global $CONFIG_FILE, $GATEWAY_NAME, $RULE_MARKER, $DEFAULT_DEVICE;

    $raw = (string)@file_get_contents($CONFIG_FILE);
    $device = $DEFAULT_DEVICE;
    $interfaceName = interface_name_for_device($raw, $device);
    $gateway = detect_gateway($device);

    /* 已有哪些接口有我们的策略路由规则 */
    $rules = [];
    if (preg_match_all('@<rule\b[^>]*>.*?</rule>@s', $raw, $m)) {
        foreach ($m[0] as $block) {
            if (!str_contains($block, $RULE_MARKER)) {
                continue;
            }
            preg_match('@<interface>([^<]+)</interface>@', $block, $mm);
            preg_match('@<gateway>([^<]+)</gateway>@', $block, $gg);
            $rules[] = [
                'interface' => $mm[1] ?? '?',
                'gateway' => $gg[1] ?? '?',
            ];
        }
    }

    $backups = glob($GLOBALS['BACKUP_GLOB']) ?: [];
    sort($backups);

    $deviceUp = false;
    [$rc, $out] = run_command('ifconfig ' . escapeshellarg($device));
    $deviceUp = ($rc === 0);

    $gwConfigured = '';
    if (preg_match(
        '@<gateway_item>(?:(?!</gateway_item>).)*?<name>' . $GATEWAY_NAME
        . '</name>(?:(?!</gateway_item>).)*?</gateway_item>@s',
        $raw,
        $gwBlock
    ) && preg_match('@<gateway>([^<]+)</gateway>@', $gwBlock[0], $gm)) {
        $gwConfigured = $gm[1];
    }

    return [
        'device' => $device,
        'device_up' => $deviceUp,
        'interface' => $interfaceName,
        'gateway_name' => $GATEWAY_NAME,
        'gateway_present' => str_contains($raw, '<name>' . $GATEWAY_NAME . '</name>'),
        'gateway_ip' => $gateway,
        'gateway_ip_configured' => $gwConfigured,
        'rules' => $rules,
        'backups' => array_slice($backups, -5),
    ];
}

/**
 * 从 config.xml 中移除本插件为指定接口生成的策略路由规则
 * @param string[] $ifaces 要移除的接口
 * @param string[] $removed 输出：实际移除的接口
 */
function remove_our_rules(string $xml, array $ifaces, string $marker, string $gwName, array &$removed): string
{
    if (!preg_match_all('@[ \t]*<rule\b[^>]*>.*?</rule>\r?\n?@s', $xml, $m, PREG_OFFSET_CAPTURE)) {
        return $xml;
    }
    $out = '';
    $last = 0;
    foreach ($m[0] as $entry) {
        [$block, $offset] = $entry;
        if (!str_contains($block, $marker) || !str_contains($block, '<gateway>' . $gwName . '</gateway>')) {
            continue;
        }
        if (!preg_match('@<interface>([^<]+)</interface>@', $block, $im) || !in_array($im[1], $ifaces, true)) {
            continue;
        }
        $out .= substr($xml, $last, $offset - $last);
        $last = $offset + strlen($block);
        $removed[] = $im[1];
    }
    return $out . substr($xml, $last);
}

function build_plan(array $plan): array
{
    global $GATEWAY_NAME;

    $state = current_state();
    $existing = array_column($state['rules'], 'interface');
    $desired = array_values(array_unique($plan['interfaces']));
    $add = array_values(array_diff($desired, $existing));
    $remove = array_values(array_diff($existing, $desired));
    $changes = [];

    if ($add !== []) {
        if (empty($state['interface'])) {
            $changes[] = 'config.xml: add interface block for ' . $state['device'];
        }
        if (!$state['gateway_present']) {
            $changes[] = sprintf(
                'config.xml: add gateway %s (%s%s)',
                $GATEWAY_NAME,
                $state['device'],
                $plan['gateway'] !== '' ? ' -> ' . $plan['gateway'] : ' -> (auto)'
            );
        }
        foreach ($add as $iface) {
            $changes[] = sprintf('config.xml: bind interface %s to mihomo (policy routing rule via %s)', $iface, $GATEWAY_NAME);
        }
    }

    foreach ($remove as $iface) {
        $changes[] = sprintf('config.xml: unbind interface %s (remove its policy routing rule)', $iface);
    }

    if ($desired === [] && ($existing !== [] || $state['gateway_present'] || !empty($state['interface']))) {
        $changes[] = sprintf('config.xml: remove gateway %s and the %s interface (nothing is bound anymore)', $GATEWAY_NAME, $state['device']);
    }

    if ($changes !== []) {
        $changes[] = 'run: configctl filter reload';
    }

    return [
        'status' => 'ok',
        'changes' => $changes,
        'state' => $state,
        'add' => $add,
        'remove' => $remove,
        'note' => empty($changes) ? 'nothing to do' : '',
    ];
}

/* ---------------------------------------------------------------------- */

$action = $argv[1] ?? '';

if (!is_file($CONFIG_FILE)) {
    fail('missing ' . $CONFIG_FILE, 2);
}

if ($action === 'check' || $action === 'plan') {
    if ($action === 'check') {
        out(array_merge(['status' => 'ok'], current_state()));
        exit(0);
    }
    $plan = ['interfaces' => [], 'gateway' => ''];
    $staging = $argv[2] ?? '';
    if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $staging) || !is_file($staging)) {
        fail('invalid staging file: ' . $staging, 2);
    }
    $payload = json_decode((string)file_get_contents($staging), true);
    if (!is_array($payload)) {
        fail('invalid staging payload', 2);
    }
    $plan['interfaces'] = array_values(array_filter(array_map('strval', $payload['interfaces'] ?? [])));
    $plan['gateway'] = trim((string)($payload['gateway'] ?? ''));
    out(build_plan($plan));
    exit(0);
}

if ($action === 'rollback') {
    $backups = glob($BACKUP_GLOB) ?: [];
    sort($backups);
    /* 允许指定要还原的备份（绝对路径且必须在备份目录内），否则用最近的 */
    $requested = trim((string)($argv[2] ?? ''));
    $last = '';
    if ($requested !== '') {
        if (!preg_match('@^/conf/config\.xml\.mihomo-bak\.[0-9_]+$@', $requested) || !is_file($requested)) {
            fail('invalid backup file: ' . $requested, 2);
        }
        $last = $requested;
    } else {
        $last = end($backups) ?: '';
    }
    if ($last === '' || !is_file($last)) {
        fail('no backup found (' . $BACKUP_GLOB . ')', 2);
    }
    if (!copy($last, $CONFIG_FILE)) {
        fail('unable to restore ' . $last, 3);
    }
    chmod($CONFIG_FILE, 0644);
    [$rc, $filterOut] = run_command('configctl filter reload');
    out([
        'status' => 'ok',
        'messages' => [
            sprintf('config.xml restored from %s', basename($last)),
            $rc === 0 ? 'filter reload: OK' : 'filter reload failed: ' . $filterOut,
        ],
        'state' => current_state(),
    ]);
    exit(0);
}

if ($action !== 'apply') {
    fail('usage: policy_net.php check|plan|apply|rollback [staging]', 2);
}

$staging = $argv[2] ?? '';
if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $staging) || !is_file($staging)) {
    fail('invalid staging file: ' . $staging, 2);
}
$payload = json_decode((string)file_get_contents($staging), true);
if (!is_array($payload)) {
    fail('invalid staging payload', 2);
}

$interfaces = [];
foreach ($payload['interfaces'] ?? [] as $iface) {
    $iface = trim((string)$iface);
    if ($iface === '') {
        continue;
    }
    if (!preg_match('/^[a-z0-9_]{2,16}$/', $iface)) {
        fail('invalid interface name: ' . $iface, 2);
    }
    $interfaces[] = $iface;
}
if (!array_key_exists('interfaces', $payload)) {
    fail('staging payload must contain an "interfaces" list (may be empty to unbind everything)', 2);
}
$interfaces = array_values(array_unique($interfaces));

$before = (string)file_get_contents($CONFIG_FILE);
$after = $before;
$messages = [];

/* ---------------- 1. 网关地址 ---------------- */
$gwIp = trim((string)($payload['gateway'] ?? ''));
if ($gwIp === '') {
    $gwIp = detect_gateway($DEFAULT_DEVICE);
}
if ($gwIp !== '' && !filter_var($gwIp, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
    fail('invalid gateway address: ' . $gwIp, 2);
}

/* ---------------- 2. 接口块（仅在有接口需要绑定时） ---------------- */
$existingInterface = interface_name_for_device($after, $DEFAULT_DEVICE);
$existingRuleIfaces = [];
if (preg_match_all('@<rule\b[^>]*>.*?</rule>@s', $after, $rm)) {
    foreach ($rm[0] as $block) {
        if (!str_contains($block, $RULE_MARKER) || !str_contains($block, '<gateway>' . $GATEWAY_NAME . '</gateway>')) {
            continue;
        }
        if (preg_match('@<interface>([^<]+)</interface>@', $block, $im)) {
            $existingRuleIfaces[$im[1]] = true;
        }
    }
}
$addIfaces = array_values(array_diff($interfaces, array_keys($existingRuleIfaces)));
$removeIfaces = array_values(array_diff(array_keys($existingRuleIfaces), $interfaces));

if ($addIfaces !== [] && $existingInterface === '') {
    /* 仿上游 +POST_INSTALL：取下一个空闲 optN，插在根接口段的 </lo0> 之后 */
    [$rootStart, $rootEnd, $rootInner] = root_interfaces_range($after);
    $maxOpt = 0;
    if (preg_match_all('@<opt(\d+)>@', $rootInner, $mm)) {
        $maxOpt = max(array_map('intval', $mm[1]));
    }
    $newName = 'opt' . ($maxOpt + 1);

    /* 只在根接口段内找 </lo0>，避免误插到别的同名段落 */
    $lo0End = strpos($after, '</lo0>', $rootStart);
    if ($lo0End === false || $lo0End > $rootEnd) {
        fail('unable to locate </lo0> inside the root interfaces section', 3);
    }
    $insertAt = $lo0End + strlen('</lo0>');
    $insertion = sprintf(
        "\n    <%s>\n      <if>%s</if>\n      <descr>TUN</descr>\n      <enable>1</enable>\n    </%s>",
        $newName,
        $DEFAULT_DEVICE,
        $newName
    );
    $after = substr($after, 0, $insertAt) . $insertion . substr($after, $insertAt);

    /* 自检：新接口确实落在根接口段里 */
    if (interface_name_for_device($after, $DEFAULT_DEVICE) !== $newName) {
        fail('interface block was not written into the root interfaces section, aborting', 3);
    }
    $existingInterface = $newName;
    $messages[] = 'interface block added: ' . $newName . ' -> ' . $DEFAULT_DEVICE;
} elseif ($existingInterface !== '') {
    $messages[] = 'interface block present: ' . $existingInterface . ' -> ' . $DEFAULT_DEVICE;
}

/* ---------------- 3. 网关（有绑定时确保存在；全部解绑时移除） ---------------- */
if ($addIfaces !== []) {
    if (str_contains($after, '<name>' . $GATEWAY_NAME . '</name>')) {
        $messages[] = 'gateway already present: ' . $GATEWAY_NAME;
    } else {
        if ($gwIp === '') {
            fail('unable to determine TUN peer address; start the service with TUN enabled first', 1);
        }
        $gwBlock = sprintf(
            "            <gateway_item>\n"
            . "                <interface>%s</interface>\n"
            . "                <gateway>%s</gateway>\n"
            . "                <name>%s</name>\n"
            . "                <weight>1</weight>\n"
            . "                <ipprotocol>inet</ipprotocol>\n"
            . "                <monitor_disable>1</monitor_disable>\n"
            . "                <descr>Mihomo TUN gateway</descr>\n"
            . "            </gateway_item>\n",
            $existingInterface,
            $gwIp,
            $GATEWAY_NAME
        );
        if (str_contains($after, '<Gateways>')) {
            $after = preg_replace('@(<Gateways>\s*)@', '$1' . "\n" . $gwBlock, $after, 1);
        } elseif (preg_match('@<OPNsense>\s*@', $after, $mm)) {
            $after = preg_replace(
                '@(<OPNsense>\s*)@',
                '$1<Gateways>' . "\n" . $gwBlock . "        </Gateways>\n",
                $after,
                1
            );
        } else {
            fail('config.xml has neither <Gateways> nor <OPNsense>', 3);
        }
        $messages[] = sprintf('gateway added: %s -> %s via %s', $GATEWAY_NAME, $gwIp, $existingInterface);
    }
}

/* ---------------- 4. 策略路由规则：先移除不再需要的，再添加新的 ---------------- */
$removed = [];
if ($removeIfaces !== []) {
    $after = remove_our_rules($after, $removeIfaces, $RULE_MARKER, $GATEWAY_NAME, $removed);
    foreach ($removed as $iface) {
        $messages[] = 'unbound interface ' . $iface . ' (policy routing rule removed)';
    }
}

foreach ($addIfaces as $iface) {
    $uuid = sprintf(
        '%s-%s-%s-%s-%s',
        bin2hex(random_bytes(4)),
        bin2hex(random_bytes(2)),
        bin2hex(random_bytes(2)),
        bin2hex(random_bytes(2)),
        bin2hex(random_bytes(6))
    );
    $rule = sprintf(
        "          <rule uuid=\"%s\">\n"
        . "            <type>pass</type>\n"
        . "            <interface>%s</interface>\n"
        . "            <ipprotocol>inet</ipprotocol>\n"
        . "            <source><network>%s</network></source>\n"
        . "            <destination><any/></destination>\n"
        . "            <gateway>%s</gateway>\n"
        . "            <descr>%s (%s)</descr>\n"
        . "          </rule>\n",
        $uuid,
        $iface,
        $iface,
        $GATEWAY_NAME,
        $RULE_MARKER,
        $iface
    );
    if (preg_match('@^(\s*)<filter\s*/>@m', $after)) {
        $after = preg_replace('@^(\s*)<filter\s*/>@m', '$1<filter>' . "\n" . $rule . '$1</filter>', $after, 1);
    } elseif (preg_match('@^(\s*)<filter>@m', $after, $mm)) {
        $after = preg_replace('@^(\s*)<filter>@m', '$0' . "\n" . $rule, $after, 1);
    } else {
        fail('config.xml has no <filter> section', 3);
    }
    $messages[] = 'bound interface ' . $iface . ' to mihomo (gateway ' . $GATEWAY_NAME . ')';
}

/* ---------------- 4b. 全部解绑时清理网关与接口块 ---------------- */
if ($interfaces === []) {
    if (str_contains($after, '<name>' . $GATEWAY_NAME . '</name>')) {
        $after = preg_replace(
            '@[ \t]*<gateway_item>(?:(?!</gateway_item>).)*?<name>' . preg_quote($GATEWAY_NAME, '@')
            . '</name>(?:(?!</gateway_item>).)*?</gateway_item>\r?\n?@s',
            '',
            $after,
            1
        );
        $messages[] = 'gateway removed: ' . $GATEWAY_NAME . ' (nothing is bound anymore)';
    }
    $ifaceName = interface_name_for_device($after, $DEFAULT_DEVICE);
    if ($ifaceName !== '') {
        [, , $rootInner] = root_interfaces_range($after);
        $higher = false;
        if (preg_match_all('@<opt(\d+)>@', $rootInner, $mm)) {
            $ours = (int)substr($ifaceName, 3);
            foreach ($mm[1] as $num) {
                if ((int)$num > $ours) {
                    $higher = true;
                }
            }
        }
        if ($higher) {
            $messages[] = 'interface block kept (' . $ifaceName . '): other opt interfaces exist, remove it manually if you want';
        } elseif (preg_match(
            '@[ \t]*<' . preg_quote($ifaceName, '@') . '>(?:(?!</' . preg_quote($ifaceName, '@') . '>).)*?</'
            . preg_quote($ifaceName, '@') . '>\r?\n?@s',
            $after,
            $mm,
            PREG_OFFSET_CAPTURE
        )) {
            $after = substr($after, 0, $mm[0][1]) . substr($after, $mm[0][1] + strlen($mm[0][0]));
            $messages[] = 'interface block removed: ' . $ifaceName . ' -> ' . $DEFAULT_DEVICE;
        }
    }
}

if ($after === $before) {
    out(['status' => 'ok', 'messages' => array_merge($messages, ['nothing changed']), 'diff' => '']);
    exit(0);
}

/* ---------------- 5. 备份 + 原子写入 ---------------- */
$backup = '/conf/config.xml.mihomo-bak.' . date('Ymd_His');
if (!copy($CONFIG_FILE, $backup)) {
    fail('unable to create backup ' . $backup, 3);
}
chmod($backup, 0600);

$tmp = $CONFIG_FILE . '.mihomo-new';
if (file_put_contents($tmp, $after) === false) {
    fail('unable to write ' . $tmp, 3);
}
/* XML 结构自检：能被解析才落盘 */
libxml_use_internal_errors(true);
$doc = new DOMDocument();
if (!$doc->loadXML($after)) {
    @unlink($tmp);
    $err = libxml_get_last_error();
    fail('generated config.xml is not valid XML: ' . ($err ? trim($err->message) : 'unknown'), 1);
}
if (!rename($tmp, $CONFIG_FILE)) {
    @unlink($tmp);
    fail('unable to install ' . $CONFIG_FILE, 3);
}
chmod($CONFIG_FILE, 0644);
$messages[] = 'config.xml written (backup ' . basename($backup) . ')';

/* ---------------- 6. 重载过滤器 + 安全自检（不通过就自动回滚） ----------------
 * 注意：绝不能在脚本里 `service configd restart` —— 本脚本正是由 configd 拉起的，
 * 重启它等于中断自己（输出丢失、后续步骤不执行）。实测踩过这个坑。 */
[$rc, $filterOut] = run_command('configctl filter reload');
$messages[] = $rc === 0 ? 'filter reload: OK' : 'filter reload failed: ' . $filterOut;

/* 关键自检：只要还有绑定，生成的 pf 规则就必须把流量送进 TUN 设备；否则立刻还原并报错 */
if ($interfaces !== []) {
    [$rc2, $routeOut] = run_command("pfctl -sr | grep 'route-to' | grep -c 'tun_mihomo'");
    $routeCount = (int)trim($routeOut);
    if ($routeCount < 1) {
        copy($backup, $CONFIG_FILE);
        chmod($CONFIG_FILE, 0644);
        run_command('configctl filter reload');
        fail(
            "safety check failed: no pf route-to rule points at tun_mihomo; config.xml was restored from "
            . basename($backup) . ". Check that the gateway interface is the TUN interface.",
            1
        );
    }
    $messages[] = 'pf route-to rules into tun_mihomo: ' . $routeCount;
} else {
    [$rc2, $routeOut] = run_command("pfctl -sr | grep 'route-to' | grep -c 'tun_mihomo'");
    $messages[] = 'pf route-to rules into tun_mihomo after unbind: ' . (int)trim($routeOut);
}

@unlink($staging);

out([
    'status' => 'ok',
    'messages' => $messages,
    'diff' => diff_text($before, $after, 'config.xml'),
    'state' => current_state(),
]);
