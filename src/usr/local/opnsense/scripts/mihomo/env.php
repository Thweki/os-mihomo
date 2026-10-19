#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 订阅 env 文件读写器（由 configd 以 root 身份调用）
 *
 * 用法:
 *   env.php get                    输出 JSON 形式的环境变量
 *   env.php set <url> <secret>     原子写入 mihomo_URL / mihomo_secret
 *
 * 文件格式与上游一致：KEY='value'（单引号包裹，内部 ' 以 '"'"' 转义）。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 Config.php 头部 BSD 许可条款。
 */

$ENV_FILE = '/usr/local/etc/mihomo/sub/env';

function read_env(string $file): array
{
    $vars = [];
    if (!is_file($file)) {
        return $vars;
    }
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (preg_match("/^(?:export\s+)?([A-Za-z0-9_]+)='(.*)'$/", $line, $m)) {
            $vars[$m[1]] = str_replace("'\"'\"'", "'", $m[2]);
        }
    }
    return $vars;
}

function escape_env_value(string $value): string
{
    return str_replace("'", "'\"'\"'", $value);
}

$action = $argv[1] ?? '';

switch ($action) {
    case 'get':
        echo json_encode(read_env($ENV_FILE), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        exit(0);

    case 'set':
        $url = trim($argv[2] ?? '');
        $secret = trim($argv[3] ?? '');

        if ($url !== '' && !preg_match('@^https?://\S+$@i', $url)) {
            fwrite(STDERR, "subscription URL must start with http:// or https://\n");
            exit(2);
        }
        if ($secret !== '' && !preg_match('/^[0-9a-zA-Z_.\-]{0,128}$/', $secret)) {
            fwrite(STDERR, "access secret contains unsupported characters\n");
            exit(2);
        }

        $dir = dirname($ENV_FILE);
        if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
            fwrite(STDERR, "unable to create {$dir}\n");
            exit(3);
        }

        $vars = read_env($ENV_FILE);
        if (($vars['mihomo_URL'] ?? null) === $url && ($vars['mihomo_secret'] ?? null) === $secret) {
            /* 值没变：不写文件，也不打印（否则每次「应用」都会刷一句"已保存"） */
            exit(0);
        }
        $vars['mihomo_URL'] = $url;
        $vars['mihomo_secret'] = $secret;

        $lines = [];
        foreach ($vars as $key => $value) {
            $lines[] = sprintf("%s='%s'", $key, escape_env_value((string)$value));
        }

        $tmp = $ENV_FILE . '.tmp';
        if (@file_put_contents($tmp, implode("\n", $lines) . "\n") === false) {
            fwrite(STDERR, "unable to write {$tmp}\n");
            exit(3);
        }
        chmod($tmp, 0600);
        chown($tmp, 'root');
        chgrp($tmp, 'wheel');
        if (!@rename($tmp, $ENV_FILE)) {
            @unlink($tmp);
            fwrite(STDERR, "unable to replace {$ENV_FILE}\n");
            exit(3);
        }
        chmod($ENV_FILE, 0600);

        echo "Subscription settings saved.\n";
        exit(0);

    default:
        fwrite(STDERR, "usage: env.php {get|set <url> <secret>}\n");
        exit(2);
}
