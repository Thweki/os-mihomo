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

$value = strtolower(trim($argv[1] ?? ''));
if (!in_array($value, ['yes', 'no'], true)) {
    fwrite(STDERR, "usage: service_enable.php <yes|no>\n");
    exit(2);
}

$file = '/etc/rc.conf.d/mihomo';
$content = sprintf("mihomo_enable=\"%s\"\n", strtoupper($value));

if (@file_put_contents($file, $content) === false) {
    fwrite(STDERR, "unable to write {$file}\n");
    exit(3);
}
chmod($file, 0644);
chown($file, 'root');
chgrp($file, 'wheel');

echo sprintf("mihomo boot-time autostart set to %s.\n", strtoupper($value));
