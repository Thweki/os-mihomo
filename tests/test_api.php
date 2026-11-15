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
    // Keep the Apply failure fixture independent of appliance paths and services.
    class WriteCoordinator {
        public static function revisions(array $paths): array {
            $result = array_fill_keys($paths, 'missing');
            ksort($result);
            return $result;
        }
    }
    class Safety {
        public static int $calls = 0;
        public static function bootEnabled(): bool {
            self::$calls++;
            throw new \LogicException('Rejected YAML must not reach boot settings');
        }
    }
}
namespace {
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config'] as $name) {
        require_once $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    foreach (['Dashboard', 'Settings', 'Subscription', 'Routing', 'Log'] as $name) {
        require $app . 'controllers/OPNsense/Mihomo/Api/' . $name . 'Controller.php';
    }
    function expect($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
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

    // Exercise real Apply selection and patching with locked TUN siblings. The
    // always-written device/stack already match, but must still fail safely.
    $flow = "log-level: info\ntun: {enable: true, device: tun_mihomo, stack: gvisor, auto-route: false}\n";
    $flowFile = tempnam(sys_get_temp_dir(), 'mihomo-flow-test-');
    file_put_contents($flowFile, $flow);
    \OPNsense\Mihomo\Config::setFileOverride($flowFile);
    try {
        $apply = new class extends \OPNsense\Mihomo\Api\SettingsController {
            public $model;
            public function throwReadOnly() {}
            public function getModel() { return $this->model; }
        };
        $apply->model = (object)[
            'managed' => '',
            'general' => (object)[
                'logLevel' => 'debug', 'mode' => 'rule', 'allowLan' => '0',
                'controllerBind' => '127.0.0.1', 'controllerPort' => '9090',
                'secret' => '', 'ipv6' => '0', 'sniffer' => '0', 'enabled' => '1',
            ],
            'tun' => (object)[
                'enabled' => '0', 'device' => 'tun_mihomo', 'stack' => 'gvisor',
                'autoRoute' => '1', 'strictRoute' => '0', 'mtu' => '1500',
            ],
            'dns' => (object)[
                'enabled' => '0', 'listen' => '127.0.0.1:1053', 'enhancedMode' => 'redir-host', 'ipv6' => '0',
            ],
        ];
        $apply->request = new class extends Request {
            public function getJsonRawBody() {
                $expected = \OPNsense\Mihomo\WriteCoordinator::revisions([
                    \OPNsense\Mihomo\Config::FILE, \OPNsense\Mihomo\Subscription::ENV_FILE,
                    '/etc/rc.conf.d/mihomo', '/conf/config.xml',
                ]);
                return ['version' => hash('sha256', json_encode($expected, JSON_UNESCAPED_SLASHES))];
            }
        };
        foreach (['', 'mihomo.general.logLevel'] as $managed) {
            $apply->model->managed = $managed;
            $result = $apply->applyAction();
            expect($result['state'] === 'failed' && $result['changed'] === false && $result['code'] === 'apply',
                'Flow parent rejection is an explicit unchanged Apply failure');
            expect(str_contains($result['message'], '"tun"') && str_contains($result['message'], 'block mapping'),
                'Apply explains how to resolve the unsupported parent without exposing its contents');
            expect(\OPNsense\Core\Backend::$calls === 0 && \OPNsense\Mihomo\Safety::$calls === 0,
                'Flow parent rejection precedes other file preparation and configd commit');
            expect(file_get_contents($flowFile) === $flow, 'Locked siblings and earlier selected settings remain byte-identical');
            expect(glob($flowFile . '.bak.*') === [], 'Rejected Apply creates no configuration backup');
        }
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($flowFile);
    }
    echo "Settings Apply flow mappings: fixed TUN fields reject without writes\n";

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
