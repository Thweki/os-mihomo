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
                    'Starting the service will insert routes for all IPv4 traffic into the TUN device. If the proxy nodes are not reachable or not configured, every device behind this firewall loses Internet access.'
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
                    'The configuration still contains the placeholder server 88.88.88.88 shipped with the plugin. Replace it with a real subscription or real proxy nodes before starting the service.'
                ),
            ];
        }

        /* --- 3. 控制器可达性与密钥 ---
         * 只监听回环时不设密钥并不危险（网络侧访问不到），因此不再一律报 danger。 */
        $bind = trim((string)(Config::scan()['external-controller'] ?? ''));
        $host = strstr($bind, ':', true);
        if ($host === '' || $host === false) {
            $host = '127.0.0.1';
        }
        $loopbackOnly = in_array($host, ['127.0.0.1', '::1', '[::1]', 'localhost'], true);
        if (!$loopbackOnly) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('External controller is reachable from the network'),
                'detail' => sprintf(
                    gettext(
                        'external-controller is bound to %s. Anyone who can reach that address and knows the secret can reconfigure the proxy. Bind it to 127.0.0.1 — this WebGUI talks to the controller over the loopback interface only.'
                    ),
                    $bind
                ),
            ];
        }
        if (Config::secret() === '') {
            if ($loopbackOnly) {
                $items[] = [
                    'level' => self::LEVEL_INFO,
                    'title' => gettext('External controller has no secret (loopback only)'),
                    'detail' => gettext(
                        'The controller listens on 127.0.0.1, so it cannot be reached from the network. A secret is only needed when you bind the controller to a network address.'
                    ),
                ];
            } else {
                $items[] = [
                    'level' => self::LEVEL_DANGER,
                    'title' => gettext('External controller is exposed without a secret'),
                    'detail' => gettext(
                        'The controller is reachable from the network and has no secret, so anyone who can reach it may reconfigure the proxy. Set a secret or bind it to 127.0.0.1.'
                    ),
                ];
            }
        }

        /* --- 4b. IPv6：TUN 设备只有 IPv4 地址，v6 流量会绕过代理 --- */
        if ($tunEnabled && Inspector::ipv6Allowed(Config::rawText())) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('IPv6 traffic bypasses the proxy'),
                'detail' => gettext(
                    'The TUN device only carries IPv4, so IPv6 traffic leaves this firewall without going through mihomo. Set ipv6: false in the configuration to stop that, or add IPv6 handling separately.'
                ),
            ];
        }

        /* --- 5. DNS 劫持 --- */
        if ($tunEnabled && Config::rawText() !== '' && preg_match('/dns-hijack:/', Config::rawText()) === 1) {
            $items[] = [
                'level' => self::LEVEL_WARNING,
                'title' => gettext('DNS hijacking is configured'),
                'detail' => gettext(
                    'DNS queries on port 53 are redirected into mihomo while the service runs. If the proxy is broken, name resolution for all clients behind this firewall breaks with it.'
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
                    'On the next reboot mihomo will take over routing as soon as it starts. Verify the configuration before you reboot.'
                ),
            ];
        }

        /* --- 7. 策略路由：服务停止时被路由的接口会断网 --- */
        try {
            $cfg = \OPNsense\Core\Config::getInstance()->object();
            $routed = [];
            if (isset($cfg->filter->rule)) {
                foreach ($cfg->filter->rule as $rule) {
                    if (
                        (string)$rule->gateway === 'MIHOMO_TUN'
                        && stripos((string)$rule->descr, 'Mihomo policy routing') !== false
                    ) {
                        $iface = (string)$rule->interface;
                        $descr = (string)($cfg->interfaces->$iface->descr ?? '');
                        $routed[] = $descr !== '' ? sprintf('%s (%s)', $descr, $iface) : $iface;
                    }
                }
            }
            if ($routed !== []) {
                $items[] = [
                    'level' => self::LEVEL_WARNING,
                    'title' => gettext('Policy routing is active'),
                    'detail' => sprintf(
                        gettext(
                            'Traffic from these interfaces is routed into the mihomo TUN device: %s. While the service is stopped or fails to start, clients on these interfaces lose Internet access.'
                        ),
                        implode(', ', array_unique($routed))
                    ),
                ];
            }
        } catch (\Throwable $e) {
            /* 只读判断失败不影响体检 */
        }

        /* --- 8. 配置语法校验（可选，较慢） --- */
        if ($validateConfig) {
            $output = trim((string)$backend->configdRun('mihomo config-current'));
            $valid = !str_contains($output, 'invalid') && !str_contains($output, 'error');
            $items[] = [
                'level' => $valid ? self::LEVEL_INFO : self::LEVEL_DANGER,
                'title' => $valid
                    ? gettext('Configuration syntax is valid')
                    : gettext('Configuration syntax is invalid'),
                'detail' => self::shorten(
                    $output === '' ? gettext('No output from the configuration test.') : $output
                ),
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

    /**
     * 校验器输出的最后若干行（mihomo -t 会打印一长串 geodata 加载日志）。
     */
    public static function shorten(string $text, int $lines = 8): string
    {
        $all = preg_split('/\r\n|\n|\r/', $text) ?: [];
        $all = array_values(array_filter($all, fn ($line) => trim($line) !== ''));
        if (count($all) <= $lines) {
            return implode("\n", $all);
        }
        return implode("\n", array_slice($all, -$lines));
    }
}
