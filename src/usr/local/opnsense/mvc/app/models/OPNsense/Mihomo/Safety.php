<?php

/*
 * os-mihomo 二次开发 —— 安全体检
 *
 * 目标：在用户点击「启动」之前，把可能造成整网故障的因素显式亮出来。
 * 本类只做只读判断，不修改任何系统状态。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

use OPNsense\Core\Backend;

class Safety
{
    public const LEVEL_DANGER = 'danger';
    public const LEVEL_WARNING = 'warning';
    public const LEVEL_INFO = 'info';

    /**
     * @return array{status: string, items: array<int, array{level: string, title: string, detail: string}>}
     */
    public static function report(bool $validateConfig = false): array
    {
        $items = [];

        if (!Config::exists()) {
            $items[] = [
                'level' => self::LEVEL_DANGER,
                'title' => gettext('Configuration file is missing'),
                'detail' => sprintf(
                    gettext('%s does not exist, the service cannot start.'),
                    Config::FILE
                ),
            ];
            return ['status' => 'danger', 'items' => $items];
        }

        /* --- 1. TUN 自动接管默认路由 --- */
        $tunEnabled = Config::bool('tun.enable');
        $autoRoute = Config::bool('tun.auto-route');
        $strictRoute = Config::bool('tun.strict-route');
        if ($tunEnabled && $autoRoute) {
            $items[] = [
                'level' => self::LEVEL_DANGER,
                'title' => gettext('TUN with automatic route takeover is enabled'),
                'detail' => gettext(
                    'Starting the service will insert routes for all IPv4 traffic into the TUN device. ' .
                    'If the proxy nodes are not reachable or not configured, every device behind this ' .
                    'firewall loses Internet access.'
                ),
            ];
        } elseif ($tunEnabled) {
            $items[] = [
                'level' => self::LEVEL_INFO,
                'title' => gettext('TUN mode is enabled (automatic route takeover off)'),
                'detail' => gettext(
                    'Traffic only enters the TUN device when firewall or policy routing sends it there.'
                ),
            ];
        }
        if ($strictRoute) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('Strict route is enabled'),
                'detail' => gettext(
                    'The TUN device is guaranteed to win over other default routes while the service runs.'
                ),
            ];
        }

        /* --- 2. 仍是随包分发的占位节点 --- */
        if (Config::hasPlaceholderProxies()) {
            $items[] = [
                'level' => self::LEVEL_DANGER,
                'title' => gettext('Placeholder proxy nodes detected'),
                'detail' => gettext(
                    'The configuration still contains the placeholder server 88.88.88.88 shipped with the ' .
                    'plugin. Replace it with a real subscription or real proxy nodes before starting the service.'
                ),
            ];
        }

        /* --- 3. 控制器对外暴露 --- */
        $bind = trim((string)(Config::scan()['external-controller'] ?? ''));
        $host = strstr($bind, ':', true);
        if ($host === '' || $host === false) {
            $host = '127.0.0.1';
        }
        if (!in_array($host, ['127.0.0.1', '::1', '[::1]', 'localhost'], true)) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('External controller is reachable from the network'),
                'detail' => sprintf(
                    gettext(
                        'external-controller is bound to %s. Anyone who can reach that address and knows the ' .
                        'secret can reconfigure the proxy. Bind it to 127.0.0.1 — this WebGUI talks to the ' .
                        'controller over the loopback interface only.'
                    ),
                    $bind
                ),
            ];
        }

        /* --- 4. 空 secret --- */
        if (Config::secret() === '') {
            $items[] = [
                'level' => self::LEVEL_DANGER,
                'title' => gettext('External controller has no secret'),
                'detail' => gettext('Set a secret in the configuration, otherwise the API is unauthenticated.'),
            ];
        }

        /* --- 5. DNS 劫持 --- */
        if ($tunEnabled && Config::rawText() !== '' && preg_match('/dns-hijack:/', Config::rawText()) === 1) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('DNS hijacking is configured'),
                'detail' => gettext(
                    'DNS queries on port 53 are redirected into mihomo while the service runs. If the proxy ' .
                    'is broken, name resolution for all clients behind this firewall breaks with it.'
                ),
            ];
        }

        /* --- 6. 服务状态与自启开关 --- */
        $backend = new Backend();
        $running = str_contains((string)$backend->configdRun('mihomo status'), 'is running');
        $enabled = self::bootEnabled();
        if ($running && $enabled) {
            $items[] = [
                'level' => self::LEVEL_INFO,
                'title' => gettext('Service is running and enabled at boot'),
                'detail' => gettext('mihomo is active and will start again after a reboot.'),
            ];
        } elseif (!$running && $enabled) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('Service is enabled at boot but not running'),
                'detail' => gettext(
                    'On the next reboot mihomo will take over routing as soon as it starts. Verify the ' .
                    'configuration before you reboot.'
                ),
            ];
        }

        /* --- 7. 配置语法校验（可选，较慢） --- */
        if ($validateConfig) {
            $output = trim((string)$backend->configdRun('mihomo config-current'));
            $valid = !str_contains($output, 'invalid') && !str_contains($output, 'error');
            $items[] = [
                'level' => $valid ? self::LEVEL_INFO : self::LEVEL_DANGER,
                'title' => $valid
                    ? gettext('Configuration syntax is valid')
                    : gettext('Configuration syntax is invalid'),
                'detail' => $output === '' ? gettext('No output from the configuration test.') : $output,
            ];
        }

        $status = self::LEVEL_INFO;
        foreach ($items as $item) {
            if ($item['level'] === self::LEVEL_DANGER) {
                $status = self::LEVEL_DANGER;
                break;
            } elseif ($item['level'] === self::LEVEL_WARNING) {
                $status = self::LEVEL_WARNING;
            }
        }

        return ['status' => $status, 'items' => $items];
    }

    /** 读取 /etc/rc.conf.d/mihomo 中的自启开关 */
    public static function bootEnabled(): bool
    {
        $file = '/etc/rc.conf.d/mihomo';
        if (!is_readable($file)) {
            return false;
        }
        return (bool)preg_match('/^\s*mihomo_enable\s*=\s*"?YES"?/mi', (string)file_get_contents($file));
    }
}
