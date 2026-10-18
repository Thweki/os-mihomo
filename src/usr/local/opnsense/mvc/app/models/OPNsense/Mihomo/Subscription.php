<?php

/*
 * os-mihomo 二次开发 —— 订阅（env 文件 / 执行 / 日志）
 *
 * 上游把订阅地址与访问密钥存放在 /usr/local/etc/mihomo/sub/env（0600 root:wheel），
 * 但旧 WebUI 以 www 身份直接读写该文件，实际必然失败。这里统一改走 configd。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

use OPNsense\Core\Backend;

class Subscription
{
    public const ENV_FILE = '/usr/local/etc/mihomo/sub/env';
    public const LOG_KEY = 'subscription';

    /** 读取 env 文件中的所有变量（经 configd） */
    public static function env(): array
    {
        $raw = trim((new Backend())->configdRun('mihomo env-get'));
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }

    /**
     * 写入订阅地址与访问密钥。
     * 空字符串表示清除该项（保留键但不赋值）。
     */
    public static function saveEnv(string $url, string $secret): string
    {
        return (new Backend())->configdpRun('mihomo env-set', [$url, $secret]);
    }

    /**
     * 触发订阅更新。
     *
     * @param bool $restart 更新成功后是否重启 mihomo（默认 false，见 subscription_run.sh 注释）
     */
    public static function run(bool $restart = false): string
    {
        return (new Backend())->configdpRun('mihomo sub-run', [$restart ? 'yes' : 'no']);
    }

    public static function log(int $lines = 300): string
    {
        return Logs::tail(self::LOG_KEY, $lines);
    }

    public static function clearLog(): string
    {
        return Logs::clear(self::LOG_KEY);
    }
}
