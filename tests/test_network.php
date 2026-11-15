<?php
/* Offline concurrency regressions. No appliance files, services or network access. */
require __DIR__ . '/fixtures/network/config.inc';
require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/NetworkConfig.php';
use OPNsense\Core\Config as CoreConfig;
use OPNsense\Mihomo\NetworkConfig;
use OPNsense\Mihomo\WriteCoordinator;

function transaction(?string $expected = null): NetworkConfig
{
    $dir = getenv('NETWORK_FIXTURE');
    return new NetworkConfig($expected, $dir . '/config.xml', $dir . '/.write.lock');
}
function checkNetwork(bool $condition, string $label): void
{
    if (!$condition) { throw new RuntimeException($label); }
    echo 'PASS ' . $label . "\n";
}
function startNetwork(array $args): array
{
    $process = proc_open(array_merge([PHP_BINARY], $args),
        [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($process)) { throw new RuntimeException('Unable to start fixture'); }
    fclose($pipes[0]);
    return [$process, $pipes];
}
function finishNetwork(array $child): string
{
    [$process, $pipes] = $child;
    $out = stream_get_contents($pipes[1]);
    $err = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    checkNetwork(proc_close($process) === 0 && $err === '', 'fixture subprocess completed');
    return $out;
}
function waitForPluginLock(string $path): void
{
    $handle = fopen($path, 'c');
    $deadline = microtime(true) + 5;
    do {
        if (!flock($handle, LOCK_EX | LOCK_NB)) { fclose($handle); return; }
        flock($handle, LOCK_UN);
        usleep(10000);
    } while (microtime(true) < $deadline);
    fclose($handle);
    throw new RuntimeException('Writer did not acquire plugin lock before waiting on core');
}
function removeNetwork(string $dir): void
{
    foreach (scandir($dir) as $name) {
        if ($name === '.' || $name === '..') { continue; }
        $path = $dir . '/' . $name;
        if (is_dir($path)) { removeNetwork($path); } else { unlink($path); }
    }
    rmdir($dir);
}

if (($argv[1] ?? '') === '--writer') {
    // Populate a stale core singleton before taking either lock.
    CoreConfig::getInstance();
    file_put_contents(getenv('NETWORK_FIXTURE') . '/ready', 'ready');
    try {
        $tx = transaction(($argv[2] ?? '') === '-' ? null : $argv[2]);
        $saved = $tx->commit(str_replace('<managed>old</managed>', '<managed>new</managed>', $tx->before));
        $tx->close();
        echo json_encode($saved);
    } catch (RuntimeException $error) {
        echo json_encode(['conflict' => true]);
    }
    exit(0);
}

$dir = sys_get_temp_dir() . '/mihomo-network-' . bin2hex(random_bytes(8));
mkdir($dir, 0700);
putenv('NETWORK_FIXTURE=' . $dir);
$path = $dir . '/config.xml';
$initial = '<opnsense><system><hostname>original</hostname></system><managed>old</managed>'
    . '<interfaces><lo0><if>lo0</if></lo0><lan><if>igb0</if><ipaddr>192.0.2.1</ipaddr><subnet>24</subnet></lan></interfaces>'
    . '<OPNsense><unboundplus><forwarding><enabled>1</enabled></forwarding>'
    . '<advanced><privateaddress>198.18.0.0/15,10.0.0.0/8</privateaddress></advanced><dots></dots></unboundplus>'
    . '<unrelated uuid="keep"><item>first</item><item>second</item></unrelated></OPNsense></opnsense>';
file_put_contents($path, $initial);
try {
    // Core writer holds the inode while the plugin writer loads an earlier singleton.
    $core = CoreConfig::getInstance();
    $core->lock();
    $child = startNetwork([__FILE__, '--writer', '-']);
    waitForPluginLock($dir . '/.write.lock');
    $core->object()->system->hostname = 'other-admin';
    $core->save();
    $first = json_decode(finishNetwork($child), true);
    $xml = simplexml_load_file($path);
    checkNetwork(isset($first['backup']) && (string)$xml->managed === 'new'
        && (string)$xml->system->hostname === 'other-admin', 'overlapping core and plugin edits both survive');
    checkNetwork((string)$xml->OPNsense->unrelated['uuid'] === 'keep'
        && count($xml->OPNsense->unrelated->item) === 2, 'unrelated attributes and repeated nodes survive');
    checkNetwork(str_contains(file_get_contents($first['backup']), 'other-admin'), 'backup is taken after the competing writer completes');

    // A second plugin writer waits for the first and must reject its stale revision.
    $tx = transaction();
    $stale = $tx->version;
    unlink($dir . '/ready');
    $child = startNetwork([__FILE__, '--writer', $stale]);
    $deadline = microtime(true) + 5;
    while (!is_file($dir . '/ready') && microtime(true) < $deadline) { usleep(10000); }
    checkNetwork(is_file($dir . '/ready'), 'competing plugin writer starts before the first save');
    $second = $tx->commit(str_replace('other-admin', 'newer-admin', $tx->before));
    $tx->close();
    $rejected = json_decode(finishNetwork($child), true);
    checkNetwork(!empty($rejected['conflict']) && str_contains(file_get_contents($path), 'newer-admin'),
        'overlapping plugin writer cannot install stale XML');
    checkNetwork($first['backup'] !== $second['backup'] && is_file($first['backup']), 'rapid saves retain distinct backups');
    checkNetwork((fileperms($first['backup']) & 0777) === 0600
        && (fileperms($second['backup']) & 0777) === 0600, 'network backups are private');
    checkNetwork(glob($dir . '/.mihomo-*') === [], 'unique backup staging files are cleaned');

    // Revision recheck also catches a writer which does not obey advisory locks.
    $tx = transaction();
    $newer = str_replace('newer-admin', 'out-of-band', $tx->before);
    file_put_contents($path, $newer);
    try { $tx->commit(str_replace('<managed>new</managed>', '<managed>stale</managed>', $tx->before));
        throw new LogicException('Lost update accepted');
    } catch (RuntimeException $error) { checkNetwork(file_get_contents($path) === $newer, 'revision recheck preserves out-of-band edit'); }
    $tx->close();

    $tx = transaction();
    try { $tx->rollback($second['backup']); throw new LogicException('Unsafe rollback accepted'); }
    catch (RuntimeException $error) { checkNetwork(file_get_contents($path) === $newer, 'rollback refuses unrelated changes since backup'); }
    $tx->close();

    $tx = transaction();
    $backupsBefore = glob($path . '.mihomo-bak.*');
    try { $tx->commit('<opnsense><broken>'); throw new LogicException('Invalid XML accepted'); }
    catch (RuntimeException $error) {
        checkNetwork(file_get_contents($path) === $newer && glob($path . '.mihomo-bak.*') === $backupsBefore
            && glob($dir . '/.mihomo-*') === [], 'invalid XML leaves configuration, backups and staging untouched');
    }
    $tx->close();

    // Inode identity is part of the appliance's lock contract.
    $open = fopen($path, 'r');
    $inode = fstat($open)['ino'];
    $tx = transaction();
    $third = $tx->commit(str_replace('out-of-band', 'final-admin', $tx->before));
    $tx->close();
    clearstatcache(true, $path);
    checkNetwork(fileinode($path) === $inode && str_contains(stream_get_contents($open), 'final-admin'),
        'core persistence updates the already-open inode');
    fclose($open);
    $tx = transaction($third['version']);
    $core->object()->managed = 'floating-rules';
    $version = $tx->save();
    $tx->advanceBackup($third['backup'], $version);
    $tx->close();
    $tx = transaction($version);
    $tx->rollback($third['backup']);
    $tx->close();
    checkNetwork(str_contains(file_get_contents($path), 'out-of-band')
        && !str_contains(file_get_contents($path), 'floating-rules'), 'guarded rollback includes the API stage');

    // Exercise actual workers with only appliance paths/bootstrap redirected.
    $scripts = dirname(__DIR__) . '/src/usr/local/opnsense/scripts/mihomo';
    $models = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo';
    foreach (['policy_net.php', 'setup_unbound.php'] as $name) {
        $source = file_get_contents($scripts . '/' . $name);
        $source = str_replace("require_once 'config.inc';", 'require_once ' . var_export(__DIR__ . '/fixtures/network/config.inc', true) . ';', $source);
        $source = str_replace("__DIR__ . '/write_common.php'", var_export($scripts . '/write_common.php', true), $source);
        $source = str_replace("dirname(__DIR__, 2) . '/mvc/app/models/OPNsense/Mihomo/NetworkConfig.php'", var_export($models . '/NetworkConfig.php', true), $source);
        $source = str_replace(['/conf/config.xml', '/var/db/os-mihomo'], [$path, $dir . '/state'], $source);
        // Constructor injection stays test-only, never exposed via worker arguments/environment.
        $source = str_replace('new NetworkConfig(', 'fixtureTransaction(', $source);
        $source = str_replace('use OPNsense\\Mihomo\\NetworkConfig;', 'use OPNsense\\Mihomo\\NetworkConfig;' . "\n"
            . 'function fixtureTransaction(?string $version = null) { return new NetworkConfig($version, '
            . var_export($path, true) . ', ' . var_export($dir . '/.write.lock', true) . '); }', $source);
        file_put_contents($dir . '/' . $name, $source);
    }
    mkdir($dir . '/bin');
    foreach (['ifconfig', 'configctl', 'pfctl'] as $name) {
        file_put_contents($dir . '/bin/' . $name, "#!/bin/sh\nexit 0\n");
        chmod($dir . '/bin/' . $name, 0700);
    }
    putenv('PATH=' . $dir . '/bin:' . getenv('PATH'));
    // These deliberately occupied historical names must never be touched.
    file_put_contents($path . '.mihomo-new', 'other-writer-stage');
    file_put_contents($path . '.os-mihomo.tmp', 'other-unbound-stage');
    $staging = tempnam('/tmp', 'mihomo-');
    chmod($staging, 0600);
    $payload = ['interfaces' => ['lan'], 'gateway' => '198.18.0.2', 'verify' => false,
        'version' => WriteCoordinator::revision($path)];
    file_put_contents($staging, json_encode($payload));
    $plan = json_decode(finishNetwork(startNetwork([$dir . '/policy_net.php', 'plan', $staging])), true);
    checkNetwork($plan['version'] === $payload['version'], 'plan returns its reviewed XML revision');
    $applied = json_decode(finishNetwork(startNetwork([$dir . '/policy_net.php', 'apply', $staging])), true);
    checkNetwork($applied['status'] === 'ok' && str_contains(file_get_contents($path), 'MIHOMO_TUN'), 'actual network worker persists through core');
    file_put_contents($staging, json_encode($payload));
    $before = file_get_contents($path);
    $conflict = json_decode(finishNetwork(startNetwork([$dir . '/policy_net.php', 'apply', $staging])), true);
    checkNetwork($conflict['status'] === 'failed' && file_get_contents($path) === $before, 'actual worker rejects a stale reviewed plan');
    unlink($staging);
    finishNetwork(startNetwork([$dir . '/setup_unbound.php', 'install']));
    finishNetwork(startNetwork([$dir . '/setup_unbound.php', 'uninstall']));
    $xml = simplexml_load_file($path);
    checkNetwork((string)$xml->OPNsense->unboundplus->forwarding->enabled === '1'
        && str_contains((string)$xml->OPNsense->unboundplus->advanced->privateaddress, '198.18.0.0/15')
        && str_contains(file_get_contents($path), 'MIHOMO_TUN') && (string)$xml->system->hostname === 'out-of-band',
        'Unbound round trip preserves network and unrelated configuration');
    checkNetwork(file_get_contents($path . '.mihomo-new') === 'other-writer-stage'
        && file_get_contents($path . '.os-mihomo.tmp') === 'other-unbound-stage'
        && glob($dir . '/.mihomo-*') === [], 'workers never clobber another staging file');
    require __DIR__ . '/fixtures/network/api.php';
    require $models . '/RequestParamsTrait.php';
    require $models . '/Config.php';
    $controllerSource = file_get_contents(dirname($models, 3) . '/controllers/OPNsense/Mihomo/Api/RoutingController.php');
    $controllerSource = str_replace('new NetworkConfig(', '\\transaction(', $controllerSource);
    file_put_contents($dir . '/RoutingController.php', $controllerSource);
    require $dir . '/RoutingController.php';
    $networkBackend = function ($action, $args) use ($dir, $path) {
        foreach ([$dir . '/.write.lock', $path] as $lockPath) {
            $handle = fopen($lockPath, 'r+');
            $free = flock($handle, LOCK_EX | LOCK_NB);
            if ($free) { flock($handle, LOCK_UN); }
            fclose($handle);
            checkNetwork($free, 'API releases locks before synchronous worker call');
        }
        $mode = substr($action, strlen('mihomo policy-net-'));
        return finishNetwork(startNetwork(array_merge([$dir . '/policy_net.php', $mode], $args)));
    };
    $controller = new \OPNsense\Mihomo\Api\RoutingController();
    $controller->request = new class {
        public string $version = '';
        public function isPost() { return true; }
        public function getPost($name, $filter = null, $default = null) { return $name === 'version' ? $this->version : $default; }
        public function getJsonRawBody() { return []; }
    };
    $plan = $controller->netplanAction();
    $controller->request->version = $plan['version'];
    $result = $controller->netapplyAction();
    checkNetwork($result['status'] === 'ok' && str_contains(file_get_contents($path), 'out-of-band')
        && str_contains(file_get_contents($path), '<fixtureRules>saved</fixtureRules>'), 'API stages preserve refreshed unrelated configuration');
    $result = $controller->netrollbackAction();
    checkNetwork($result['status'] === 'ok' && str_contains(file_get_contents($path), 'MIHOMO_TUN')
        && !str_contains(file_get_contents($path), '<fixtureRules>'), 'actual rollback accepts the completed API transaction');
    // Insert another administrator's save between worker and API model stages.
    $normalBackend = $networkBackend;
    $networkBackend = function ($action, $args) use ($normalBackend) {
        $result = $normalBackend($action, $args);
        if ($action === 'mihomo policy-net-apply') {
            $core = CoreConfig::getInstance()->lock();
            $core->object()->system->hostname = 'between-stages';
            $core->save();
        }
        return $result;
    };
    $controller->request->version = WriteCoordinator::revision($path);
    $result = $controller->netapplyAction();
    checkNetwork($result['status'] === 'failed' && str_contains(file_get_contents($path), 'between-stages')
        && !str_contains(file_get_contents($path), '<fixtureRules>'), 'API refuses to overwrite an intervening core save');

} finally {
    if (isset($tx)) { $tx->close(); }
    removeNetwork($dir);
}
echo "Network concurrency regressions passed\n";
