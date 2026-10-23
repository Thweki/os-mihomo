#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 路由策略落盘器（由 configd 以 root 身份调用）
 *
 * 用法:
 *   policy_apply.php apply <staging-json-file>
 *
 * staging JSON（由 WebGUI 侧生成，0600 于 /tmp/mihomo-XXXXXX）:
 *   {"rules": ["AND,((SRC-IP-CIDR,192.0.2.0/24),(GEOSITE,geolocation-!cn)),GROUP", ...]}
 *
 * 行为:
 *   1. 把「受管区块」写入 config.yaml 与 sub/template_config.yaml（带标记，整块替换、幂等）
 *      —— 同时写模板是因为订阅更新会用模板重新生成 config.yaml，否则规则会被冲掉；
 *   2. 落盘前用 `mihomo -t` 校验新的 config.yaml，不通过整体放弃（原文件保持不动）；
 *   3. 两个文件都先做时间戳备份，再原子替换，只保留最近 N 份；
 *   4. stdout 输出 JSON（configd 只把 stdout 回传给调用方）：
 *      {"status":"ok","messages":[...],"diff":"..."}
 *
 * 退出码: 0 成功 / 1 校验失败 / 2 参数或环境错误 / 3 写入失败
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部 BSD 许可条款。
 */

$CONFIG_FILE = '/usr/local/etc/mihomo/config.yaml';
$TEMPLATE_FILE = '/usr/local/etc/mihomo/sub/template_config.yaml';
$CONFIG_DIR = '/usr/local/etc/mihomo';
$MIHOMO_BIN = '/usr/local/bin/mihomo';
$BACKUP_KEEP = 20;
$MODEL_CONFIG = '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php';

require_once $MODEL_CONFIG;

function out(array $data): void
{
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
}

function fail(string $message, int $code): void
{
    /* configd 只回传 stdout，因此错误必须同时打到 stdout */
    out(['status' => 'failed', 'message' => $message]);
    fwrite(STDERR, $message . "\n");
    exit($code);
}

function run_command(string $command): array
{
    $output = [];
    $rc = 0;
    exec($command . ' 2>&1', $output, $rc);
    return [$rc, implode("\n", $output)];
}

function validate_config(string $file, string $dir): array
{
    global $MIHOMO_BIN;
    [$rc, $output] = run_command(sprintf(
        '%s -t -d %s -f %s',
        escapeshellarg($MIHOMO_BIN),
        escapeshellarg($dir),
        escapeshellarg($file)
    ));
    return [$rc === 0, trim($output)];
}

/** 简易逐行差异（只给 WebUI 看，不追求 patch 精度） */
function diff_text(string $before, string $after, string $label): string
{
    $a = preg_split("/\r\n|\n|\r/", $before) ?: [];
    $b = preg_split("/\r\n|\n|\r/", $after) ?: [];
    $lines = [];
    $max = max(count($a), count($b));
    $shown = 0;
    for ($i = 0; $i < $max; $i++) {
        $left = $a[$i] ?? null;
        $right = $b[$i] ?? null;
        if ($left === $right) {
            continue;
        }
        if ($shown < 40) {
            $no = $i + 1;
            if ($left !== null && !in_array($left, $b, true)) {
                $lines[] = sprintf('%-4d - %s', $no, $left);
            }
            if ($right !== null && !in_array($right, $a, true)) {
                $lines[] = sprintf('%-4d + %s', $no, $right);
            }
            $shown++;
        } elseif ($shown === 40) {
            $lines[] = '...';
            $shown++;
        }
    }
    if ($lines === []) {
        return '';
    }
    return $label . ":\n" . implode("\n", $lines);
}

function trim_backups(string $file, int $keep): void
{
    $backups = glob($file . '.bak.*') ?: [];
    sort($backups);
    while (count($backups) > $keep) {
        $old = array_shift($backups);
        @unlink($old);
    }
}

/* ---------------------------------------------------------------------- */

$action = $argv[1] ?? '';
$staging = $argv[2] ?? '';
$rules = [];

if (!is_file($MIHOMO_BIN)) {
    fail('mihomo binary is missing: ' . $MIHOMO_BIN, 2);
}
if ($action !== 'apply') {
    fail('usage: policy_apply.php apply <staging-file>', 2);
}
if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $staging) || !is_file($staging)) {
    fail('invalid staging file: ' . $staging, 2);
}

$payload = json_decode((string)file_get_contents($staging), true);
if (!is_array($payload) || !isset($payload['rules']) || !is_array($payload['rules'])) {
    fail('invalid staging payload (expects {"rules": [...]})', 2);
}
foreach ($payload['rules'] as $raw) {
    $rule = trim((string)$raw);
    if ($rule === '') {
        continue;
    }
    if (preg_match('/[\x00-\x1f]/', $rule)) {
        fail('rule contains control characters, refusing to write', 2);
    }
    $rules[] = $rule;
}

$messages = [];
$diffs = [];
$targets = [
    ['file' => $CONFIG_FILE, 'required' => true],
    ['file' => $TEMPLATE_FILE, 'required' => false],
];

foreach ($targets as $target) {
    $file = $target['file'];
    if (!is_file($file)) {
        if ($target['required']) {
            fail('configuration file not found: ' . $file, 2);
        }
        continue;
    }

    $before = (string)file_get_contents($file);
    $after = \OPNsense\Mihomo\Config::applyPolicyBlock($before, $rules);

    if ($after === $before) {
        $messages[] = sprintf('%s: already up to date', basename($file));
        continue;
    }

    $tmp = $file . '.policy-new';
    if (file_put_contents($tmp, $after) === false) {
        fail('unable to write ' . $tmp, 3);
    }
    chmod($tmp, 0644);

    if ($target['required']) {
        [$ok, $output] = validate_config($tmp, $CONFIG_DIR);
        if (!$ok) {
            @unlink($tmp);
            fail("mihomo rejected the new configuration:\n" . $output, 1);
        }
        $messages[] = 'mihomo -t: OK';
    }

    $backup = $file . '.bak.' . date('Ymd_His');
    if (!copy($file, $backup)) {
        @unlink($tmp);
        fail('unable to create backup ' . $backup, 3);
    }
    chmod($backup, 0600);
    chown($backup, 'root');
    chgrp($backup, 'wheel');

    if (!rename($tmp, $file)) {
        @unlink($tmp);
        fail('unable to install ' . $file, 3);
    }
    chmod($file, 0644);
    chown($file, 'root');
    chgrp($file, 'wheel');

    $messages[] = sprintf('%s: updated (%d rules, backup %s)', basename($file), count($rules), basename($backup));
    $diff = diff_text($before, $after, basename($file));
    if ($diff !== '') {
        $diffs[] = $diff;
    }
    trim_backups($file, $BACKUP_KEEP);
}

@unlink($staging);

out([
    'status' => 'ok',
    'messages' => $messages,
    'diff' => implode("\n\n", $diffs),
]);
