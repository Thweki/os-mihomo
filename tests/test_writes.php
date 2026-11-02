<?php
/* Isolated behavioral tests. All targets live in a fresh temporary directory. */
require_once dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/WriteCoordinator.php';

use OPNsense\Mihomo\ActionResult;
use OPNsense\Mihomo\WriteCoordinator;

if (($argv[1] ?? '') === '--lock-child') {
    try {
        $writer = new WriteCoordinator($argv[2], 0.15);
        exit(2);
    } catch (RuntimeException $error) {
        exit(0);
    }
}

$root = sys_get_temp_dir() . '/mihomo-write-test-' . bin2hex(random_bytes(8));
mkdir($root, 0700);
$failures = 0;
function checkWrite(string $label, bool $ok): void
{
    global $failures;
    echo ($ok ? 'PASS ' : 'FAIL ') . $label . "\n";
    $failures += $ok ? 0 : 1;
}
function runFixture(array $command, ?array $environment = null): array
{
    $process = proc_open($command, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, $environment);
    if (!is_resource($process)) {
        throw new RuntimeException('Unable to start test subprocess');
    }
    fclose($pipes[0]);
    $out = stream_get_contents($pipes[1]);
    $err = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    return [proc_close($process), $out, $err];
}
function removeFixture(string $dir): void
{
    foreach (scandir($dir) ?: [] as $name) {
        if ($name === '.' || $name === '..') { continue; }
        $path = $dir . '/' . $name;
        if (is_dir($path) && !is_link($path)) { removeFixture($path); } else { unlink($path); }
    }
    rmdir($dir);
}

try {
    $config = $root . '/config.yaml';
    $template = $root . '/template.yaml';
    $old = "secret: fixture-old\nmode: rule\n";
    file_put_contents($config, $old);
    file_put_contents($template, 'template-old');
    file_put_contents($config . '.bak.legacy', 'historical-private-content');
    chmod($config . '.bak.legacy', 0644);
    $lock = $root . '/.write.lock';
    $writer = new WriteCoordinator($lock);
    $baseline = WriteCoordinator::revisions([$config, $template]);
    $result = $writer->commit([$config => 'invalid'], $baseline, function (): void { throw new RuntimeException('validator rejected'); });
    checkWrite('validation failure leaves original bytes intact', $result['state'] === 'failed' && file_get_contents($config) === $old);
    checkWrite('validation failure creates no backup of rejected content', count(glob($config . '.bak.*')) === 1);
    $result = $writer->commit([$config => $old], [$config => $baseline[$config]]);
    checkWrite('unchanged is a successful explicit state', $result['state'] === 'unchanged' && $result['status'] === 'ok' && !$result['changed']);
    [$code] = runFixture([PHP_BINARY, __FILE__, '--lock-child', $lock]);
    checkWrite('a competing process cannot enter the shared writer lock', $code === 0);
    $result = $writer->commit([$config => 'config-new', $template => 'template-new'], $baseline);
    checkWrite('both prepared files commit', $result['state'] === 'completed' && file_get_contents($config) === 'config-new' && file_get_contents($template) === 'template-new');
    checkWrite('backup contains the actual previous bytes', file_get_contents($result['backups'][$config]) === $old);
    if (PHP_OS_FAMILY !== 'Windows') {
        checkWrite('configuration and backup permissions are private', (fileperms($config) & 0777) === 0600 && (fileperms($result['backups'][$config]) & 0777) === 0600);
        checkWrite('legacy backups are hardened to private permissions', (fileperms($config . '.bak.legacy') & 0777) === 0600);
    }
    $result = $writer->commit([$config => 'stale-tab'], $baseline);
    checkWrite('stale revision cannot overwrite a newer write', $result['code'] === 'conflict' && file_get_contents($config) === 'config-new');
    $model = $root . '/model.xml';
    file_put_contents($model, '<model>old</model>');
    $modelBaseline = WriteCoordinator::revisions([$config, $model]);
    file_put_contents($model, '<model>new</model>');
    $result = $writer->commit([$config => 'rendered-from-old-model'], $modelBaseline);
    checkWrite('read-only model baseline prevents applying stale rendered settings', $result['code'] === 'conflict' && file_get_contents($config) === 'config-new' && file_get_contents($model) === '<model>new</model>');
    unset($writer);
    $faulty = new class($lock) extends WriteCoordinator {
        private int $count = 0;
        protected function replace(string $source, string $destination): bool
        {
            return ++$this->count === 2 ? false : parent::replace($source, $destination);
        }
    };
    $result = $faulty->commit([$config => 'should-rollback', $template => 'never-installed']);
    checkWrite('second-file failure restores the first file', $result['state'] === 'failed' && !$result['changed'] && file_get_contents($config) === 'config-new' && file_get_contents($template) === 'template-new');
    unset($faulty);
    $brokenRecovery = new class($lock) extends WriteCoordinator {
        private int $count = 0;
        protected function replace(string $source, string $destination): bool
        {
            return ++$this->count === 2 ? false : parent::replace($source, $destination);
        }
        protected function restore(string $source, string $destination): bool { return false; }
    };
    $result = $brokenRecovery->commit([$config => 'partially-installed', $template => 'never-installed']);
    checkWrite('failed recovery reports partial and retains the original backup', $result['state'] === 'partial' && $result['changed']
        && $result['unrestored'] === [$config] && file_get_contents($result['backups'][$config]) === 'config-new');
    unset($brokenRecovery);
    file_put_contents($config, 'config-new');
    checkWrite('all staging files cleaned after failure', glob($root . '/.mihomo-*') === []);
    $parsed = ActionResult::parse(json_encode(ActionResult::make('unchanged', false, 'unchanged', '')));
    checkWrite('empty no-op message remains a success', $parsed['state'] === 'unchanged');
    checkWrite('arbitrary success words cannot spoof a result', ActionResult::parse('saved successfully')['state'] === 'failed');
    checkWrite('accepted state is distinguishable from completion', ActionResult::parse(json_encode(ActionResult::make('accepted')))['state'] === 'accepted');

    // Exercise the actual subscription shell and installer with offline dependencies.
    $shell = PHP_OS_FAMILY === 'Windows' ? 'C:/Program Files/Git/usr/bin/sh.exe' : '/bin/sh';
    if (!is_file($shell)) { throw new RuntimeException('POSIX shell required for subscription fixtures'); }
    mkdir($root . '/sub', 0700);
    mkdir($root . '/bin', 0700);
    $repo = dirname(__DIR__);
    copy($repo . '/src/usr/local/etc/mihomo/sub/sub.sh', $root . '/sub/sub.sh');
    file_put_contents($root . '/sub/template_config.yaml', "mode: rule\n# __MIHOMO_PROXIES__\nproxy-groups:\n  - name: fixture\n    type: select\n    proxies:\n# __MIHOMO_NODE_NAMES__\nrules:\n  - MATCH,DIRECT\n");
    file_put_contents($root . '/payload.yaml', "proxies:\n  - name: fixture-node\n    type: direct\n");
    file_put_contents($root . '/bin/curl', "#!/bin/sh\nif [ -n \"\${FIXTURE_CONCURRENT_CONFIG:-}\" ]; then printf '%s' concurrent-newer > \"\$FIXTURE_CONCURRENT_CONFIG\"; fi\nwhile [ \"\$#\" -gt 0 ]; do\n if [ \"\$1\" = -o ]; then shift; cp \"\$FIXTURE_PAYLOAD\" \"\$1\"; exit 0; fi\n shift\ndone\nexit 1\n");
    file_put_contents($root . '/bin/jq', "#!/bin/sh\ncat >/dev/null\nprintf '%s' fixture-encoded-url\n");
    file_put_contents($root . '/bin/openssl', "#!/bin/sh\nprintf '%s' fixture-generated-secret\n");
    foreach (['curl', 'jq', 'openssl'] as $tool) { chmod($root . '/bin/' . $tool, 0700); }
    $binary = $root . (PHP_OS_FAMILY === 'Windows' ? '/validator.cmd' : '/validator');
    file_put_contents($binary, PHP_OS_FAMILY === 'Windows' ? "@exit /b 7\r\n" : "#!/bin/sh\nexit 7\n");
    chmod($binary, 0700);
    $posix = static function (string $path): string {
        $path = str_replace('\\', '/', $path);
        return preg_replace_callback('/^([A-Za-z]):/', fn($m) => '/' . strtolower($m[1]), $path);
    };
    $env = getenv();
    $env['PATH'] = $posix($root . '/bin') . ':' . (PHP_OS_FAMILY === 'Windows' ? '/usr/bin:/bin' : $env['PATH']);
    $env['FIXTURE_PAYLOAD'] = $posix($root . '/payload.yaml');
    $env['MIHOMO_DIR'] = $posix($root);
    $env['MIHOMO_FORMAL_CONFIG'] = $posix($config);
    $env['MIHOMO_BIN'] = $posix($binary);
    $env['MIHOMO_PHP_BIN'] = $posix(PHP_BINARY);
    $env['MIHOMO_WRITE_HELPER'] = $posix($repo . '/src/usr/local/opnsense/scripts/mihomo/subscription_install.php');
    $env['MIHOMO_LOCK_DIR'] = $posix($root . '/subscription.lock');
    $env['MIHOMO_SERVICE_CMD'] = PHP_OS_FAMILY === 'Windows' ? 'cmd /c exit 0' : '/usr/bin/true';
    $env['MIHOMO_CONVERTER_URL'] = 'direct';
    $env['mihomo_URL'] = 'https://example.invalid/subscription?token=fixture-private-token';
    $env['mihomo_secret'] = 'fixture-private-secret';
    [$code, $out, $err] = runFixture([$shell, $posix($root . '/sub/sub.sh')], $env);
    checkWrite('subscription validator failure leaves original config unchanged', $code !== 0 && file_get_contents($config) === 'config-new' && str_contains($out, 'Mihomo rejected'));
    checkWrite('subscription logs omit URL credentials and controller secret', !str_contains($out . $err, 'fixture-private-token') && !str_contains($out . $err, 'fixture-private-secret'));
    file_put_contents($binary, PHP_OS_FAMILY === 'Windows' ? "@exit /b 0\r\n" : "#!/bin/sh\nexit 0\n");
    [$code, $out, $err] = runFixture([$shell, $posix($root . '/sub/sub.sh')], $env);
    checkWrite('subscription success atomically installs generated config', $code === 0 && str_contains(file_get_contents($config), 'fixture-node'));
    if ($code !== 0) { echo 'Subscription fixture diagnostics: ' . $out . $err . "\n"; }
    $new = file_get_contents($config);
    file_put_contents($root . '/payload.yaml', "proxies:\n  - name: fixture-replacement\n    type: direct\n");
    $env['MIHOMO_SERVICE_CMD'] = PHP_OS_FAMILY === 'Windows' ? 'cmd /c exit 1' : '/usr/bin/false';
    [$code, $out, $err] = runFixture([$shell, $posix($root . '/sub/sub.sh')], $env);
    checkWrite('subscription restart failure restores genuinely previous config', $code !== 0 && file_get_contents($config) === $new && str_contains($out, 'restart_failed_rolled_back'));
    $env['MIHOMO_SERVICE_CMD'] = PHP_OS_FAMILY === 'Windows' ? 'cmd /c exit 0' : '/usr/bin/true';
    $env['FIXTURE_CONCURRENT_CONFIG'] = $posix($config);
    [$code, $out, $err] = runFixture([$shell, $posix($root . '/sub/sub.sh')], $env);
    checkWrite('subscription rejects a config changed during its download', $code !== 0 && file_get_contents($config) === 'concurrent-newer' && str_contains($out, 'conflict'));
    checkWrite('subscription removes only its unique staging directory', glob($root . '/.mihomo-sub.*') === []);
} finally {
    removeFixture($root);
}
echo "Write regressions: {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
