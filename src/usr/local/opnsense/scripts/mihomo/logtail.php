<?php

/*
 * os-mihomo —— 日志读取器（由 configd 以 root 身份调用）
 *
 * 用法: logtail.php <mihomo|subscription> [行数]
 *
 * /var/log/mihomo.log 与 /var/log/mihomo_sub.log 均为 0640 root:wheel，
 * php-fpm 的 www 用户无法直读，因此统一经 configd 取回。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 Config.php 头部 BSD 许可条款。
 */

const LOG_MAP = [
    'mihomo' => '/var/log/mihomo.log',
    'subscription' => '/var/log/mihomo_sub.log',
];

const MAX_BYTES = 262144;

$key = $argv[1] ?? '';
$lines = isset($argv[2]) ? (int)$argv[2] : 200;
$lines = max(1, min($lines, 5000));

if (!array_key_exists($key, LOG_MAP)) {
    fwrite(STDERR, "unknown log key: {$key}\n");
    exit(2);
}

$file = LOG_MAP[$key];
if (!is_file($file) || !is_readable($file)) {
    exit(0);   /* 无日志时安静地返回空 */
}

$size = filesize($file);
if ($size === false || $size <= 0) {
    exit(0);
}

$readSize = min($size, MAX_BYTES);
$fp = @fopen($file, 'rb');
if ($fp === false) {
    fwrite(STDERR, "unable to open {$file}\n");
    exit(3);
}
fseek($fp, -$readSize, SEEK_END);
$content = (string)fread($fp, $readSize);
fclose($fp);

$all = preg_split("/\r\n|\n|\r/", $content);
if ($size > $readSize && !empty($all)) {
    array_shift($all);   /* 首行可能被截断，丢弃 */
}
$tail = array_slice($all, -$lines);
echo implode("\n", $tail);
if ($tail !== []) {
    echo "\n";
}
