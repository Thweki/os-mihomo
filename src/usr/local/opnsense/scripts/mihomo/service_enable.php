#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 开机自启开关（由 configd 以 root 身份调用）
 *
 * 用法: service_enable.php <yes|no>
 *
 * 写 /etc/rc.conf.d/mihomo（FreeBSD rcvar: mihomo_enable）。
 * 默认 NO —— 避免机器重启后在未经确认的情况下接管路由。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 Config.php 头部 BSD 许可条款。
 */

require_once __DIR__ . '/write_common.php';
use OPNsense\Mihomo\WriteCoordinator;

$value = strtolower(trim($argv[1] ?? ''));
if (!in_array($value, ['yes', 'no'], true)) {
    mihomo_fail('invalid_value', 'Autostart must be yes or no');
}

$file = '/etc/rc.conf.d/mihomo';
$content = sprintf("mihomo_enable=\"%s\"\n", strtoupper($value));

try {
    $writer = new WriteCoordinator();
    mihomo_result($writer->commit([$file => $content]));
} catch (Throwable $error) {
    mihomo_fail('write_failed', $error->getMessage());
}
