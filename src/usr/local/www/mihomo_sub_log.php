<?php

/*
 * os-mihomo —— 兼容旧入口（订阅日志）
 * 302 到 /ui/mihomo/subscription
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 */

$target = '/ui/mihomo/subscription';

session_start();
if (empty($_SESSION['Username'])) {
    header('Location: /?url=' . rawurlencode($target));
    exit;
}

header('Location: ' . $target, true, 302);
exit;
