<?php

/*
 * os-mihomo 二次开发 —— mihomo external controller REST 客户端
 *
 * 仅由服务端（php-fpm）通过 loopback 访问 127.0.0.1:<port>，
 * 浏览器永远不直接接触该端口。所有请求 2~5 秒超时，服务未运行时优雅降级。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class Controller
{
    /** 默认测速地址（mihomo 官方推荐） */
    public const DEFAULT_TEST_URL = 'https://www.gstatic.com/generate_204';

    private const CONNECT_TIMEOUT = 2;
    private const REQUEST_TIMEOUT = 5;

    /**
     * 发起一次 REST 调用。
     *
     * @return array{ok: bool, code: int, data: mixed, error: string, raw: string}
     */
    public static function request(
        string $method,
        string $path,
        ?array $body = null,
        float $timeout = self::REQUEST_TIMEOUT
    ): array {
        $base = Config::controllerBase();
        if ($base === null) {
            return [
                'ok' => false,
                'code' => 0,
                'data' => null,
                'error' => gettext('External controller is not configured in the mihomo configuration file.'),
                'raw' => '',
            ];
        }

        $headers = ['Content-Type: application/json'];
        $secret = Config::secret();
        if ($secret !== '') {
            $headers[] = 'Authorization: Bearer ' . $secret;
        }

        $ch = curl_init($base . $path);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => strtoupper($method),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => self::CONNECT_TIMEOUT,
            CURLOPT_TIMEOUT => (int)ceil($timeout),
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_FOLLOWLOCATION => false,
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        }

        $raw = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);

        if ($raw === false) {
            return [
                'ok' => false,
                'code' => 0,
                'data' => null,
                'error' => $error !== '' ? $error : gettext('Unable to reach the mihomo external controller.'),
                'raw' => '',
            ];
        }

        $decoded = null;
        if ($raw !== '') {
            $decoded = json_decode($raw, true);
        }

        $ok = $code >= 200 && $code < 300;
        return [
            'ok' => $ok,
            'code' => $code,
            'data' => $decoded,
            'error' => $ok ? '' : sprintf(gettext('Controller responded with HTTP code %s.'), $code),
            'raw' => (string)$raw,
        ];
    }

    public static function get(string $path, float $timeout = self::REQUEST_TIMEOUT): array
    {
        return self::request('GET', $path, null, $timeout);
    }

    public static function put(string $path, array $body = []): array
    {
        return self::request('PUT', $path, $body);
    }

    public static function patch(string $path, array $body = []): array
    {
        return self::request('PATCH', $path, $body);
    }

    public static function delete(string $path): array
    {
        return self::request('DELETE', $path);
    }

    /** 控制器是否可达（用于状态横幅） */
    public static function isAlive(): bool
    {
        $result = self::get('/version', 2);
        return $result['ok'];
    }

    /** mihomo 版本信息 */
    public static function version(): ?array
    {
        $result = self::get('/version', 2);
        return $result['ok'] ? $result['data'] : null;
    }

    /** 运行中的配置（mode / log-level / ports …） */
    public static function runningConfig(): ?array
    {
        $result = self::get('/configs', 3);
        return $result['ok'] ? $result['data'] : null;
    }

    /**
     * 代理列表，整理成「组 + 成员」结构，附带最近一次延迟。
     *
     * @return array{groups: array, ready: bool, error: string}
     */
    public static function proxyGroups(): array
    {
        $result = self::get('/proxies', 5);
        if (!$result['ok'] || !is_array($result['data']['proxies'] ?? null)) {
            return ['groups' => [], 'ready' => false, 'error' => $result['error']];
        }

        $proxies = $result['data']['proxies'];
        $groups = [];
        foreach ($proxies as $name => $node) {
            if (empty($node['all'])) {
                continue;   /* 非分组节点 */
            }
            $members = [];
            foreach ($node['all'] as $member) {
                $memberNode = $proxies[$member] ?? [];
                $delay = null;
                foreach (array_reverse($memberNode['history'] ?? []) as $hist) {
                    if (isset($hist['delay'])) {
                        $delay = (int)$hist['delay'];
                        break;
                    }
                }
                $members[] = [
                    'name' => $member,
                    'type' => (string)($memberNode['type'] ?? ''),
                    'delay' => $delay,
                    'selected' => ($member === ($node['now'] ?? null)),
                    'alive' => $delay !== null && $delay > 0,
                ];
            }
            $groups[] = [
                'name' => (string)$name,
                'type' => (string)($node['type'] ?? ''),
                'now' => (string)($node['now'] ?? ''),
                'members' => $members,
            ];
        }
        usort($groups, fn ($a, $b) => strcmp($a['name'], $b['name']));
        return ['groups' => $groups, 'ready' => true, 'error' => ''];
    }

    /** 选择分组内的节点 */
    public static function selectProxy(string $group, string $member): array
    {
        return self::put('/proxies/' . rawurlencode($group), ['name' => $member]);
    }

    /** 单节点延迟测速（毫秒；0/负数表示失败） */
    public static function testDelay(string $name, string $url = self::DEFAULT_TEST_URL, int $timeoutMs = 5000): array
    {
        $query = http_build_query(['timeout' => $timeoutMs, 'url' => $url]);
        $result = self::get('/proxies/' . rawurlencode($name) . '/delay?' . $query, 10);
        if (!$result['ok'] || !isset($result['data']['delay'])) {
            return ['ok' => false, 'delay' => -1, 'error' => $result['error'] ?: (string)($result['data']['message'] ?? '')];
        }
        return ['ok' => true, 'delay' => (int)$result['data']['delay'], 'error' => ''];
    }

    /** 运行态摘要：流量累计 / 连接数 / 内存 */
    public static function snapshot(): array
    {
        $result = self::get('/connections', 5);
        if (!$result['ok'] || !is_array($result['data'])) {
            return ['ready' => false, 'error' => $result['error'], 'connections' => []];
        }
        $data = $result['data'];
        return [
            'ready' => true,
            'error' => '',
            'downloadTotal' => (int)($data['downloadTotal'] ?? 0),
            'uploadTotal' => (int)($data['uploadTotal'] ?? 0),
            'memory' => (int)($data['memory'] ?? 0),
            'connections' => is_array($data['connections'] ?? null) ? $data['connections'] : [],
        ];
    }

    /**
     * 连接列表 → 前端表格行（含流量格式化所需的原始字节数）。
     * 处理 mihomo 的 metadata 字段差异（host / destinationIP / sniffHost）。
     */
    public static function connectionRows(): array
    {
        $snapshot = self::snapshot();
        if (!$snapshot['ready']) {
            return $snapshot + ['rows' => []];
        }
        $rows = [];
        foreach ($snapshot['connections'] as $conn) {
            $meta = $conn['metadata'] ?? [];
            $host = (string)($meta['host'] ?? '');
            if ($host === '') {
                $host = (string)($meta['destinationIP'] ?? ($meta['sniffHost'] ?? ''));
            }
            $chains = $conn['chains'] ?? [];
            $rows[] = [
                'id' => (string)($conn['id'] ?? ''),
                'host' => $host,
                'source' => (string)($meta['sourceIP'] ?? '') . (isset($meta['sourcePort']) ? ':' . $meta['sourcePort'] : ''),
                'destination' => (string)($meta['destinationIP'] ?? '') . (isset($meta['destinationPort']) ? ':' . $meta['destinationPort'] : ''),
                'network' => strtoupper((string)($meta['network'] ?? '')),
                'type' => strtoupper((string)($meta['type'] ?? '')),
                'rule' => (string)($conn['rule'] ?? ''),
                'rulePayload' => (string)($conn['rulePayload'] ?? ''),
                'chain' => implode(' → ', array_reverse($chains)),
                'outbound' => (string)(end($chains) ?: ''),
                'download' => (int)($conn['download'] ?? 0),
                'upload' => (int)($conn['upload'] ?? 0),
                'start' => (string)($conn['start'] ?? ''),
            ];
        }
        return $snapshot + ['rows' => $rows];
    }

    /** 关闭单条连接（id 为空时关闭全部） */
    public static function closeConnection(string $id = ''): array
    {
        return self::delete('/connections' . ($id !== '' ? '/' . rawurlencode($id) : ''));
    }

    /** 切换运行模式 */
    public static function setMode(string $mode): array
    {
        if (!in_array($mode, ['rule', 'global', 'direct'], true)) {
            return ['ok' => false, 'error' => gettext('Invalid mode.'), 'code' => 0, 'data' => null, 'raw' => ''];
        }
        return self::patch('/configs', ['mode' => $mode]);
    }

    /** 运行期修改日志等级（等价于编辑 config.yaml 后的 PATCH） */
    public static function setLogLevel(string $level): array
    {
        if (!in_array($level, ['debug', 'info', 'warning', 'error', 'silent'], true)) {
            return ['ok' => false, 'error' => gettext('Invalid log level.'), 'code' => 0, 'data' => null, 'raw' => ''];
        }
        return self::patch('/configs', ['log-level' => $level]);
    }
}
