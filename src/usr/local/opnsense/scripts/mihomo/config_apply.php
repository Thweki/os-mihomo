#!/usr/local/bin/php
<?php

/*
 * os-mihomo —— 配置文件落盘器（由 configd 以 root 身份调用）
 *
 * 用法:
 *   config_apply.php check   <staging-file>    仅校验，不落盘
 *   config_apply.php install <staging-file>    校验 -> 备份 -> 原子安装
 *   config_apply.php current                   校验当前 config.yaml
 *
 * staging 文件由 php-fpm(www) 生成于 /tmp/mihomo-XXXXXX（0600），
 * 本脚本会严格校验其路径与属主/权限，防止被替换。
 *
 * 退出码: 0 成功 / 1 校验失败 / 2 参数或环境错误 / 3 写入失败
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 Config.php 头部 BSD 许可条款。
 */

$CONFIG_FILE = '/usr/local/etc/mihomo/config.yaml';
$CONFIG_DIR = '/usr/local/etc/mihomo';
$MIHOMO_BIN = '/usr/local/bin/mihomo';
$BACKUP_KEEP = 20;

function fail(string $message, int $code): void
{
    /* configd 只把 stdout 回传给调用方（stderr 只进 syslog），
       因此错误必须同时打到 stdout，否则 WebUI 只会看到“(no output)”。 */
    echo 'ERROR: ' . $message . "\n";
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

/**
 * 校验一个配置文件。返回 [bool ok, string output]
 */
function validate_config(string $file, string $dir): array
{
    global $MIHOMO_BIN;
    [$rc, $out] = run_command(sprintf(
        '%s -t -d %s -f %s',
        escapeshellarg($MIHOMO_BIN),
        escapeshellarg($dir),
        escapeshellarg($file)
    ));
    return [$rc === 0, trim($out)];
}

$action = $argv[1] ?? '';
$target = $argv[2] ?? '';

if (!is_file($MIHOMO_BIN)) {
    fail('mihomo binary is missing: ' . $MIHOMO_BIN, 2);
}

switch ($action) {
    case 'current':
        if (!is_file($CONFIG_FILE)) {
            fail('configuration file not found: ' . $CONFIG_FILE, 2);
        }
        [$ok, $out] = validate_config($CONFIG_FILE, $CONFIG_DIR);
        echo $out === '' ? ($ok ? "Configuration is valid.\n" : "Configuration is invalid.\n") : $out . "\n";
        exit($ok ? 0 : 1);

    case 'restore':
        /* 从时间戳备份还原：先校验备份，再备份当前文件，最后原子安装 */
        if (!preg_match('@^' . preg_quote($CONFIG_DIR, '@') . '/config\.yaml\.bak\.[0-9_]+$@', $target)) {
            fail('invalid backup path', 2);
        }
        if (!is_file($target) || is_link($target)) {
            fail('backup file is not a regular file', 2);
        }
        $tmp = tempnam('/tmp', 'mihomo-');
        if ($tmp === false || !@copy($target, $tmp)) {
            fail('unable to stage the backup for validation', 3);
        }
        chmod($tmp, 0600);
        [$ok, $out] = validate_config($tmp, $CONFIG_DIR);
        if (!$ok) {
            @unlink($tmp);
            echo "Backup validation failed:\n" . $out . "\n";
            exit(1);
        }
        $backup = $CONFIG_FILE . '.bak.' . date('Ymd_His');
        if (is_file($CONFIG_FILE) && !@copy($CONFIG_FILE, $backup)) {
            @unlink($tmp);
            fail('unable to create a backup of the current configuration', 3);
        }
        chmod($backup, 0644);
        [$rc, $out2] = run_command(sprintf(
            '/usr/bin/install -m 0644 -o root -g wheel %s %s',
            escapeshellarg($tmp),
            escapeshellarg($CONFIG_FILE)
        ));
        @unlink($tmp);
        if ($rc !== 0) {
            echo "Failed to install the configuration file:\n" . $out2 . "\n";
            exit(3);
        }
        echo sprintf(
            "Restored from %s.\nPrevious file kept as %s.\n%s\n",
            basename($target),
            basename($backup),
            $out
        );
        exit(0);

    case 'check':
    case 'install':
        /* ---- 输入校验：必须是 www 在 /tmp 下生成的临时文件 ---- */
        if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $target)) {
            fail('invalid staging path', 2);
        }
        if (!is_file($target) || is_link($target)) {
            fail('staging file is not a regular file', 2);
        }
        $stat = stat($target);
        if ($stat === false || $stat['size'] === 0) {
            fail('staging file is empty', 2);
        }
        /* 说明：本机 WebGUI 的 php-cgi 以 root 运行，因此属主就是 root，
           不能据此判断来源；真正的护栏是「随机文件名 + 0600 + 非符号链接 + 内容校验」。 */
        if (((int)$stat['mode'] & 0777) !== 0600) {
            fail('staging file has unexpected permissions', 2);
        }

        [$ok, $out] = validate_config($target, $CONFIG_DIR);
        if (!$ok) {
            @unlink($target);
            echo "Configuration validation failed:\n" . $out . "\n";
            exit(1);
        }

        if ($action === 'check') {
            @unlink($target);
            echo "Configuration validation passed.\n" . $out . "\n";
            exit(0);
        }

        /* ---- 备份 ---- */
        if (is_file($CONFIG_FILE)) {
            $backup = $CONFIG_FILE . '.bak.' . date('Ymd_His');
            if (!@copy($CONFIG_FILE, $backup)) {
                @unlink($target);
                fail('unable to create a backup of the current configuration', 3);
            }
            chmod($backup, 0644);
            /* 只保留最近若干份备份，避免占满 /usr/local */
            $backups = glob($CONFIG_FILE . '.bak.*') ?: [];
            sort($backups);
            foreach (array_slice($backups, 0, max(0, count($backups) - $BACKUP_KEEP)) as $old) {
                @unlink($old);
            }
        }

        /* ---- 原子安装 ---- */
        [$rc, $out2] = run_command(sprintf(
            '/usr/bin/install -m 0644 -o root -g wheel %s %s',
            escapeshellarg($target),
            escapeshellarg($CONFIG_FILE)
        ));
        @unlink($target);
        if ($rc !== 0) {
            echo "Failed to install the configuration file:\n" . $out2 . "\n";
            exit(3);
        }

        echo "Configuration installed successfully.\n" . $out . "\n";
        exit(0);

    default:
        fail('usage: config_apply.php {check|install|current} [staging-file]', 2);
}
