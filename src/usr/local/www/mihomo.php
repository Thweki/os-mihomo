<?php

/*
 * os-mihomo —— 兼容旧入口
 *
 * 上游 1.0.4 的 WebUI 是本目录下的过程式页面；二次开发后全部改为
 * OPNsense 原生 MVC（/ui/mihomo/*）。此文件仅做 302 跳转，
 * 不再渲染任何内容，也不再直接执行系统命令。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 */

$target = '/ui/mihomo';

session_start();
if (empty($_SESSION['Username'])) {
    /* 未登录：回到登录页，并带上原始目标 */
    header('Location: /?url=' . rawurlencode($target));
    exit;
}

header('Location: ' . $target, true, 302);
exit;
