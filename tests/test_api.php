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
namespace {
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config', 'Inspector', 'Safety'] as $name) {
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
    $config = tempnam(sys_get_temp_dir(), 'mihomo-safety-');
    file_put_contents($config, "external-controller: 127.0.0.1:9090\ntun:\n  enable: false\n");
    \OPNsense\Mihomo\Config::setFileOverride($config);
    $fixtures = [
        'empty response' => ['', false, 'The backend did not return a valid action result.'],
        'whitespace response' => [" \n\t", false, 'The backend did not return a valid action result.'],
        'malformed JSON' => ['{"state":', false, 'The backend did not return a valid action result.'],
        'incomplete envelope' => ['{"status":"ok"}', false, 'The backend did not return a valid action result.'],
        'legacy success text' => ['Configuration is valid.', false, 'The backend did not return a valid action result.'],
        'rejected configuration' => [
            '{"status":"failed","state":"failed","changed":false,"code":"configuration_failed","message":"Mihomo rejected the configuration (exit 1)."}',
            false, 'Mihomo rejected the configuration (exit 1).',
        ],
        'missing binary' => [
            '{"status":"failed","state":"failed","changed":false,"code":"configuration_failed","message":"The mihomo binary is missing."}',
            false, 'The mihomo binary is missing.',
        ],
        'successful validation' => [
            '{"status":"ok","state":"unchanged","changed":false,"code":"valid","message":"Configuration validation passed."}',
            true, 'Configuration validation passed.',
        ],
    ];
    foreach (['accepted', 'partial', 'failed', 'completed'] as $state) {
        $fixtures[$state . ' is not a validation result'] = [
            json_encode(\OPNsense\Mihomo\ActionResult::make($state, false, 'valid', 'Validation pending.')),
            false, 'Validation pending.',
        ];
    }
    $fixtures['unrelated successful result'] = [
        json_encode(\OPNsense\Mihomo\ActionResult::make('unchanged', false, 'unchanged', 'No changes.')),
        false, 'No changes.',
    ];
    $fixtures['success depends on the envelope, not message words'] = [
        json_encode(\OPNsense\Mihomo\ActionResult::make('unchanged', false, 'valid', 'No invalid syntax or error found.')),
        true, 'No invalid syntax or error found.',
    ];
    try {
        foreach ($fixtures as $label => [$output, $valid, $message]) {
            \OPNsense\Core\Backend::$output = $output;
            $report = \OPNsense\Mihomo\Safety::report(true);
            $item = $report['items'][count($report['items']) - 1];
            expect($item['level'] === ($valid ? 'info' : 'danger'), 'Safety validation severity: ' . $label);
            expect($report['status'] === ($valid ? 'info' : 'danger'), 'Safety report severity: ' . $label);
            expect($item['title'] === ($valid ? 'Configuration syntax is valid' : 'Configuration syntax is invalid'), 'Safety validation title: ' . $label);
            expect($item['detail'] === $message, 'Safety validation message: ' . $label);
        }
        $report = \OPNsense\Mihomo\Safety::report(false);
        expect(count($report['items']) === 1, 'Optional validation stays disabled by default');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($config);
    }
    echo "Safety structured validation results: passed\n";
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
