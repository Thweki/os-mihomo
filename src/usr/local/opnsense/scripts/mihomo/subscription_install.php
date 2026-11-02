#!/usr/local/bin/php
<?php
/* CLI-only bridge used by sub.sh. It shares the WebUI writer and lock. */
require_once __DIR__ . '/write_common.php';

use OPNsense\Mihomo\ActionResult;
use OPNsense\Mihomo\WriteCoordinator;

try {
    $action = $argv[1] ?? '';
    if ($action === 'snapshot') {
        $paths = array_slice($argv, 2);
        if (count($paths) !== 3) {
            throw new RuntimeException('Invalid subscription snapshot');
        }
        $writer = new WriteCoordinator(dirname($paths[0]) . '/.write.lock');
        echo json_encode(WriteCoordinator::revisions($paths), JSON_UNESCAPED_SLASHES) . "\n";
        exit(0);
    }
    if ($action !== 'install' || count($argv) !== 9) {
        throw new RuntimeException('Invalid subscription install request');
    }
    [, , $candidate, $formal, $dir, $binary, $baseline, $service, $template] = $argv;
    if (is_link($candidate) || !is_file($candidate) || is_link($baseline) || !is_file($baseline)) {
        throw new RuntimeException('Invalid subscription staging files');
    }
    $expected = json_decode((string)file_get_contents($baseline), true);
    if (!is_array($expected) || !isset($expected[$formal], $expected[$template])) {
        throw new RuntimeException('Missing subscription baseline');
    }
    $writer = new WriteCoordinator(dirname($formal) . '/.write.lock');
    $before = is_file($formal) ? file_get_contents($formal) : null;
    $content = file_get_contents($candidate);
    if ($before === false || $content === false || $content === '') {
        throw new RuntimeException('Unable to read subscription configuration');
    }
    $result = $writer->commit([$formal => $content], $expected, function (array $staged) use ($formal, $dir, $binary): void {
        if (isset($staged[$formal])) {
            mihomo_validate($staged[$formal], $dir, $binary);
        }
    });
    if ($result['status'] !== 'ok') {
        ActionResult::emit($result);
        exit(1);
    }
    // A restart is requested only by the existing trusted CLI environment/runner.
    // Retain the write lock through restart and rollback so another writer cannot intervene.
    $output = [];
    $code = 0;
    $null = PHP_OS_FAMILY === 'Windows' ? 'NUL' : '/dev/null';
    exec($service . ' >' . $null . ' 2>&1', $output, $code);
    if ($code !== 0) {
        $restored = $before === null ? @unlink($formal)
            : $writer->commit([$formal => $before])['status'] === 'ok';
        $recovery = 1;
        if ($restored && $before !== null) {
            exec($service . ' >' . $null . ' 2>&1', $output, $recovery);
        }
        $result = ActionResult::make($restored ? 'failed' : 'partial', !$restored,
            $restored ? 'restart_failed_rolled_back' : 'rollback_failed',
            $restored ? 'Service restart failed; the previous configuration was restored.' : 'Service restart and configuration recovery failed.',
            ['service_recovered' => $recovery === 0, 'backups' => $result['backups'] ?? []]);
        ActionResult::emit($result);
        exit(1);
    }
    ActionResult::emit($result);
    exit(0);
} catch (Throwable $error) {
    ActionResult::emit(ActionResult::make('failed', false, 'subscription_failed', $error->getMessage()));
    exit(1);
}
