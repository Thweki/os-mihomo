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

    /** 对照项定义。
     *
     * key   = YAML 里的路径（点号分层）
     * label = 界面上的名字（与设置页表单标签保持一致，直接复用已有译文）
     * secret= 该行是敏感值，只显示"已设置/空"
     * run   = 运行值（内核 /configs）的取法：
     *         ['flat', 键] 顶层字段；['tun', 键] tun 子对象；['probe', 说明] 用探针推断
     *         没写 run 的项 = 内核不对外报告，界面显示"（内核不报告）"
     */
    private static function items(): array
    {
        return [
            ['key' => 'log-level', 'label' => gettext('Log Level'), 'run' => ['flat', 'log-level']],
            ['key' => 'mode', 'label' => gettext('Mode'), 'run' => ['flat', 'mode']],
            ['key' => 'allow-lan', 'label' => gettext('Allow LAN'), 'run' => ['flat', 'allow-lan']],
            ['key' => 'external-controller', 'label' => gettext('External Controller'), 'run' => ['controller', '']],
            ['key' => 'secret', 'label' => gettext('Secret'), 'secret' => true, 'run' => ['auth', '']],
            ['key' => 'tun.enable', 'label' => gettext('TUN Mode'), 'run' => ['tun', 'enable']],
            ['key' => 'tun.device', 'label' => gettext('Device Name'), 'run' => ['tun', 'device']],
            ['key' => 'tun.stack', 'label' => gettext('Stack'), 'run' => ['tun', 'stack']],
            ['key' => 'tun.auto-route', 'label' => gettext('Automatic Route'), 'run' => ['tun', 'auto-route']],
            ['key' => 'tun.strict-route', 'label' => gettext('Strict Route')],
            ['key' => 'tun.mtu', 'label' => gettext('MTU'), 'run' => ['tun', 'mtu']],
            ['key' => 'dns.enable', 'label' => gettext('DNS Module'), 'run' => ['dns-probe', 'enable']],
            ['key' => 'dns.listen', 'label' => gettext('Listen Address'), 'run' => ['dns-probe', 'listen']],
            ['key' => 'dns.enhanced-mode', 'label' => gettext('Enhanced Mode')],
            ['key' => 'dns.ipv6', 'label' => gettext('DNS over IPv6')],
            ['key' => 'ipv6', 'label' => gettext('IPv6 handling'), 'run' => ['flat', 'ipv6']],
            ['key' => 'sniffer.enable', 'label' => gettext('Domain sniffing'), 'run' => ['flat', 'sniffing']],
        ];
    }

    /** 只看运行值的附加项（文件里不一定写，内核有默认） */
    private static function runtimeOnlyItems(): array
    {
        return [
            ['key' => 'mixed-port', 'label' => gettext('Mixed port'), 'run' => ['flat', 'mixed-port']],
            ['key' => 'socks-port', 'label' => gettext('SOCKS port'), 'run' => ['flat', 'socks-port']],
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
     * @return array{status: string, rows: array, notes: array, differs: int, missing: int, runtime: bool}
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
        foreach ($rows as $row) {
            if ($row['state'] === self::STATE_DIFFERS) {
                $differs++;
            } elseif ($row['state'] === self::STATE_MISSING) {
                $missing++;
            }
        }

        $notes = [];
        if (!$runtime) {
            $notes[] = [
                'level' => 'info',
                'text' => gettext('The running service cannot be read right now (stopped, or the secret does not match), so only the page and the file are compared here.'),
            ];
        } else {
            $notes[] = [
                'level' => 'info',
                'text' => gettext('The "Running" column is what the core is using right now. Change the file and you still have to restart the service before it shows up here.'),
            ];
            $notes[] = [
                'level' => 'info',
                'text' => gettext('A few items are not reported by the core at all (strict route, DNS mode, ...), so their "Running" cell stays empty — only the file and the core log can tell.'),
            ];
        }
        if ($differs > 0) {
            $notes[] = [
                'level' => 'warning',
                'text' => gettext('The page and the file disagree on some items: press Apply to write what the page says into the file, or press Import to load what the file says into the page.'),
            ];
        }
        if (self::looksHandwritten($yaml)) {
            $notes[] = [
                'level' => 'warning',
                'text' => gettext('This config.yaml is hand-written, not generated from the subscription template. Updating the subscription replaces the whole file, so your own edits would be gone — do not use it, or take a backup first.'),
            ];
        }
        $notes[] = self::hasManagedBlock($yaml) ? [
            'level' => 'info',
            'text' => gettext('The file contains a block of rules that the plugin keeps up to date (from the Policy Routing page). Do not edit inside that block: it gets replaced as a whole.'),
        ] : [
            'level' => 'info',
            'text' => gettext('No interface is bound to mihomo right now, so the file contains no plugin-managed rules.'),
        ];
        if (self::ipv6Allowed($yaml)) {
            $notes[] = [
                'level' => 'warning',
                'text' => gettext('IPv6 traffic does not go through the proxy: the mihomo tunnel only handles IPv4. Add ipv6: false in the configuration if you want IPv6 handled by the normal route, or ignore this.'),
            ];
        }

        return [
            'status' => 'ok',
            'rows' => $rows,
            'notes' => $notes,
            'differs' => $differs,
            'missing' => $missing,
            'runtime' => $runtime,
        ];
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
            'tun.device' => (string)$mdl->tun->device,
            'tun.stack' => (string)$mdl->tun->stack,
            'tun.auto-route' => $flag($mdl->tun->autoRoute) ? 'true' : 'false',
            'tun.strict-route' => $flag($mdl->tun->strictRoute) ? 'true' : 'false',
            'tun.mtu' => (string)(int)(string)$mdl->tun->mtu,
            'dns.enable' => $flag($mdl->dns->enabled) ? 'true' : 'false',
            'dns.listen' => (string)$mdl->dns->listen,
            'dns.enhanced-mode' => (string)$mdl->dns->enhancedMode,
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
