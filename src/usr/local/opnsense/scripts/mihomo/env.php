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

require_once __DIR__ . '/write_common.php';
use OPNsense\Mihomo\WriteCoordinator;

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
            mihomo_fail('invalid_url', 'Subscription URL must start with http:// or https://');
        }
        if ($secret !== '' && !preg_match('/^[0-9a-zA-Z_.\-]{0,128}$/', $secret)) {
            mihomo_fail('invalid_secret', 'Access secret contains unsupported characters');
        }

        $dir = dirname($ENV_FILE);
        if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
            mihomo_fail('write_failed', 'Unable to create the subscription directory');
        }

        try {
            $writer = new WriteCoordinator();
        } catch (Throwable $error) {
            mihomo_fail('busy', $error->getMessage());
        }
        $vars = read_env($ENV_FILE);
        $vars['mihomo_URL'] = $url;
        $vars['mihomo_secret'] = $secret;

        $lines = [];
        foreach ($vars as $key => $value) {
            $lines[] = sprintf("%s='%s'", $key, escape_env_value((string)$value));
        }

        $expected = isset($argv[4]) ? [$ENV_FILE => $argv[4]] : [];
        mihomo_result($writer->commit([$ENV_FILE => implode("\n", $lines) . "\n"], $expected));

    default:
        mihomo_fail('invalid_action', 'Unsupported subscription settings action');
}
