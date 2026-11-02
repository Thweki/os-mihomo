#!/usr/local/bin/php
<?php
/* Validated writes, restores and multi-file settings commits via one coordinator. */
require_once __DIR__ . '/write_common.php';

use OPNsense\Mihomo\ActionResult;
use OPNsense\Mihomo\WriteCoordinator;

$config = '/usr/local/etc/mihomo/config.yaml';
$dir = dirname($config);
$action = $argv[1] ?? '';
$target = $argv[2] ?? '';
$cleanup = null;
try {
    if ($action === 'current') {
        $writer = new WriteCoordinator();
        mihomo_validate($config, $dir);
        mihomo_result(ActionResult::make('unchanged', false, 'valid', 'Configuration validation passed.'));
    }
    if ($action === 'restore') {
        if (!preg_match('@^' . preg_quote($config, '@') . '\.bak\.[A-Za-z0-9_]+$@', $target)
            || !is_file($target) || is_link($target)) {
            throw new RuntimeException('Invalid backup path');
        }
        $content = file_get_contents($target);
        if ($content === false) {
            throw new RuntimeException('Unable to read the backup');
        }
        $files = [$config => $content];
        $expected = isset($argv[3]) ? [$config => $argv[3]] : [];
    } elseif (in_array($action, ['check', 'install', 'install-bundle'], true)) {
        $content = mihomo_staging($target);
        $cleanup = $target;
        if ($action === 'check') {
            mihomo_validate($target, $dir);
            @unlink($target);
            mihomo_result(ActionResult::make('unchanged', false, 'valid', 'Configuration validation passed.'));
        }
        if ($action === 'install-bundle') {
            $payload = json_decode($content, true);
            if (!is_array($payload) || !is_array($payload['files'] ?? null) || !is_array($payload['expected'] ?? null)) {
                throw new RuntimeException('Invalid configuration bundle');
            }
            $files = $payload['files'];
            $expected = $payload['expected'];
            $allowed = [$config, $dir . '/sub/template_config.yaml', $dir . '/sub/env', '/etc/rc.conf.d/mihomo'];
            if (array_diff(array_keys($files), $allowed) || array_diff(array_keys($expected), array_merge($allowed, ['/conf/config.xml']))) {
                throw new RuntimeException('Unsupported configuration bundle target');
            }
            foreach ($files as $path => $value) {
                if (!is_string($value) || !isset($expected[$path])) {
                    throw new RuntimeException('Every bundle target requires content and a baseline revision');
                }
            }
        } else {
            $files = [$config => $content];
            $expected = isset($argv[3]) ? [$config => $argv[3]] : [];
        }
    } else {
        throw new RuntimeException('Unsupported configuration action');
    }
    $writer = new WriteCoordinator();
    $result = $writer->commit($files, $expected, function (array $staged) use ($config, $dir): void {
        if (isset($staged[$config])) {
            mihomo_validate($staged[$config], $dir);
        }
    });
    if ($cleanup !== null) {
        @unlink($cleanup);
    }
    mihomo_result($result);
} catch (Throwable $error) {
    if ($cleanup !== null) {
        @unlink($cleanup);
    }
    mihomo_fail('configuration_failed', $error->getMessage());
}
