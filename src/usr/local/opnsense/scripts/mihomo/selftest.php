#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 绑定自检（由 configd 以 root 身份调用）
 *
 * 用法:
 *   selftest.php run <staging-json>
 *
 * staging JSON（WebGUI 侧按模型算出）:
 *   {"tests":[{"interface":"lan","source":"192.168.1.0/24","src_ip":"192.168.1.1","target":"🇺🇸 United States"}]}
 *
 * 做法（只做临时改动，测完立刻还原）:
 *   1. 解析一个国外探针与一个国内探针；
 *   2. 对每个绑定接口：临时加一条「主机路由把探针送进 TUN」，
 *      再用 --interface <接口 IP> 发起请求（这样 mihomo 看到的源地址就在被绑网段内，
 *      会命中该行的 SRC-IP-CIDR 规则）；
 *   3. 从 /var/log/mihomo.log 的新增行里解析出「命中的规则 + 使用的代理组」；
 *   4. 删除临时主机路由（无论成败）。
 *
 * stdout 输出 JSON: {"status":"ok","results":[{...}]}
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部 BSD 许可条款。
 */

$CONFIG_FILE = '/usr/local/etc/mihomo/config.yaml';
$LOG_FILE = '/var/log/mihomo.log';
$DEVICE = 'tun_mihomo';
$FOREIGN_URL = 'https://api.ipify.org';
$FOREIGN_FALLBACK = 'https://1.1.1.1/cdn-cgi/trace';
$DOMESTIC_URL = 'https://www.baidu.com';
$TIMEOUT = 25;

function out(array $data): void
{
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
}

function fail(string $message, int $code): void
{
    out(['status' => 'failed', 'message' => $message]);
    fwrite(STDERR, $message . "\n");
    exit($code);
}

function run(string $command): array
{
    $output = [];
    $rc = 0;
    exec($command . ' 2>&1', $output, $rc);
    return [$rc, implode("\n", $output)];
}

function resolve(string $host): string
{
    [$rc, $ip] = run('host -W 3 -t a ' . escapeshellarg($host) . ' 127.0.0.1');
    if ($rc === 0 && preg_match('/has address (\d+\.\d+\.\d+\.\d+)/', $ip, $m)) {
        return $m[1];
    }
    /* 退回系统解析器 */
    $ip = gethostbyname($host);
    return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ? $ip : '';
}

/** 从日志新增部分解析命中的规则与代理组（needles 任一命中即可） */
function parse_match(string $log, array $needles): array
{
    $rule = '';
    $group = '';
    foreach (preg_split("/\r\n|\n|\r/", $log) ?: [] as $line) {
        if (!str_contains($line, 'match')) {
            continue;
        }
        $hit = false;
        foreach ($needles as $needle) {
            if ($needle !== '' && str_contains($line, $needle)) {
                $hit = true;
                break;
            }
        }
        if (!$hit) {
            continue;
        }
        if (preg_match('/match (.+?) using (.+?)("[^"]*"?\s*$|\s+\[)/u', $line, $m)) {
            $rule = trim(rtrim(trim($m[1]), '"'));
            $group = trim(rtrim(trim($m[2]), '"'));
        }
    }
    return [$rule, $group];
}

/** 发起一次探针请求，返回 [ok, 摘要/出口IP] */
function probe(string $url, string $srcIp, string $pinIp, int $timeout): array
{
    $args = '--silent --show-error --max-time ' . $timeout . ' --interface ' . escapeshellarg($srcIp);
    if ($pinIp !== '') {
        $host = parse_url($url, PHP_URL_HOST);
        $args .= ' --resolve ' . escapeshellarg($host . ':443:' . $pinIp);
    }
    [$rc, $body] = run('curl ' . $args . ' ' . escapeshellarg($url));
    $body = trim($body);
    if ($rc !== 0) {
        return [false, $body === '' ? 'curl exit ' . $rc : $body];
    }
    if (str_contains($url, 'cdn-cgi/trace')) {
        if (preg_match('/^ip=(.+)$/m', $body, $m)) {
            return [true, trim($m[1])];
        }
        return [false, 'unexpected trace output'];
    }
    return [true, $body];
}

/* ---------------------------------------------------------------------- */

$action = $argv[1] ?? '';
$staging = $argv[2] ?? '';

if ($action !== 'run') {
    fail('usage: selftest.php run <staging-json>', 2);
}
if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $staging) || !is_file($staging)) {
    fail('invalid staging file: ' . $staging, 2);
}
$payload = json_decode((string)file_get_contents($staging), true);
if (!is_array($payload) || !is_array($payload['tests'] ?? null)) {
    fail('invalid staging payload (expects {"tests":[...]})', 2);
}
if (!is_file($CONFIG_FILE)) {
    fail('missing ' . $CONFIG_FILE, 2);
}

/* 服务/TUN 是否就绪 */
[$rcTun, $tunOut] = run('ifconfig ' . escapeshellarg($DEVICE));
$tunUp = ($rcTun === 0);
[$rcSvc, $svcOut] = run('service mihomo status');
$serviceUp = str_contains($svcOut, 'is running');

$foreignIp = resolve('api.ipify.org');
$domesticIp = resolve('www.baidu.com');
$useFallback = ($foreignIp === '');

$results = [];
foreach ($payload['tests'] as $test) {
    $iface = trim((string)($test['interface'] ?? ''));
    $source = trim((string)($test['source'] ?? ''));
    $srcIp = trim((string)($test['src_ip'] ?? ''));
    $target = trim((string)($test['target'] ?? ''));
    $row = [
        'interface' => $iface,
        'source' => $source,
        'expected_group' => $target,
        'ok' => false,
        'note' => '',
        'foreign_ip' => '',
        'foreign_rule' => '',
        'foreign_group' => '',
        'domestic_rule' => '',
    ];

    if (!$serviceUp || !$tunUp) {
        $row['note'] = 'service or TUN not running';
        $results[] = $row;
        continue;
    }
    if ($srcIp === '' || !filter_var($srcIp, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        $row['note'] = 'interface has no IPv4 address';
        $results[] = $row;
        continue;
    }

    /* --- 国外探针 --- */
    $logOffset = is_file($LOG_FILE) ? (int)filesize($LOG_FILE) : 0;
    $routeAdded = false;
    $probeIp = $useFallback ? '1.1.1.1' : $foreignIp;
    $url = $useFallback ? $FOREIGN_FALLBACK : $FOREIGN_URL;
    [$rcAdd, $addOut] = run('route add -host ' . escapeshellarg($probeIp) . ' -interface ' . escapeshellarg($DEVICE));
    $routeAdded = ($rcAdd === 0);
    if ($routeAdded) {
        [$ok, $value] = probe($url, $srcIp, $useFallback ? '1.1.1.1' : $foreignIp, $TIMEOUT);
        if ($ok) {
            $row['foreign_ip'] = $value;
        } else {
            $row['note'] = 'probe failed: ' . $value;
        }
    } else {
        $row['note'] = trim($addOut);
    }

    /* --- 日志里的命中规则 --- */
    if (is_file($LOG_FILE)) {
        $fp = fopen($LOG_FILE, 'r');
        if ($fp) {
            if ($logOffset > 0 && $logOffset < (int)filesize($LOG_FILE)) {
                fseek($fp, $logOffset);
            } elseif (filesize($LOG_FILE) < $logOffset) {
                $logOffset = 0;
            }
            $newLog = (string)stream_get_contents($fp);
            fclose($fp);
            [$rule, $group] = parse_match($newLog, [$probeIp, 'api.ipify.org']);
            $row['foreign_rule'] = $rule;
            $row['foreign_group'] = $group;
        }
    }

    /* --- 国内探针（验证「仅国外」范围） --- */
    if ($domesticIp !== '') {
        $logOffset2 = is_file($LOG_FILE) ? (int)filesize($LOG_FILE) : 0;
        [$rcAdd2] = run('route add -host ' . escapeshellarg($domesticIp) . ' -interface ' . escapeshellarg($DEVICE));
        if ($rcAdd2 === 0) {
            probe($DOMESTIC_URL, $srcIp, $domesticIp, $TIMEOUT);
            run('route delete -host ' . escapeshellarg($domesticIp));
            if (is_file($LOG_FILE)) {
                $fp = fopen($LOG_FILE, 'r');
                if ($fp) {
                    if ($logOffset2 > 0 && $logOffset2 < (int)filesize($LOG_FILE)) {
                        fseek($fp, $logOffset2);
                    }
                    $newLog2 = (string)stream_get_contents($fp);
                    fclose($fp);
                    [$rule2] = parse_match($newLog2, [$domesticIp, 'www.baidu.com']);
                    $row['domestic_rule'] = $rule2;
                }
            }
        }
    }

    if ($routeAdded) {
        run('route delete -host ' . escapeshellarg($probeIp));
    }

    $row['ok'] = ($row['foreign_ip'] !== '');
    $results[] = $row;
}

@unlink($staging);

out([
    'status' => 'ok',
    'service_running' => $serviceUp,
    'tun_up' => $tunUp,
    'probe' => [
        'foreign' => $useFallback ? '1.1.1.1 (fallback)' : ($foreignIp !== '' ? 'api.ipify.org' : 'unresolved'),
        'domestic' => $domesticIp !== '' ? 'www.baidu.com' : '',
    ],
    'results' => $results,
]);
