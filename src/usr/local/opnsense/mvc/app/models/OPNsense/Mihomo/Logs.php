<?php

/*
 * os-mihomo 二次开发 —— 日志（统一经 configd 读取 root 拥有的日志文件）
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

use OPNsense\Core\Backend;

class Logs
{
    public const KEYS = ['mihomo', 'subscription'];

    public static function tail(string $key, int $lines = 200): string
    {
        if (!in_array($key, self::KEYS, true)) {
            return '';
        }
        return self::redact(rtrim((new Backend())->configdpRun('mihomo log-tail', [$key, $lines]), "\n"));
    }

    /** Defense in depth for historical logs, validator output and converter failures. */
    public static function redact(string $text): string
    {
        $text = preg_replace('~https?://[^\s<>]+~iu', '[URL redacted]', $text) ?? '';
        $text = preg_replace('/(?im)((?:secret|password|token|authorization|密钥)\s*[:=：]\s*)[^\r\n]+/u', '$1[redacted]', $text) ?? '';
        return $text;
    }

    public static function clear(string $key): string
    {
        if (!in_array($key, self::KEYS, true)) {
            return '';
        }
        return trim((new Backend())->configdpRun('mihomo log-clear', [$key]));
    }
}
