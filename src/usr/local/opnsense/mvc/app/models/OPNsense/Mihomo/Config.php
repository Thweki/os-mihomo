<?php

/*
 * os-mihomo 二次开发 —— mihomo 配置文件（config.yaml）访问层
 *
 * 设计要点：
 *  - 只读操作（扫描键值）直接由 php-fpm 的 www 用户完成（config.yaml 为 0644）。
 *  - 所有写操作必须经 configd（root），本类只负责生成内容 / 给出临时文件路径。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

namespace OPNsense\Mihomo;

class Config
{
    /** 主配置文件的绝对路径（与 rc.d/mihomo 保持一致） */
    public const FILE = '/usr/local/etc/mihomo/config.yaml';

    /** 订阅模板文件（上游 sub.sh 使用） */
    public const TEMPLATE_FILE = '/usr/local/etc/mihomo/sub/template_config.yaml';

    /** 备份文件前缀 */
    public const BACKUP_PREFIX = 'config.yaml.bak.';

    /** 测试用：覆盖配置文件路径（生产代码不要调用） */
    private static ?string $fileOverride = null;

    public static function setFileOverride(?string $path): void
    {
        self::$fileOverride = $path;
    }

    /** 当前生效的配置文件路径 */
    public static function file(): string
    {
        return self::$fileOverride ?? self::FILE;
    }

    /**
     * 简易 YAML 扫描：把「缩进的 key: value」展平成 "a.b.c" => scalar。
     * 只用于读取少量顶层/两层标量（log-level / tun.enable / …），
     * 不是通用 YAML 解析器；列表、锚点、多行块会被忽略。
     */
    public static function scan(?string $file = null): array
    {
        $file = $file ?? self::file();
        if (!is_file($file) || !is_readable($file)) {
            return [];
        }
        return self::scanText((string)file_get_contents($file));
    }

    /**
     * 扫描一段 YAML 文本（供内存中的内容使用，避免重复读盘）。
     */
    public static function scanText(string $content): array
    {
        $result = [];
        $stack = [];
        $lines = preg_split("/\r\n|\n|\r/", $content) ?: [];
        foreach ($lines as $line) {
            if (trim($line) === '' || preg_match('/^\s*#/', $line)) {
                continue;
            }
            /* 列表项（"- xxx"）不参与键路径计算 */
            if (preg_match('/^\s*-\s/', $line)) {
                continue;
            }
            if (!preg_match('/^(\s*)"?([A-Za-z0-9_.\-\/]+)"?:(\s+(.*))?$/', $line, $m)) {
                continue;
            }
            $indent = strlen($m[1]);
            $key = $m[2];
            $raw = ($m[3] ?? '') !== '' ? rtrim($m[4]) : null;

            while (!empty($stack) && end($stack)['indent'] >= $indent) {
                array_pop($stack);
            }
            $path = implode('.', array_merge(array_column($stack, 'key'), [$key]));

            if ($raw === null || $raw === '') {
                $stack[] = ['indent' => $indent, 'key' => $key];
                continue;
            }
            /* 去掉行尾注释与包裹引号 */
            $value = preg_replace('/\s+#.*$/', '', $raw);
            $value = trim((string)$value);
            if (strlen($value) >= 2 && (
                ($value[0] === '"' && substr($value, -1) === '"') ||
                ($value[0] === "'" && substr($value, -1) === "'")
            )) {
                $value = substr($value, 1, -1);
            }
            $result[$path] = $value;
        }
        return $result;
    }

    /**
     * 取一个键，带默认值。支持 "tun.enable" 形式。
     */
    public static function get(string $key, mixed $default = null): mixed
    {
        return self::scan()[$key] ?? $default;
    }

    public static function bool(string $key, bool $default = false): bool
    {
        $value = self::scan()[$key] ?? null;
        if ($value === null) {
            return $default;
        }
        return in_array(strtolower((string)$value), ['true', 'yes', 'on', '1'], true);
    }

    /** config.yaml 是否可读 */
    public static function exists(): bool
    {
        return is_file(self::file());
    }

    /** 原始内容（不可读时返回空串） */
    public static function rawText(): string
    {
        return self::exists() ? (string)file_get_contents(self::file()) : '';
    }

    /**
     * 由 external-controller 推导出可供本机访问的 REST 基址。
     *  "0.0.0.0:9090" / ":9090" / "127.0.0.1:9090" / "http://127.0.0.1:9090"
     */
    public static function controllerBase(): ?string
    {
        $value = trim((string)(self::scan()['external-controller'] ?? ''));
        if ($value === '') {
            return null;
        }
        $value = (string)preg_replace('@^[a-zA-Z]+://@', '', $value);
        $parts = explode(':', $value);
        $port = array_pop($parts);
        $host = trim(implode(':', $parts), '[]');
        if ($host === '' || in_array($host, ['0.0.0.0', '*', '::'], true)) {
            $host = '127.0.0.1';
        }
        if (!ctype_digit((string)$port)) {
            return null;
        }
        return sprintf('http://%s:%s', (str_contains($host, ':') ? '[' . $host . ']' : $host), $port);
    }

    /** 控制面板密钥（可能为空） */
    public static function secret(): string
    {
        return (string)(self::scan()['secret'] ?? '');
    }

    /** 上游随包分发的占位节点地址；一旦命中，说明用户还没换成真实节点。 */
    public static function hasPlaceholderProxies(): bool
    {
        return str_contains(self::rawText(), '88.88.88.88');
    }

    /**
     * 把 PHP 标量渲染为 YAML 标量。
     */
    public static function renderValue(mixed $value): string
    {
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }
        if (is_int($value) || is_float($value)) {
            return (string)$value;
        }
        $value = (string)$value;
        /* 已经是 YAML 流式集合（如 [443, 8443]）：原样输出，不能再加引号 */
        if (str_starts_with($value, '[') && str_ends_with($value, ']')) {
            return $value;
        }
        /* 需要引号的情形：空串 / 以特殊字符开头 / 含 ": " 或 " #" / 首尾空白 */
        if ($value === '' || preg_match('/^[\s#\[\]{}&*!|>\'"%@`]/', $value) || preg_match('/:\s|#\s|^\s|\s$/', $value)) {
            return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $value) . '"';
        }
        return $value;
    }

    /**
     * 域名嗅探（sniffer）对应的配置键。
     * 仅写 `enable: true` 不够 —— 嗅探端口表必须显式给出，否则域名类规则对路由流量不生效。
     */
    public static function snifferKeys(bool $enabled): array
    {
        if (!$enabled) {
            return ['sniffer.enable' => false];
        }
        return [
            'sniffer.enable' => true,
            'sniffer.parse-pure-ip' => true,
            'sniffer.force-dns-mapping' => true,
            'sniffer.override-destination' => true,
            'sniffer.sniff.HTTP.ports' => '[80, 8080-8880]',
            'sniffer.sniff.HTTP.override-destination' => true,
            'sniffer.sniff.TLS.ports' => '[443, 8443]',
            'sniffer.sniff.QUIC.ports' => '[443, 8443]',
        ];
    }

    /**
     * 该行是否为可参与结构判断的内容行。
     */
    private static function isContentLine(string $line): bool
    {
        $trimmed = trim($line);
        return $trimmed !== ''
            && $trimmed !== '-'
            && !preg_match('/^\s*#/', $line)
            && !preg_match('/^\s*-(\s|$)/', $line);
    }

    private static function lineIndent(string $line): int
    {
        preg_match('/^(\s*)/', $line, $m);
        return strlen($m[1] ?? '');
    }

    /** 在 [from,to) 中找出位于 indent 层级的 key 所在行 */
    private static function findKeyLine(array $lines, int $from, int $to, int $indent, string $key): ?int
    {
        for ($i = $from; $i < $to; $i++) {
            if (!self::isContentLine($lines[$i])) {
                continue;
            }
            if (self::lineIndent($lines[$i]) !== $indent) {
                continue;
            }
            if (preg_match('/^"?' . preg_quote($key, '/') . '"?\s*:/', trim($lines[$i]))) {
                return $i;
            }
        }
        return null;
    }

    /** 从 key 行之后，找出该块的终止行（下一个缩进 <= indent 的内容行） */
    private static function findBlockEnd(array $lines, int $keyLine, int $to, int $indent): int
    {
        for ($i = $keyLine + 1; $i < $to; $i++) {
            if (!self::isContentLine($lines[$i])) {
                continue;
            }
            if (self::lineIndent($lines[$i]) <= $indent) {
                return $i;
            }
        }
        return $to;
    }

    /** 块内子键的缩进（取块内首个内容行的缩进，缺省 indent+2） */
    private static function childIndent(array $lines, int $from, int $to, int $indent): int
    {
        for ($i = $from; $i < $to; $i++) {
            if (self::isContentLine($lines[$i])) {
                return self::lineIndent($lines[$i]);
            }
        }
        return $indent + 2;
    }

    private static function setPathInRange(array $lines, array $segments, string $rendered, int $from, int $to, int $indent): array
    {
        $key = array_shift($segments);
        $indentStr = str_repeat(' ', $indent);
        $lineNo = self::findKeyLine($lines, $from, $to, $indent, $key);

        if ($segments === []) {
            /* 叶子：替换或追加（改动时保留行尾注释） */
            if ($lineNo !== null) {
                $existing = $lines[$lineNo];
                $comment = '';
                $hashPos = strpos($existing, ' #');
                if ($hashPos !== false) {
                    $comment = substr($existing, $hashPos);
                }
                $lines[$lineNo] = $indentStr . $key . ': ' . $rendered . $comment;
            } else {
                array_splice($lines, $to, 0, [$indentStr . $key . ': ' . $rendered]);
            }
            return $lines;
        }

        /* 中间节点 */
        if ($lineNo === null) {
            /* 整块不存在：在范围末尾补出该子树 */
            $blockLines = [$indentStr . $key . ':'];
            $subIndent = $indent + 2;
            $lastIdx = count($segments) - 1;
            foreach ($segments as $depth => $segment) {
                if ($depth === $lastIdx) {
                    $blockLines[] = str_repeat(' ', $subIndent) . $segment . ': ' . $rendered;
                } else {
                    $blockLines[] = str_repeat(' ', $subIndent) . $segment . ':';
                    $subIndent += 2;
                }
            }
            array_splice($lines, $to, 0, $blockLines);
            return $lines;
        }

        $blockEnd = self::findBlockEnd($lines, $lineNo, $to, $indent);
        $subIndent = self::childIndent($lines, $lineNo + 1, $blockEnd, $indent);

        /* 若该行写成 `tun: {}` 或标量，无法安全下钻，改写为块形式 */
        $afterColon = trim((string)preg_replace('/^[^:]+:/', '', $lines[$lineNo]));
        if ($afterColon !== '') {
            $lines[$lineNo] = $indentStr . $key . ':';
        }

        return self::setPathInRange($lines, $segments, $rendered, $lineNo + 1, $blockEnd, $subIndent);
    }

    /**
     * 修改任意层级的标量键，path 形如 "log-level" / "tun.enable" / "dns.listen"。
     *
     * 两重「最小改动」保证：
     *   1) 目标值已与文件一致 → 该键**一个字节都不动**（保留原有的注释、引号风格与缩进）；
     *   2) 需要改动时，只替换该行的值，并保留行尾注释。
     * 不重排、不删除、不解析列表，最大限度保留用户手写内容。
     * 结果仍会交给 `mihomo -t` 校验，校验不过就不会落盘。
     */
    public static function patchKeys(string $content, array $values): string
    {
        $eol = str_contains($content, "\r\n") ? "\r\n" : "\n";
        $lines = preg_split("/\r\n|\n|\r/", $content) ?: [];
        $current = self::scanText($content);
        foreach ($values as $path => $value) {
            if (self::valuesEqual($current[$path] ?? null, $value)) {
                continue;
            }
            $segments = explode('.', (string)$path);
            $lines = self::setPathInRange($lines, $segments, self::renderValue($value), 0, count($lines), 0);
        }
        return implode($eol, $lines);
    }

    /** 目标值与文件中已有值是否等价（忽略引号与布尔写法差异） */
    public static function valuesEqual(mixed $current, mixed $wanted): bool
    {
        if ($current === null) {
            return false;
        }
        $normalize = function (mixed $value): string {
            if (is_bool($value)) {
                return $value ? 'true' : 'false';
            }
            return strtolower(trim((string)$value, " \t\"'"));
        };
        return $normalize($current) === $normalize($wanted);
    }

    /* =====================================================================
     * DNS 上游（nameserver / nameserver-policy）受管区块
     *
     * 这些键是列表/嵌套映射，不能用 patchKeys 的单行标量方式安全改写；
     * 因此用带标记的 YAML 子块，整块替换。区块位于 dns: 内部，缩进 2 格。
     * ===================================================================== */

    public const DNS_UPSTREAM_MARK_BEGIN = '# >>> os-mihomo:dns-upstream (managed, do not edit) >>>';
    public const DNS_UPSTREAM_MARK_END = '# <<< os-mihomo:dns-upstream <<<';

    /** 受管区块接管的 DNS 上游键；写入前先移除旧的，避免重复键 */
    private const DNS_UPSTREAM_KEYS = [
        'default-nameserver',
        'nameserver',
        'nameserver-policy',
        'proxy-server-nameserver',
        'proxy-server-nameserver-policy',
        'direct-nameserver',
        'direct-nameserver-follow-policy',
        'respect-rules',
        'fallback',
        'fallback-filter',
    ];

    /**
     * 读取当前 DNS 上游配置（供 WebUI 文本框显示）。
     *
     * 优先读受管区块；没有区块时，从现有 dns: 块里抽取上面列出的键。
     * 返回的是去掉 2 空格缩进的 YAML 片段（不含 dns: 这一行）。
     */
    public static function dnsUpstreamBlock(?string $content = null): string
    {
        $content = $content ?? self::rawText();
        $lines = preg_split("/\r\n|\n|\r/", $content) ?: [];
        [$start, $end] = self::dnsUpstreamMarkers($lines);
        if ($start !== null && $end !== null) {
            return self::dedentBlock(array_slice($lines, $start + 1, $end - $start - 1), 2);
        }

        $dnsLine = self::findKeyLine($lines, 0, count($lines), 0, 'dns');
        if ($dnsLine === null) {
            return '';
        }
        $dnsEnd = self::findBlockEnd($lines, $dnsLine, count($lines), 0);
        $ranges = [];
        foreach (self::DNS_UPSTREAM_KEYS as $key) {
            $line = self::findKeyLine($lines, $dnsLine + 1, $dnsEnd, 2, $key);
            if ($line === null) {
                continue;
            }
            $ranges[] = [$line, self::findBlockEnd($lines, $line, $dnsEnd, 2)];
        }
        usort($ranges, fn ($a, $b) => $a[0] <=> $b[0]);
        $block = [];
        foreach ($ranges as [$from, $to]) {
            if ($block !== []) {
                $block[] = '';
            }
            $block = array_merge($block, array_slice($lines, $from, $to - $from));
        }
        return self::dedentBlock($block, 2);
    }

    /**
     * 用 WebUI 里的 YAML 片段替换 DNS 上游受管区块。
     *
     * 片段为空 = 删除受管区块与旧的上游键（用户明确清空）。
     * 写入前会移除同名旧键，避免 YAML 重复键导致 mihomo 拒绝。
     */
    public static function applyDnsUpstreamBlock(string $content, string $fragment): string
    {
        $eol = str_contains($content, "\r\n") ? "\r\n" : "\n";
        $lines = preg_split("/\r\n|\n|\r/", $content) ?: [];
        if ($lines !== [] && end($lines) === '') {
            array_pop($lines);
        }
        $dnsLine = self::findKeyLine($lines, 0, count($lines), 0, 'dns');
        if ($dnsLine === null) {
            throw new \RuntimeException(gettext('The configuration file has no dns: block.'));
        }

        [$start, $end] = self::dnsUpstreamMarkers($lines);
        if ($start !== null || $end !== null) {
            if ($start === null || $end === null || $end < $start) {
                throw new \RuntimeException(gettext('The DNS upstream block in the configuration file is not closed.'));
            }
            array_splice($lines, $start, $end - $start + 1);
        }

        $fragmentLines = self::normalizeDnsFragment($fragment);

        /* 片段里出现的顶层键也要从旧 dns: 块里移除，避免重复 */
        $removeKeys = self::DNS_UPSTREAM_KEYS;
        foreach ($fragmentLines as $line) {
            if (preg_match('/^"?([A-Za-z0-9_-]+)"?\s*:/', $line, $m)) {
                $removeKeys[] = $m[1];
            }
        }
        $removeKeys = array_values(array_unique($removeKeys));

        $dnsLine = self::findKeyLine($lines, 0, count($lines), 0, 'dns');
        $dnsEnd = self::findBlockEnd($lines, $dnsLine, count($lines), 0);
        $remove = [];
        for ($i = $dnsLine + 1; $i < $dnsEnd;) {
            if (self::isContentLine($lines[$i]) && self::lineIndent($lines[$i]) === 2) {
                if (preg_match('/^"?([A-Za-z0-9_-]+)"?\s*:/', trim($lines[$i]), $m)
                    && in_array($m[1], $removeKeys, true)
                ) {
                    $blockEnd = self::findBlockEnd($lines, $i, $dnsEnd, 2);
                    for ($j = $i; $j < $blockEnd; $j++) {
                        $remove[$j] = true;
                    }
                    $i = $blockEnd;
                    continue;
                }
            }
            $i++;
        }
        if ($remove !== []) {
            $kept = [];
            foreach ($lines as $i => $line) {
                if (!isset($remove[$i])) {
                    $kept[] = $line;
                }
            }
            $lines = $kept;
        }

        if ($fragmentLines !== []) {
            $dnsLine = self::findKeyLine($lines, 0, count($lines), 0, 'dns');
            $dnsEnd = self::findBlockEnd($lines, $dnsLine, count($lines), 0);
            $block = ['  ' . self::DNS_UPSTREAM_MARK_BEGIN];
            foreach ($fragmentLines as $line) {
                $block[] = $line === '' ? '' : '  ' . $line;
            }
            $block[] = '  ' . self::DNS_UPSTREAM_MARK_END;
            array_splice($lines, $dnsEnd, 0, $block);
        }
        return implode($eol, $lines);
    }

    /** @return array{0:?int,1:?int} 受管区块起止行号 */
    private static function dnsUpstreamMarkers(array $lines): array
    {
        $start = $end = null;
        foreach ($lines as $i => $line) {
            $trim = trim($line);
            if ($trim === self::DNS_UPSTREAM_MARK_BEGIN && $start === null) {
                $start = $i;
            } elseif ($trim === self::DNS_UPSTREAM_MARK_END && $start !== null) {
                $end = $i;
                break;
            }
        }
        return [$start, $end];
    }

    /** 去掉固定缩进，返回 YAML 片段字符串 */
    private static function dedentBlock(array $lines, int $indent): string
    {
        $out = [];
        foreach ($lines as $line) {
            if (trim($line) === '') {
                $out[] = '';
                continue;
            }
            $remove = min($indent, strlen($line) - strlen(ltrim($line)));
            $out[] = substr($line, $remove);
        }
        return rtrim(implode("\n", $out));
    }

    /** 规整 WebUI 提交的 YAML 片段：去 CRLF、去外层缩进、拒绝制表符与 dns: 行 */
    private static function normalizeDnsFragment(string $fragment): array
    {
        $fragment = str_replace(["\r\n", "\r"], "\n", $fragment);
        $lines = explode("\n", $fragment);
        $out = [];
        foreach ($lines as $line) {
            if (str_contains($line, "\t")) {
                throw new \RuntimeException(gettext('DNS upstream YAML must use spaces, not tabs.'));
            }
            $trim = trim($line);
            if ($trim === self::DNS_UPSTREAM_MARK_BEGIN || $trim === self::DNS_UPSTREAM_MARK_END) {
                continue;
            }
            if (preg_match('/^\s*dns:\s*$/', $line)) {
                throw new \RuntimeException(gettext('Do not include the top-level dns: line in the DNS upstream box.'));
            }
            $out[] = rtrim($line);
        }
        while ($out !== [] && trim($out[0]) === '') {
            array_shift($out);
        }
        while ($out !== [] && trim(end($out)) === '') {
            array_pop($out);
        }
        if ($out === []) {
            return [];
        }
        $min = null;
        foreach ($out as $line) {
            if (trim($line) === '') {
                continue;
            }
            $indent = strlen($line) - strlen(ltrim($line));
            $min = $min === null ? $indent : min($min, $indent);
        }
        $min = $min ?? 0;
        foreach ($out as &$line) {
            if (trim($line) === '') {
                $line = '';
                continue;
            }
            $remove = min($min, strlen($line) - strlen(ltrim($line)));
            $line = substr($line, $remove);
        }
        unset($line);
        return $out;
    }

    /**
     * 「不修改」开关：从完整键表里挑出**用户交给插件**的键。
     *
     * 页面每一项前面都有一条「不修改」勾（默认勾上）：
     *   勾上   = 插件完全不碰这一项 —— 文件里原本怎么写就怎么用，也不会把已有键删掉；
     *   取消勾 = 这一项由页面负责写入。
     *
     * @param array $managed       yamlKey => ['value' => mixed, 'fields' => [字段 id...], 'label' => 显示名]
     * @param array $ownedFields   「不修改」没勾上的字段 id（= 允许写入）
     * @param array $current       文件里现在的值（Config::scan()），用于说明"没写但有差别"的项
     * @return array{0: array, 1: array, 2: array}  [要写的键表, 写了的显示名, 没写但有差别的显示名]
     */
    public static function selectManagedKeys(array $managed, array $ownedFields, array $current = []): array
    {
        $owned = array_flip(array_map('strval', $ownedFields));
        $write = [];
        $written = [];
        $skipped = [];
        foreach ($managed as $yamlKey => $info) {
            $mine = false;
            foreach ((array)$info['fields'] as $field) {
                if (isset($owned[$field])) {
                    $mine = true;
                    break;
                }
            }
            if ($mine) {
                $write[$yamlKey] = $info;
                $written[] = $info['label'];
                continue;
            }
            /* 不修改的项：只有"文件里现在和页面不一样"才值得提一句（否则本来就不用动） */
            if (array_key_exists($yamlKey, $current) && !self::valuesEqual($current[$yamlKey], $info['value'])) {
                $skipped[] = $info['label'];
            }
        }
        return [$write, array_values(array_unique($written)), array_values(array_unique($skipped))];
    }

    /** 键表里的显示名（去重） */
    private static function labels(array $managed): array
    {
        $labels = [];
        foreach ($managed as $info) {
            $labels[] = $info['label'];
        }
        return array_values(array_unique($labels));
    }

    /* =====================================================================
     * 设置页「不修改」开关：哪些项不给开关
     *
     *  · 插件自己的状态（开机自启、订阅凭据、自动更新）不是 config.yaml 里的键，
     *    "不修改"对它们没有意义（插件必须知道自己的状态）→ 不给开关，始终由插件维护；
     *  · 设备名与协议栈是写死的：防火墙规则里的接口名、FreeBSD 上验证过的协议栈，
     *    改了只会把网络搞坏 → 页面上只读，写配置时恒用下面的值。
     * ===================================================================== */

    /** 写死的项：页面字段 id => [YAML 键, 固定值] */
    public const FIXED_SETTINGS = [
        'mihomo.tun.device' => ['key' => 'tun.device', 'value' => 'tun_mihomo'],
        'mihomo.tun.stack' => ['key' => 'tun.stack', 'value' => 'gvisor'],
    ];

    /** 插件自己的状态字段：没有「不修改」开关，始终随「应用」同步 */
    public const PLUGIN_OWNED_FIELDS = [
        'mihomo.general.enabled',
        'mihomo.subscription.url',
        'mihomo.subscription.secret',
        'mihomo.subscription.updateEnabled',
        'mihomo.subscription.updateInterval',
    ];

    /** 设置页上不该出现「不修改」开关的字段（= 始终由插件写） */
    public static function fieldsWithoutSwitch(): array
    {
        return array_merge(array_keys(self::FIXED_SETTINGS), self::PLUGIN_OWNED_FIELDS);
    }

    /**
     * 页面提交的「允许写入」清单 + 始终由插件维护的项（后端兜底：前端漏传也不会漏写）。
     */
    public static function ownedFieldsWithDefaults(array $fromPage): array
    {
        $fields = [];
        foreach ($fromPage as $field) {
            $field = trim((string)$field);
            if ($field !== '' && !in_array($field, $fields, true)) {
                $fields[] = $field;
            }
        }
        foreach (self::fieldsWithoutSwitch() as $field) {
            if (!in_array($field, $fields, true)) {
                $fields[] = $field;
            }
        }
        return $fields;
    }

    /** 写死项的固定值（按 YAML 键取） */
    public static function fixedValue(string $yamlKey, string $default = ''): string
    {
        foreach (self::FIXED_SETTINGS as $info) {
            if ($info['key'] === $yamlKey) {
                return $info['value'];
            }
        }
        return $default;
    }

    /**
     * 生成一个仅 www 可读写的临时文件，供 configd（root）校验并接管写入。
     * 返回绝对路径，失败抛异常。
     */
    public static function createStagingFile(string $content): string
    {
        $path = tempnam('/tmp', 'mihomo-');
        if ($path === false) {
            throw new \RuntimeException(gettext('Unable to create a staging file in /tmp.'));
        }
        if (file_put_contents($path, $content) === false) {
            @unlink($path);
            throw new \RuntimeException(gettext('Unable to write the staging file.'));
        }
        chmod($path, 0600);
        return $path;
    }

    /** 校验临时文件路径确实是我们生成的 */
    public static function isStagingPath(string $path): bool
    {
        return (bool)preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $path);
    }

    /* =====================================================================
     * 路由策略（按接口/源分流）
     *
     * 设计：模型里只存「谁的流量（接口 + 源）」与「走哪个出口」；
     * 渲染成 mihomo 规则后写入 config.yaml 的受管区块（带标记、整块替换，
     * 其余内容逐字节保留）；受管区块同时写进订阅模板，避免订阅更新把它冲掉。
     * ===================================================================== */

    public const POLICY_MARK_BEGIN = '# >>> os-mihomo:policy-routing (managed, do not edit) >>>';
    public const POLICY_MARK_END = '# <<< os-mihomo:policy-routing <<<';

    /** 国外流量判定用的规则集（与随包模板里的规则保持一致） */
    private const POLICY_FOREIGN_RULESETS = ['geolocation-!cn', 'gfw'];

    /**
     * 把策略行渲染成 mihomo 规则字符串。
     *
     * @param array $rules      每项: enabled, interface, source, scope, target
     * @param array $ifSubnets  接口 => 网段（source 留空时用它），例如 ['lan' => '192.168.1.0/24']
     * @return string[]         mihomo 规则行（不含缩进与 '- '）
     */
    public static function renderPolicyRules(array $rules, array $ifSubnets = []): array
    {
        $rendered = [];
        foreach ($rules as $rule) {
            if (!$rule instanceof \Traversable && !is_array($rule)) {
                continue;
            }
            $get = fn (string $key): string => trim((string)($rule[$key] ?? ''));
            if ($get('enabled') === '0') {
                continue;
            }

            $source = $get('source');
            if ($source === '') {
                $source = trim((string)($ifSubnets[$get('interface')] ?? ''));
            }
            if ($source === '') {
                /* 没有源就没有规则：宁可少生成，也不要生成一条会误伤所有流量的规则 */
                continue;
            }

            $target = $get('target');
            $scope = $get('scope') !== '' ? $get('scope') : 'foreign';

            if ($scope === 'direct') {
                $rendered[] = sprintf('SRC-IP-CIDR,%s,DIRECT', $source);
                continue;
            }
            if ($target === '') {
                /* 未选出口就不生成，避免把流量交给一个不存在的组导致规则校验失败 */
                continue;
            }
            if ($scope === 'all') {
                $rendered[] = sprintf('SRC-IP-CIDR,%s,%s', $source, $target);
                continue;
            }
            /* scope = foreign：只把国外流量交给该出口，国内仍按原有规则直连 */
            foreach (self::POLICY_FOREIGN_RULESETS as $ruleset) {
                $rendered[] = sprintf(
                    'AND,((SRC-IP-CIDR,%s),(GEOSITE,%s)),%s',
                    $source,
                    $ruleset,
                    $target
                );
            }
        }
        return $rendered;
    }

    /**
     * 把受管区块写入/替换到 YAML 文本里（纯字符串操作，最小 diff）。
     *
     * 规则块插在 `rules:` 之后（作为最先匹配的规则）；已存在标记时整块替换；
     * 没有 `rules:` 时在文件末尾补一个。其它内容逐字节保留。
     */
    public static function applyPolicyBlock(string $content, array $ruleLines): string
    {
        $eol = str_contains($content, "\r\n") ? "\r\n" : "\n";
        $lines = preg_split("/\r\n|\n|\r/", $content) ?: [];
        if ($lines !== [] && end($lines) === '') {
            array_pop($lines);   // 末尾空行稍后统一补回
        }

        /* 找已存在的受管区块 */
        $start = $end = null;
        foreach ($lines as $i => $line) {
            if (trim($line) === self::POLICY_MARK_BEGIN) {
                $start = $i;
            } elseif ($start !== null && trim($line) === self::POLICY_MARK_END) {
                $end = $i;
                break;
            }
        }

        /* 决定块的缩进：优先沿用文件里「我们区块之外」的第一条规则；其次沿用区块自身的；最后两空格 */
        $indent = '  ';
        $fileIndent = null;
        $seenRules = false;
        $inBlock = false;
        foreach ($lines as $line) {
            if (trim($line) === self::POLICY_MARK_BEGIN) {
                $inBlock = true;
                continue;
            }
            if (trim($line) === self::POLICY_MARK_END) {
                $inBlock = false;
                continue;
            }
            if ($inBlock) {
                continue;
            }
            if (preg_match('/^rules:\s*$/', $line)) {
                $seenRules = true;
                continue;
            }
            if ($seenRules && preg_match('/^(\s+)-\s/', $line, $m)) {
                $fileIndent = $m[1];
                break;
            }
            if ($seenRules && preg_match('/^\S/', $line)) {
                break;
            }
        }
        if ($fileIndent !== null) {
            $indent = $fileIndent;
        } elseif ($start !== null && isset($lines[$start + 1]) && preg_match('/^(\s*)-/', $lines[$start + 1], $m)) {
            $indent = $m[1];
        }

        $block = [];
        if ($ruleLines !== []) {
            $block[] = $indent . self::POLICY_MARK_BEGIN;
            foreach ($ruleLines as $rule) {
                $block[] = $indent . '- ' . $rule;
            }
            $block[] = $indent . self::POLICY_MARK_END;
        }

        if ($start !== null && $end !== null) {
            array_splice($lines, $start, $end - $start + 1, $block);
        } elseif ($block !== []) {
            $inserted = false;
            foreach ($lines as $i => $line) {
                if (preg_match('/^rules:\s*$/', $line)) {
                    array_splice($lines, $i + 1, 0, $block);
                    $inserted = true;
                    break;
                }
            }
            if (!$inserted) {
                if ($lines !== [] && trim(end($lines)) !== '') {
                    $lines[] = '';
                }
                $lines[] = 'rules:';
                $lines = array_merge($lines, $block);
            }
        }

        return implode($eol, $lines) . $eol;
    }

    /**
     * 从 config.yaml 里取代理组名字（供下拉与校验用）。
     * 只做缩进扫描，不引入 YAML 解析器；两种常见写法都要认：
     *   块风格:  - name: 🇺🇸 United States
     *   flow 风格: - { name: '🇺🇸 United States', type: select, ... }
     */
    public static function policyTargets(?string $file = null): array
    {
        $lines = preg_split("/\r\n|\n|\r/", self::rawTextOf($file)) ?: [];
        $names = [];
        $inGroups = false;
        foreach ($lines as $line) {
            if (preg_match('/^proxy-groups:\s*$/', $line)) {
                $inGroups = true;
                continue;
            }
            if (!$inGroups) {
                continue;
            }
            if (preg_match('/^[a-zA-Z_-]/', $line)) {
                break;   // 进入下一个顶层键
            }
            if (!preg_match('/\bname:\s*(.+)$/', $line, $m)) {
                continue;
            }
            /* flow 风格里 name 之后还有其它字段，按 ", key:" 截断 */
            $value = preg_split('/,\s*[a-zA-Z_-]+:/', $m[1])[0];
            $value = trim(rtrim(trim($value), ','));
            $value = trim($value, " \t\"'");
            if ($value !== '') {
                $names[] = $value;
            }
        }
        return array_values(array_unique($names));
    }

    /** 读取任意文件内容（默认 config.yaml），失败返回空串 */
    private static function rawTextOf(?string $file = null): string
    {
        $path = $file ?? self::file();
        $text = @file_get_contents($path);
        return $text === false ? '' : $text;
    }

    /**
     * 某个接口的 IPv4 地址（自检时用它作为源地址，让流量命中该网段的规则）
     */
    public static function interfaceIp(string $ifname): string
    {
        try {
            $config = \OPNsense\Core\Config::getInstance()->object();
            if (isset($config->interfaces->$ifname)) {
                $ip = trim((string)$config->interfaces->$ifname->ipaddr);
                return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ? $ip : '';
            }
        } catch (\Throwable $e) {
            /* 取不到就当没有 */
        }
        return '';
    }

    /**
     * OPNsense 已配置接口 => 网段 映射（如 ['lan' => '192.168.1.0/24']）。
     * 依赖框架的 Core\Config；仅在 WebGUI 上下文中调用。
     */
    public static function interfaceSubnets(): array
    {
        $result = [];
        try {
            $config = \OPNsense\Core\Config::getInstance()->object();
        } catch (\Throwable $e) {
            return $result;
        }
        if (!isset($config->interfaces)) {
            return $result;
        }
        foreach ($config->interfaces->children() as $name => $node) {
            $ip = trim((string)$node->ipaddr);
            $mask = trim((string)$node->subnet);
            if ($ip === '' || $mask === '' || !ctype_digit($mask)) {
                continue;
            }
            $long = ip2long($ip);
            if ($long === false) {
                continue;
            }
            $bits = (int)$mask;
            $netmask = $bits === 0 ? 0 : (-1 << (32 - $bits));
            $result[$name] = long2ip($long & $netmask) . '/' . $bits;
        }
        return $result;
    }
}
