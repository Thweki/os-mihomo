<?php

/*
 * os-mihomo —— 日志清空器（由 configd 以 root 身份调用）
 *
 * 用法: logclear.php <mihomo|subscription>
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 Config.php 头部 BSD 许可条款。
 */

const LOG_MAP = [
    'mihomo' => '/var/log/mihomo.log',
    'subscription' => '/var/log/mihomo_sub.log',
];

$key = $argv[1] ?? '';
if (!array_key_exists($key, LOG_MAP)) {
    fwrite(STDERR, "unknown log key: {$key}\n");
    exit(2);
}

$file = LOG_MAP[$key];
if (!is_file($file)) {
    echo "Log file does not exist; nothing to clear.\n";
    exit(0);
}

if (file_put_contents($file, '', LOCK_EX) === false) {
    fwrite(STDERR, "unable to truncate {$file}\n");
    exit(3);
}
chmod($file, 0640);
echo "Log file cleared.\n";
