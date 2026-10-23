<?php

/*
 * os-mihomo 二次开发 —— 「配置对照」（只读）
 *
 * 解决的问题：同一个设置可能存在于三个地方，用户很难知道"此刻到底在用什么"。
 *
 *   · 页面值（WebUI）  = /conf/config.xml 里 <OPNsense><mihomo> 的模型值（页面的"记忆"）
 *   · 文件值（File）   = /usr/local/etc/mihomo/config.yaml 里真正写着的那一行
 *   · 运行值（Running）= mihomo 进程内存里正在用的值（外部控制器 /configs）
 *
 * 三类不一致各自的含义（写进界面提示）：
 *   页面 ≠ 文件 → 改了页面没点「应用」，或手工改了文件而页面记忆过期
 *   文件 ≠ 运行 → 改了文件没重启服务，内核还在用启动那一刻读进去的配置
 *
 * 本类**只读**，不修改任何文件或系统状态。
 * 纯函数（normalize / yamlValue / looksHandwritten / managedBlock / compare）不依赖框架，
 * 便于在 CLI 回归测试里直接调用。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class Inspector
{
    /** 页面列 / 文件列一致 */
    public const STATE_MATCH = 'match';
    /** 两列都有但值不同 */
    public const STATE_DIFFERS = 'differs';
    /** 文件里没有这个键（内核用内置默认值） */
    public const STATE_MISSING = 'missing';
    /** 不适用（例如只在运行态出现的端口/IPv6 开关，页面管不到） */
    public const STATE_NA = 'na';

    /** 订阅模板的特征分组名：一个都找不到就认为这份配置是手写的 */
    private const TEMPLATE_MARKERS = [
        '🌍选择节点',
        '🐟漏网之鱼',
        'load-balance',
        'external-ui-url',
    ];

    /** 对照分组：机器键 => 界面标题（运行期取 gettext，跟随当前语言） */
    private static function groups(): array
    {
        return [
            'general' => gettext('General'),
            'tun' => 'TUN',
            'dns' => 'DNS',
            'other' => gettext('Other'),
            'ports' => gettext('Listening ports'),
        ];
    }

    /** 对照项定义。
     *
     * key   = YAML 里的路径（点号分层）
     * label = 界面上的名字（与设置页表单标签保持一致，直接复用已有译文）
     * group = 界面分组（groups() 的键）
     * secret= 该行是敏感值，只显示"已设置/空"
     * run   = 运行值（内核 /configs）的取法：
     *         ['flat', 键] 顶层字段；['tun', 键] tun 子对象；['probe', 说明] 用探针推断
     *         没写 run 的项 = 内核不对外报告，界面显示"（内核不报告）"
     */
    private static function items(): array
    {
        return [
            ['key' => 'log-level', 'label' => gettext('Log Level'), 'group' => 'general', 'run' => ['flat', 'log-level']],
            ['key' => 'mode', 'label' => gettext('Mode'), 'group' => 'general', 'run' => ['flat', 'mode']],
            ['key' => 'allow-lan', 'label' => gettext('Allow LAN'), 'group' => 'general', 'run' => ['flat', 'allow-lan']],
            ['key' => 'external-controller', 'label' => gettext('External Controller'), 'group' => 'general', 'run' => ['controller', '']],
            ['key' => 'secret', 'label' => gettext('Secret'), 'group' => 'general', 'secret' => true, 'run' => ['auth', '']],
            ['key' => 'tun.enable', 'label' => gettext('TUN Mode'), 'group' => 'tun', 'run' => ['tun', 'enable']],
            ['key' => 'tun.device', 'label' => gettext('Device Name'), 'group' => 'tun', 'run' => ['tun', 'device']],
            ['key' => 'tun.stack', 'label' => gettext('Stack'), 'group' => 'tun', 'run' => ['tun', 'stack']],
            ['key' => 'tun.auto-route', 'label' => gettext('Automatic Route'), 'group' => 'tun', 'run' => ['tun', 'auto-route']],
            ['key' => 'tun.strict-route', 'label' => gettext('Strict Route'), 'group' => 'tun'],
            ['key' => 'tun.mtu', 'label' => gettext('MTU'), 'group' => 'tun', 'run' => ['tun', 'mtu']],
            ['key' => 'dns.enable', 'label' => gettext('DNS Module'), 'group' => 'dns', 'run' => ['dns-probe', 'enable']],
            ['key' => 'dns.listen', 'label' => gettext('Listen Address'), 'group' => 'dns', 'run' => ['dns-probe', 'listen']],
            ['key' => 'dns.enhanced-mode', 'label' => gettext('Enhanced Mode'), 'group' => 'dns'],
            ['key' => 'dns.ipv6', 'label' => gettext('DNS over IPv6'), 'group' => 'dns'],
            ['key' => 'ipv6', 'label' => gettext('IPv6 handling'), 'group' => 'other', 'run' => ['flat', 'ipv6']],
            ['key' => 'sniffer.enable', 'label' => gettext('Domain sniffing'), 'group' => 'other', 'run' => ['flat', 'sniffing']],
        ];
    }

    /** 只看运行值的附加项（文件里不一定写，内核有默认） */
    private static function runtimeOnlyItems(): array
    {
        return [
            ['key' => 'mixed-port', 'label' => gettext('Mixed port'), 'group' => 'ports', 'run' => ['flat', 'mixed-port']],
            ['key' => 'socks-port', 'label' => gettext('SOCKS port'), 'group' => 'ports', 'run' => ['flat', 'socks-port']],
        ];
    }

    /* =====================================================================
     * 纯函数（可在 CLI 测试里直接调用）
     * ===================================================================== */

    /**
     * 把各种写法归一化，便于比较：true/1/yes/on → 'true'，false/0/no/off → 'false'，
     * 其余去掉首尾引号与空白后返回小写。
     */
    public static function normalize(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }
        $text = trim((string)$value);
        $text = trim($text, "\"'");
        $lower = strtolower($text);
        if (in_array($lower, ['true', 'yes', 'on', '1'], true)) {
            return 'true';
        }
        if (in_array($lower, ['false', 'no', 'off', '0'], true)) {
            return 'false';
        }
        return $lower;
    }

    /**
     * 取 YAML 文本里某个路径的值（按缩进找，只看第一个匹配；行尾注释去掉）。
     * 找不到返回 null。不做完整 YAML 解析 —— 我们只需要"那一行长什么样"。
     */
    public static function yamlValue(string $yaml, string $path): ?string
    {
        $lines = preg_split("/\r\n|\n|\r/", $yaml) ?: [];
        $segments = explode('.', $path);
        $indent = 0;
        $start = 0;

        foreach ($segments as $index => $key) {
            $pattern = '/^' . str_repeat(' ', $indent) . preg_quote($key, '/') . ':[ \t]*(.*)$/';
            $found = null;
            for ($i = $start; $i < count($lines); $i++) {
                if (preg_match($pattern, $lines[$i], $m)) {
                    $found = [$i, $m[1]];
                    break;
                }
            }
            if ($found === null) {
                return null;
            }
            [$start, $raw] = $found;

            $value = trim($raw);
            $last = $index === count($segments) - 1;
            if ($last) {
                return self::stripComment($value);
            }
            if ($value === '') {
                $indent += 2;
                $start++;
                continue;
            }
            /* 形如 tun: {enable: true} 的流式写法：简化处理，不深挖 */
            return null;
        }
        return null;
    }

    /** 去掉行尾注释（引号内的 # 不算注释） */
    private static function stripComment(string $value): string
    {
        if ($value === '') {
            return '';
        }
        if ($value[0] === '"' || $value[0] === "'") {
            $quote = $value[0];
            $end = strpos($value, $quote, 1);
            return $end === false ? $value : substr($value, 0, $end + 1);
        }
        $pos = strpos($value, ' #');
        if ($pos === false) {
            $pos = strpos($value, "\t#");
        }
        return $pos === false ? $value : rtrim(substr($value, 0, $pos));
    }

    /** 这份配置看起来是"手写的"还是"订阅模板生成的" */
    public static function looksHandwritten(string $yaml): bool
    {
        if (trim($yaml) === '') {
            return false;
        }
        foreach (self::TEMPLATE_MARKERS as $marker) {
            if (str_contains($yaml, $marker)) {
                return false;
            }
        }
        return true;
    }

    /** 受管区块（路由策略写进 rules 的那段）是否存在 */
    public static function hasManagedBlock(string $yaml): bool
    {
        return str_contains($yaml, Config::POLICY_MARK_BEGIN);
    }

    /** 配置是否允许 IPv6（没写或写 true 就是允许；允许则 IPv6 会绕过 mihomo） */
    public static function ipv6Allowed(string $yaml): bool
    {
        $value = self::normalize(self::yamlValue($yaml, 'ipv6') ?? 'true');
        return $value !== 'false';
    }

    /**
     * 生成对照表。
     *
     * @param string     $yaml    config.yaml 全文
     * @param array      $model   ['<yaml 路径>' => 页面里的值]
     * @param array|null $runtime mihomo /configs 的解码结果；null = 服务没跑/读不到
     * @return array<int, array{key: string, label: string, model: string, file: string, runtime: string, state: string, secret: bool}>
     */
    public static function compare(string $yaml, array $model, ?array $runtime, array $probe = []): array
    {
        $rows = [];
        foreach (self::items() as $item) {
            $rows[] = self::buildRow($item, $yaml, $model, $runtime, false, $probe);
        }
        foreach (self::runtimeOnlyItems() as $item) {
            $rows[] = self::buildRow($item, $yaml, $model, $runtime, true, $probe);
        }
        return $rows;
    }

    /**
     * 探针 1：内核到底要不要校验密钥。
     * 用错误的密钥问一次 /version：401 = 会校验（说明密钥确实设置了）；200 = 不校验。
     */
    public static function authProbe(): ?string
    {
        if (Config::controllerBase() === null) {
            return null;
        }
        $ch = curl_init(Config::controllerBase() . '/version');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_TIMEOUT => 3,
            CURLOPT_HTTPHEADER => ['Authorization: Bearer __os-mihomo-probe__'],
        ]);
        curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code === 0) {
            return null;
        }
        return $code === 401 || $code === 403
            ? gettext('checked by the core')
            : gettext('not checked (no secret)');
    }

    /**
     * 探针 2：mihomo 自己的 DNS 是否在配置里写的地址上应答。
     * 发一个最小的 example.com/A 查询，只看有没有正常应答 —— 不改动任何状态。
     */
    public static function dnsProbe(string $yaml): ?string
    {
        $listen = self::yamlValue($yaml, 'dns.listen');
        if ($listen === null) {
            return null;
        }
        $listen = trim($listen, "\"'");
        if (!str_contains($listen, ':')) {
            return null;
        }
        [$host, $port] = explode(':', $listen, 2);
        $port = (int)$port;
        if ($port <= 0) {
            return null;
        }
        if ($host === '' || $host === '0.0.0.0') {
            $host = '127.0.0.1';
        }

        $query = "\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            . "\x07example\x03com\x00" . "\x00\x01\x00\x01";

        $answer = false;
        try {
            $socket = @stream_socket_client(
                sprintf('udp://%s:%d', $host, $port),
                $errno,
                $errstr,
                1
            );
            if ($socket !== false) {
                stream_set_timeout($socket, 2);
                fwrite($socket, $query);
                $response = fread($socket, 512);
                fclose($socket);
                if (is_string($response) && strlen($response) >= 12) {
                    $answer = true;
                }
            }
        } catch (\Throwable $e) {
            $answer = false;
        }

        return $answer
            ? sprintf(gettext('%s (answering)'), $listen)
            : sprintf(gettext('%s (no answer)'), $listen);
    }

    /** 单行对照 */
    private static function buildRow(array $item, string $yaml, array $model, ?array $runtime, bool $runtimeOnly = false, array $probe = []): array
    {
        $key = $item['key'];
        $secret = (bool)($item['secret'] ?? false);
        $groupKey = (string)($item['group'] ?? 'other');
        $groups = self::groups();

        /* 只在运行态出现的键（mixed-port / ipv6…）：页面管不到，不参与"页面 vs 文件"判定 */
        $modelValue = array_key_exists($key, $model) ? (string)$model[$key] : null;
        $fileValue = self::yamlValue($yaml, $key);
        $runtimeValue = null;
        if ($runtime !== null && isset($item['run'])) {
            [$where, $name] = $item['run'];
            if ($where === 'controller') {
                /* 内核能应答，就证明它确实在这个地址上监听 */
                $base = Config::controllerBase();
                $runtimeValue = $base === null ? null : preg_replace('@^https?://@', '', $base);
            } elseif ($where === 'auth') {
                $runtimeValue = $probe['auth_enforced'] ?? null;
            } elseif ($where === 'dns-probe') {
                $runtimeValue = $probe['dns'] ?? null;
            } else {
                $source = $where === 'tun' ? ($runtime['tun'] ?? null) : $runtime;
                if (is_array($source) && array_key_exists($name, $source)) {
                    $runtimeValue = is_bool($source[$name])
                        ? ($source[$name] ? 'true' : 'false')
                        : (string)$source[$name];
                }
            }
        }

        $state = self::STATE_MATCH;
        if ($runtimeOnly) {
            $state = self::STATE_NA;
        } elseif ($fileValue === null) {
            $state = self::STATE_MISSING;
        } elseif (self::normalize($fileValue) !== self::normalize($modelValue)) {
            $state = self::STATE_DIFFERS;
        }

        if ($secret) {
            $modelValue = $modelValue === null || $modelValue === ''
                ? gettext('(empty)') : gettext('(set, hidden)');
            $fileValue = $fileValue === null
                ? gettext('(not set in the file)') : (trim($fileValue, "\"'") === '' ? gettext('(empty)') : gettext('(set, hidden)'));
            $state = ($fileValue === gettext('(empty)') && $modelValue === gettext('(empty)')) || ($fileValue === gettext('(set, hidden)') && $modelValue === gettext('(set, hidden)'))
                ? self::STATE_MATCH : self::STATE_DIFFERS;
        }

        return [
            'key' => $key,
            'label' => $item['label'],
            'group' => $groupKey,
            'group_label' => $groups[$groupKey] ?? $groups['other'],
            'model' => $modelValue === null ? '' : (string)$modelValue,
            'file' => $fileValue === null ? gettext('(not set in the file)') : (string)$fileValue,
            'runtime' => $runtimeValue === null ? '' : (string)$runtimeValue,
            'state' => $state,
            'secret' => $secret,
            'runtime_only' => $runtimeOnly,
        ];
    }

    /* =====================================================================
     * 组装报告（依赖框架：模型 + 控制器）
     * ===================================================================== */

    /**
     * @return array{status: string, rows: array, differs: int, missing: int, runtime: bool}
     */
    public static function report(): array
    {
        $yaml = Config::rawText();
        $runtimeValues = self::runtimeValues();
        $runtime = $runtimeValues !== null;
        $probe = [
            'auth_enforced' => $runtime ? self::authProbe() : null,
            'dns' => $runtime ? self::dnsProbe($yaml) : null,
        ];
        $rows = self::compare($yaml, self::modelValues(), $runtimeValues, $probe);

        $differs = 0;
        $missing = 0;
        $match = 0;
        foreach ($rows as $row) {
            if ($row['state'] === self::STATE_DIFFERS) {
                $differs++;
            } elseif ($row['state'] === self::STATE_MISSING) {
                $missing++;
            } elseif ($row['state'] === self::STATE_MATCH) {
                $match++;
            }
        }

        return [
            'status' => 'ok',
            'rows' => $rows,
            'match' => $match,
            'differs' => $differs,
            'missing' => $missing,
            'runtime' => $runtime,
        ];
    }

    /* =====================================================================
     * DNS 去向（只读）：mihomo DNS、53 劫持覆盖、各接口的客户端 DNS 路径
     * ===================================================================== */

    /**
     * DNS 现状报告。
     *
     * 只读：不修改配置文件、不重启服务、不碰防火墙。
     * 结论基于「配置文件 + 运行态 + config.xml 的接口/Unbound/策略行」；
     * 实际 pf 规则是否生效仍以路由策略页的状态为准。
     */
    public static function dnsReport(): array
    {
        $yaml = Config::rawText();
        $scan = Config::scanText($yaml);
        $serviceRunning = self::serviceRunning();
        $runtime = $serviceRunning ? self::runtimeValues() : null;
        $tunRuntime = is_array($runtime['tun'] ?? null) ? $runtime['tun'] : [];

        $dnsEnabled = self::boolValue($scan['dns.enable'] ?? null, false);
        $tunEnabled = self::boolValue(
            $scan['tun.enable'] ?? null,
            self::boolValue($tunRuntime['enable'] ?? null, false)
        );
        $listen = trim((string)($scan['dns.listen'] ?? '127.0.0.1:1053'));
        $mode = trim((string)($scan['dns.enhanced-mode'] ?? 'redir-host'));
        $dnsIpv6 = self::boolValue($scan['dns.ipv6'] ?? null, false);
        $hijack = self::hijackReport($yaml, $tunRuntime);
        $unbound = self::unboundReport();
        $interfaces = self::dnsInterfaceRows($hijack, $unbound, $tunEnabled, $dnsEnabled, $serviceRunning);
        $warnings = self::dnsWarnings($hijack, $interfaces, $tunEnabled, $dnsEnabled, $serviceRunning, $yaml);

        return [
            'status' => 'ok',
            'dns' => [
                'enabled' => $dnsEnabled,
                'listen' => $listen,
                'mode' => $mode,
                'ipv6' => $dnsIpv6,
                'tun_enabled' => $tunEnabled,
                'service_running' => $serviceRunning,
                'controller_alive' => $runtime !== null,
            ],
            'hijack' => $hijack,
            'unbound' => $unbound,
            'upstream' => [
                'nameserver' => preg_match('/^\s+nameserver:\s*(?:$|\[)/m', $yaml) === 1,
                'nameserver_policy' => preg_match('/^\s+nameserver-policy:\s*(?:$|\{)/m', $yaml) === 1,
                'respect_rules' => self::boolValue($scan['dns.respect-rules'] ?? null, false),
            ],
            'interfaces' => $interfaces,
            'warnings' => $warnings,
        ];
    }

    /** YAML/运行态里的布尔值归一化（Config::scanText() 读出来的是字符串） */
    private static function boolValue(mixed $value, bool $default): bool
    {
        if ($value === null || $value === '') {
            return $default;
        }
        if (is_bool($value)) {
            return $value;
        }
        return in_array(strtolower(trim((string)$value, "\"'")), ['1', 'true', 'yes', 'on'], true);
    }

    /** mihomo 服务是否在跑（configd 只读状态） */
    private static function serviceRunning(): bool
    {
        try {
            $output = (string)(new \OPNsense\Core\Backend())->configdRun('mihomo status');
            return str_contains($output, 'is running');
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * TUN 的 DNS 劫持覆盖。
     *
     * 优先级：运行态 /configs（mihomo 会补默认值）> config.yaml > 内核默认。
     * 注意：没有协议前缀的条目按 udp:// 处理（mihomo 文档语义）。
     */
    private static function hijackReport(string $yaml, array $tunRuntime): array
    {
        $entries = [];
        $source = 'default';
        $runtimeEntries = $tunRuntime['dns-hijack'] ?? null;
        if (is_array($runtimeEntries) && $runtimeEntries !== []) {
            $entries = array_values(array_filter(array_map('strval', $runtimeEntries)));
            $source = 'runtime';
        } else {
            $fileEntries = self::yamlList($yaml, 'dns-hijack');
            if ($fileEntries !== null) {
                $entries = $fileEntries;
                $source = 'file';
            }
        }
        if ($entries === [] && $source === 'default') {
            /* mihomo 未写 dns-hijack 时的默认值（实测 /configs 里是 0.0.0.0:53） */
            $entries = ['0.0.0.0:53'];
        }

        $udp = false;
        $tcp = false;
        $port53 = false;
        foreach ($entries as $entry) {
            $proto = 'udp';
            $value = trim($entry);
            if (preg_match('@^(tcp|udp)://(.+)$@i', $value, $m)) {
                $proto = strtolower($m[1]);
                $value = $m[2];
            }
            if (preg_match('@:53$@', trim($value))) {
                $port53 = true;
                if ($proto === 'tcp') {
                    $tcp = true;
                } else {
                    $udp = true;
                }
            }
        }

        return [
            'entries' => $entries,
            'source' => $source,
            'udp' => $udp,
            'tcp' => $tcp,
            'port53' => $port53,
            'coverage' => $udp && $tcp ? 'udp+tcp' : ($udp ? 'udp' : ($tcp ? 'tcp' : 'none')),
        ];
    }

    /**
     * 读取 YAML 里某个键的列表。
     * 返回值：null = 键不存在；[] = 键存在但为空；[...] = 列表项。
     */
    private static function yamlList(string $yaml, string $key): ?array
    {
        $lines = preg_split("/\r\n|\n|\r/", $yaml) ?: [];
        $collect = false;
        $indent = 0;
        $out = [];
        foreach ($lines as $line) {
            if (!$collect) {
                if (!preg_match('/^(\s*)' . preg_quote($key, '/') . ':\s*(.*)$/', $line, $m)) {
                    continue;
                }
                $indent = strlen($m[1]);
                $inline = trim(preg_replace('/\s+#.*$/', '', $m[2]));
                if ($inline === '') {
                    $collect = true;
                    continue;
                }
                if (preg_match('/^\[(.*)\]$/', $inline, $im)) {
                    foreach (explode(',', $im[1]) as $item) {
                        $item = trim(trim($item), "\"'");
                        if ($item !== '') {
                            $out[] = $item;
                        }
                    }
                }
                return $out;
            }

            if (trim($line) === '' || preg_match('/^\s*#/', $line)) {
                continue;
            }
            $lineIndent = strlen($line) - strlen(ltrim($line));
            if ($lineIndent <= $indent) {
                break;
            }
            if (preg_match('/^\s*-\s*(.*)$/', $line, $m)) {
                $item = trim(preg_replace('/\s+#.*$/', '', $m[1]));
                $item = trim($item, "\"'");
                if ($item !== '') {
                    $out[] = $item;
                }
            }
        }
        return $collect ? $out : null;
    }

    /** Unbound 是否启用、监听哪些接口（空列表 = 所有接口） */
    private static function unboundReport(): array
    {
        $result = ['enabled' => true, 'all' => true, 'interfaces' => []];
        try {
            $cfg = \OPNsense\Core\Config::getInstance()->object();
            $node = null;
            /* OPNsense 26.x 把 Unbound 设置放在 <OPNsense><unboundplus>；旧版是 <unbound>。 */
            foreach ([
                $cfg->OPNsense->unboundplus ?? null,
                $cfg->unboundplus ?? null,
                $cfg->OPNsense->unbound ?? null,
                $cfg->unbound ?? null,
            ] as $candidate) {
                if ($candidate !== null) {
                    $node = $candidate;
                    break;
                }
            }
            if ($node === null) {
                return $result;
            }
            $general = isset($node->general) ? $node->general : $node;
            $enabledRaw = $general->enabled ?? ($node->enabled ?? ($node->enable ?? null));
            $result['enabled'] = self::boolValue($enabledRaw, true);
            $raw = trim((string)($general->active_interface ?? ($node->active_interface ?? '')));
            if ($raw === '') {
                $result['all'] = true;
            } else {
                $result['all'] = false;
                $result['interfaces'] = array_values(array_filter(array_map('trim', explode(',', $raw))));
            }
        } catch (\Throwable $e) {
            /* 读不到就按默认：Unbound 在跑、监听所有接口 */
        }
        return $result;
    }

    /** 本插件策略行：interface => [target/scope/firewall, ...]（只取已启用） */
    private static function policyRows(): array
    {
        $rows = [];
        try {
            $mdl = new Mihomo();
            foreach ($mdl->policyRouting->rule->iterateItems() as $item) {
                if ((string)$item->enabled === '0') {
                    continue;
                }
                $iface = trim((string)$item->interface);
                if ($iface === '') {
                    continue;
                }
                $rows[$iface][] = [
                    'source' => trim((string)$item->source),
                    'target' => trim((string)$item->target),
                    'scope' => trim((string)$item->scope),
                    'firewall' => trim((string)$item->firewall),
                ];
            }
        } catch (\Throwable $e) {
            /* 模型不可读时返回空表 */
        }
        return $rows;
    }

    /**
     * 网络侧已建好策略路由规则的接口（只读）。
     *
     * OPNsense 26.x 的浮动规则在 <OPNsense><Firewall><Filter><rules>，
     * 旧版在 <filter><rule>；两处都认，避免把“已生效”误判成“待同步”。
     */
    private static function policyRuleInterfaces(): array
    {
        $result = [];
        try {
            $cfg = \OPNsense\Core\Config::getInstance()->object();
            $gatewayExists = false;
            if (isset($cfg->OPNsense->Gateways)) {
                foreach ($cfg->OPNsense->Gateways->gateway_item as $item) {
                    if ((string)$item->name === 'MIHOMO_TUN') {
                        $gatewayExists = true;
                        break;
                    }
                }
            }
            if (!$gatewayExists) {
                return $result;
            }

            $scan = function ($rules) use (&$result): void {
                foreach ($rules as $item) {
                    if ((string)($item->enabled ?? '1') === '0') {
                        continue;
                    }
                    if ((string)$item->gateway !== 'MIHOMO_TUN') {
                        continue;
                    }
                    $descr = (string)($item->description ?? '');
                    if ($descr === '') {
                        $descr = (string)($item->descr ?? '');
                    }
                    if (stripos($descr, 'Mihomo policy') === false) {
                        continue;
                    }
                    /* 浮动规则用 source_net 表示来源接口；旧规则可能用 interface。 */
                    $source = trim((string)($item->source_net ?? ''));
                    if ($source === '') {
                        $source = trim((string)($item->interface ?? ''));
                    }
                    if ($source !== '') {
                        $result[$source] = true;
                    }
                }
            };

            if (isset($cfg->OPNsense->Firewall->Filter->rules->rule)) {
                $scan($cfg->OPNsense->Firewall->Filter->rules->rule);
            }
            if (isset($cfg->filter->rule)) {
                $scan($cfg->filter->rule);
            }
        } catch (\Throwable $e) {
            /* 只读判断失败按未就绪处理 */
        }
        return $result;
    }

    /** 每个 OPNsense 接口的 DNS 去向 */
    private static function dnsInterfaceRows(
        array $hijack,
        array $unbound,
        bool $tunEnabled,
        bool $dnsEnabled,
        bool $serviceRunning
    ): array {
        $policy = self::policyRows();
        $readyRules = self::policyRuleInterfaces();
        $rows = [];
        try {
            $cfg = \OPNsense\Core\Config::getInstance()->object();
            if (!isset($cfg->interfaces)) {
                return [];
            }
            foreach ($cfg->interfaces->children() as $name => $node) {
                $device = trim((string)$node->if);
                if ($device === 'lo0' || (string)$node->internal_dynamic === '1') {
                    continue;
                }
                $ip = trim((string)$node->ipaddr);
                if ($ip === '' || !filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                    continue;
                }
                $mask = trim((string)$node->subnet);
                $address = $ip . (ctype_digit($mask) && $mask !== '' ? '/' . $mask : '');
                $descr = trim((string)$node->descr);
                $pr = $policy[$name] ?? [];
                $bound = $pr !== [];
                $networkReady = false;
                $firewall = 'none';
                $targets = [];
                foreach ($pr as $item) {
                    if (isset($readyRules[$name]) || ($item['source'] !== '' && isset($readyRules[$item['source']]))) {
                        $networkReady = true;
                    }
                    if ($item['firewall'] === 'auto') {
                        $firewall = 'auto';
                    } elseif ($firewall === 'none') {
                        $firewall = 'manual';
                    }
                    $targets[] = $item['target'] !== '' ? $item['target'] : 'DIRECT';
                }
                $targets = array_values(array_unique($targets));
                $unboundHere = $unbound['enabled'] && ($unbound['all'] || in_array($name, $unbound['interfaces'], true));

                $path = 'none';
                $state = 'warning';
                $note = '';
                if ($bound && $firewall === 'manual') {
                    $path = 'manual';
                    $note = gettext('Manual policy routing: verify that pf sends this interface into the TUN device.');
                } elseif ($bound && $firewall === 'auto' && !$networkReady) {
                    $path = 'pending';
                    $note = gettext('Waiting for the OPNsense side: apply the routing policy to create the interface, gateway and firewall rule.');
                } elseif ($bound && !$tunEnabled) {
                    $note = gettext('TUN is off: DNS queries cannot reach mihomo.');
                } elseif ($bound && !$serviceRunning) {
                    $state = 'danger';
                    $note = gettext('mihomo is not running: DNS on this interface will fail.');
                } elseif ($bound && !$dnsEnabled) {
                    $state = 'danger';
                    $note = gettext('The DNS module is off: mihomo cannot answer DNS queries.');
                } elseif ($bound && !$hijack['port53']) {
                    $note = gettext('No port 53 hijack: DNS queries are not sent to mihomo.');
                } elseif ($bound) {
                    $path = 'mihomo';
                    $state = 'ok';
                    if ($hijack['udp'] && $hijack['tcp']) {
                        $note = gettext('UDP and TCP 53 are hijacked.');
                    } elseif ($hijack['udp']) {
                        $note = gettext('UDP 53 is hijacked; TCP DNS is not covered.');
                    } else {
                        $note = gettext('TCP 53 is hijacked; UDP DNS is not covered.');
                    }
                } elseif ($unboundHere) {
                    $path = 'unbound';
                    $state = 'muted';
                    $note = gettext('Not policy-routed: Unbound answers DNS on this interface.');
                } else {
                    $note = gettext('No DNS listener: set a DNS server that this interface can reach.');
                }

                if ($path === 'mihomo' && $unboundHere) {
                    $note .= ' ' . gettext('Unbound is also listening on this address; the TUN policy normally wins.');
                }

                $rows[] = [
                    'interface' => $name,
                    'device' => $device,
                    'description' => $descr,
                    'address' => $address,
                    'bound' => $bound,
                    'targets' => $targets,
                    'firewall' => $firewall,
                    'unbound' => $unboundHere,
                    'path' => $path,
                    'state' => $state,
                    'note' => $note,
                ];
            }
        } catch (\Throwable $e) {
            /* 取不到接口就返回空表 */
        }
        usort($rows, fn ($a, $b) => strcmp($a['interface'], $b['interface']));
        return $rows;
    }

    /** 汇总提示（只读） */
    private static function dnsWarnings(
        array $hijack,
        array $interfaces,
        bool $tunEnabled,
        bool $dnsEnabled,
        bool $serviceRunning,
        string $yaml
    ): array {
        $warnings = [];
        $bound = array_values(array_filter($interfaces, fn ($row) => $row['bound']));
        if ($bound === []) {
            $warnings[] = [
                'level' => 'info',
                'text' => gettext('No interface is bound to mihomo: DNS on all interfaces is handled by Unbound or by the clients themselves.'),
            ];
            return $warnings;
        }
        if (!$tunEnabled) {
            $warnings[] = ['level' => 'warning', 'text' => gettext('TUN is off: bound interfaces cannot send DNS to mihomo.')];
        }
        if (!$serviceRunning) {
            $warnings[] = ['level' => 'danger', 'text' => gettext('mihomo is not running: DNS on bound interfaces will fail.')];
        }
        if (!$dnsEnabled) {
            $warnings[] = ['level' => 'danger', 'text' => gettext('The DNS module is off: bound interfaces cannot use mihomo DNS.')];
        }
        if ($hijack['port53'] && !$hijack['tcp']) {
            $warnings[] = [
                'level' => 'warning',
                'text' => gettext('Only UDP 53 is hijacked. Add tcp://any:53 to also cover TCP DNS.'),
            ];
        }
        if ($hijack['port53'] && !$hijack['udp']) {
            $warnings[] = [
                'level' => 'warning',
                'text' => gettext('Only TCP 53 is hijacked. Add any:53 to also cover UDP DNS.'),
            ];
        }
        if (!$hijack['port53']) {
            $warnings[] = [
                'level' => 'warning',
                'text' => gettext('No port 53 hijack is configured: bound interfaces will not use mihomo DNS.'),
            ];
        }
        $both = [];
        $manual = [];
        foreach ($bound as $row) {
            if ($row['unbound']) {
                $both[] = $row['interface'];
            }
            if ($row['firewall'] === 'manual') {
                $manual[] = $row['interface'];
            }
        }
        if ($both !== []) {
            $warnings[] = [
                'level' => 'warning',
                'text' => sprintf(
                    gettext('Unbound is also listening on %s. Keep it off these interfaces, or make sure the TUN policy wins.'),
                    implode(', ', $both)
                ),
            ];
        }
        if ($manual !== []) {
            $warnings[] = [
                'level' => 'warning',
                'text' => sprintf(
                    gettext('Manual policy routing on %s: verify the pf rules yourself.'),
                    implode(', ', $manual)
                ),
            ];
        }
        $hasNameserver = preg_match('/^\s+nameserver:\s*(?:$|\[)/m', $yaml) === 1;
        $hasPolicy = preg_match('/^\s+nameserver-policy:\s*(?:$|\{)/m', $yaml) === 1;
        if (!$hasNameserver && !$hasPolicy) {
            $warnings[] = [
                'level' => 'info',
                'text' => gettext('No nameserver or nameserver-policy is configured: mihomo uses its default upstreams, which may not be pollution-resistant.'),
            ];
        }
        return $warnings;
    }

    /** 页面里的值（与 SettingsController::modelPatch() 的键一一对应） */
    private static function modelValues(): array
    {
        $mdl = new Mihomo();
        $flag = fn ($node) => ((string)$node === '1');

        return [
            'log-level' => (string)$mdl->general->logLevel,
            'mode' => (string)$mdl->general->mode,
            'allow-lan' => $flag($mdl->general->allowLan) ? 'true' : 'false',
            'external-controller' => sprintf(
                '%s:%s',
                (string)$mdl->general->controllerBind,
                (string)$mdl->general->controllerPort
            ),
            'secret' => (string)$mdl->general->secret,
            'tun.enable' => $flag($mdl->tun->enabled) ? 'true' : 'false',
            'tun.device' => Config::fixedValue('tun.device', (string)$mdl->tun->device),
            'tun.stack' => Config::fixedValue('tun.stack', (string)$mdl->tun->stack),
            'tun.auto-route' => $flag($mdl->tun->autoRoute) ? 'true' : 'false',
            'tun.strict-route' => $flag($mdl->tun->strictRoute) ? 'true' : 'false',
            'tun.mtu' => (string)(int)(string)$mdl->tun->mtu,
            'dns.enable' => $flag($mdl->dns->enabled) ? 'true' : 'false',
            'dns.listen' => (string)$mdl->dns->listen,
            'dns.enhanced-mode' => (string)$mdl->dns->enhancedMode,
            'dns.ipv6' => $flag($mdl->dns->ipv6) ? 'true' : 'false',
            'ipv6' => $flag($mdl->general->ipv6) ? 'true' : 'false',
            'sniffer.enable' => $flag($mdl->general->sniffer) ? 'true' : 'false',
        ];
    }

    /** 运行值：读不到（服务没跑/密钥不对）返回 null */
    private static function runtimeValues(): ?array
    {
        $response = Controller::request('GET', '/configs', null, 3.0);
        if (!$response['ok'] || !is_array($response['data'])) {
            return null;
        }
        return $response['data'];
    }
}
