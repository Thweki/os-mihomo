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
        /* 需要引号的情形：空串 / 以特殊字符开头 / 含 ": " 或 " #" / 首尾空白 */
        if ($value === '' || preg_match('/^[\s#\[\]{}&*!|>\'"%@`]/', $value) || preg_match('/:\s|#\s|^\s|\s$/', $value)) {
            return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $value) . '"';
        }
        return $value;
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
}
