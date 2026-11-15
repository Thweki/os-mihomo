<?php
/** Isolated API contracts. No framework, appliance files, network or configd execution. */
namespace OPNsense\Base {
    class ApiControllerBase {
        public $request;
        public function throwReadOnly() { throw new \RuntimeException('read-only'); }
    }
    class ApiMutableModelControllerBase extends ApiControllerBase {}
}
namespace OPNsense\Core {
    class Backend {
        public static string $output = '';
        public static int $calls = 0;
        public function configdRun($action) { self::$calls++; return self::$output; }
        public function configdpRun($action, $args) { self::$calls++; return self::$output; }
    }
}
namespace OPNsense\Mihomo {
    // Namespace-local transport doubles exercise the real JSON decoder without
    // opening sockets or requiring the cURL extension on portable PHP runners.
    class ControllerHttpFixture {
        public static string|false $body = '';
        public static int $status = 200;
        public static string $url = '';
    }
    function curl_init($url) { ControllerHttpFixture::$url = $url; return $url; }
    function curl_setopt_array($handle, $options) { return true; }
    function curl_exec($handle) { return ControllerHttpFixture::$body; }
    function curl_getinfo($handle, $option) { return ControllerHttpFixture::$status; }
    function curl_error($handle) { return 'Fixture transport failure'; }
    function curl_close($handle) {}
    function gettext($message) { return $message; }
}
namespace {
    foreach (['CURLOPT_CUSTOMREQUEST', 'CURLOPT_RETURNTRANSFER', 'CURLOPT_CONNECTTIMEOUT',
        'CURLOPT_TIMEOUT', 'CURLOPT_HTTPHEADER', 'CURLOPT_FOLLOWLOCATION', 'CURLINFO_HTTP_CODE'] as $name) {
        define('OPNsense\\Mihomo\\' . $name, $name);
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config', 'Controller'] as $name) {
        require_once $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    foreach (['Dashboard', 'Settings', 'Subscription', 'Routing', 'Log'] as $name) {
        require $app . 'controllers/OPNsense/Mihomo/Api/' . $name . 'Controller.php';
    }
    function expect($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
    // Use only the shipped example configuration, never appliance credentials.
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        foreach (['version' => ['version' => 'fixture', 'meta' => true],
            'runningConfig' => ['mode' => 'rule', 'tun' => ['enable' => false]]] as $method => $valid) {
            foreach (['"unexpected"', '""', '42', '1.5', 'true', 'false', 'null', '', '{invalid'] as $body) {
                \OPNsense\Mihomo\ControllerHttpFixture::$body = $body;
                expect(\OPNsense\Mihomo\Controller::$method() === null,
                    $method . ' treats non-array JSON as unavailable without a TypeError');
            }
            foreach ([$valid, []] as $data) {
                \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode($data);
                expect(\OPNsense\Mihomo\Controller::$method() === $data, $method . ' preserves decoded arrays');
            }
            $path = $method === 'version' ? '/version' : '/configs';
            expect(\OPNsense\Mihomo\ControllerHttpFixture::$url === 'http://127.0.0.1:9090' . $path,
                $method . ' uses the expected controller endpoint');
            \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode($valid);
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
            expect(\OPNsense\Mihomo\Controller::$method() === null, $method . ' rejects unsuccessful HTTP responses');
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
            \OPNsense\Mihomo\ControllerHttpFixture::$body = false;
            expect(\OPNsense\Mihomo\Controller::$method() === null, $method . ' handles transport failure');
        }
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Controller metadata response types: passed\n";
    class Request {
        public function isPost() { return true; }
        public function getPost($name, $filter = null, $default = null) { return $default; }
        public function getQuery($name, $filter = null, $default = null) { return $default; }
        public function getJsonRawBody() { return []; }
    }
    $guarded = [
        'Dashboard' => ['selectProxy', 'setMode', 'closeConnection', 'testDelay'],
        'Settings' => ['set', 'apply', 'import', 'configSet'],
        'Subscription' => ['save', 'run', 'clearLog'],
        'Routing' => ['apply', 'historyRestore', 'netapply', 'netrollback', 'selftest'],
        'Log' => ['clear'],
    ];
    foreach ($guarded as $name => $actions) {
        $class = 'OPNsense\\Mihomo\\Api\\' . $name . 'Controller';
        $controller = new $class();
        $controller->request = new Request();
        foreach ($actions as $action) {
            try { $controller->{$action . 'Action'}(); throw new \LogicException('Guard absent: ' . $name . '/' . $action); }
            catch (\RuntimeException $error) { expect($error->getMessage() === 'read-only', 'Read-only rejected before I/O'); }
        }
    }
    expect(\OPNsense\Core\Backend::$calls === 0, 'Read-only calls never reach configd');
    $settings = new \OPNsense\Mihomo\Api\SettingsController();
    foreach (['', 'FATAL: invalid config', 'Configuration is valid.', '{"status":"ok"}', '{"state":"failed","status":"ok","changed":"no","code":[],"message":"invalid"}'] as $output) {
        \OPNsense\Core\Backend::$output = $output;
        expect($settings->configTestAction()['status'] === 'failed', 'Unknown output must not be reported as valid');
    }
    foreach (['unchanged', 'completed', 'accepted', 'failed', 'partial'] as $state) {
        $result = \OPNsense\Mihomo\ActionResult::make($state, $state === 'completed');
        $parsed = \OPNsense\Mihomo\ActionResult::parse(json_encode($result));
        expect($parsed['state'] === $state && is_bool($parsed['changed']), 'Structured state round trip: ' . $state);
    }
    \OPNsense\Core\Backend::$output = json_encode(\OPNsense\Mihomo\ActionResult::make('completed'));
    expect($settings->configTestAction()['status'] === 'ok', 'Explicit validated result accepted');
    $raw = "converter https://example.invalid/path?token=fixture-value\nsecret: fixture-secret\nAuthorization: Bearer fixture-auth\n访问密钥：fixture-key\nnormal message";
    $redacted = \OPNsense\Mihomo\Logs::redact($raw);
    foreach (['fixture-value', 'fixture-secret', 'fixture-auth', 'fixture-key'] as $secret) {
        expect(!str_contains($redacted, $secret), 'Sensitive output masked');
    }
    expect(str_contains($redacted, 'normal message'), 'Ordinary log text preserved');
    $acl = simplexml_load_file($app . 'models/OPNsense/Mihomo/ACL/ACL.xml');
    $view = array_map('strval', iterator_to_array($acl->{'page-vpn-mihomo-view'}->patterns->pattern, false));
    foreach (['api/mihomo/settings/config_get', 'api/mihomo/subscription/get', 'api/mihomo/dashboard/set_mode', 'api/mihomo/routing/history_show'] as $path) {
        foreach ($view as $pattern) { expect(!fnmatch($pattern, $path), 'View privilege excludes mutation and credentials'); }
    }
    expect((string)$acl->{'page-vpn-mihomo'}->patterns->pattern[1] === 'api/mihomo/*', 'Existing full-access grant remains compatible');
    require $app . 'models/OPNsense/Mihomo/CronApply.php';
    $marker = sys_get_temp_dir() . '/mihomo-cron-test-' . bin2hex(random_bytes(6));
    $saves = 0; $reloads = 0;
    $save = function () use (&$saves) { $saves++; };
    try {
        try {
            \OPNsense\Mihomo\CronApply::run(true, $save, function () use (&$reloads) { $reloads++; return 'failed'; }, $marker);
            throw new \LogicException('Cron failure was hidden');
        } catch (\RuntimeException $error) {
            expect(is_file($marker) && $saves === 1, 'Failed Cron reload remains pending after saved model');
        }
        expect(\OPNsense\Mihomo\CronApply::run(false, $save, function () use (&$reloads) { $reloads++; return 'OK'; }, $marker), 'Unchanged model retries pending Cron reload');
        expect(!is_file($marker) && $saves === 1 && $reloads === 2, 'Retry only reloads and clears pending marker');
        expect(!\OPNsense\Mihomo\CronApply::run(false, $save, fn () => 'unexpected', $marker), 'Unchanged completed Cron is a no-op');
    } finally { if (is_file($marker)) { unlink($marker); } }
    echo "API read-only guards, strict action results, redaction and ACL: passed\n";
}
