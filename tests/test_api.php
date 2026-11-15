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
        public static array $requests = [];
        public static array $responses = [];
    }
    function curl_init($url) { ControllerHttpFixture::$url = $url; return $url; }
    function curl_setopt_array($handle, $options) {
        ControllerHttpFixture::$requests[] = [$options[CURLOPT_CUSTOMREQUEST], $handle];
        return true;
    }
    function curl_exec($handle) {
        if (ControllerHttpFixture::$responses) {
            [ControllerHttpFixture::$status, ControllerHttpFixture::$body] = array_shift(ControllerHttpFixture::$responses);
        }
        return ControllerHttpFixture::$body;
    }
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
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config', 'Controller', 'Inspector', 'Safety'] as $name) {
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
        'Dashboard' => ['selectProxy', 'resetProxy', 'setMode', 'closeConnection', 'testDelay'],
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

    // Reset uses the core's unfix operation, never a guessed first/fastest member.
    class WritableDashboard extends \OPNsense\Mihomo\Api\DashboardController {
        public function throwReadOnly() {}
    }
    class ResetRequest extends Request {
        public function __construct(public mixed $group, public bool $post = true) {}
        public function isPost() { return $this->post; }
        public function getJsonRawBody() { return ['group' => $this->group]; }
    }
    $reset = function ($group, $post = true) {
        $controller = new WritableDashboard();
        $controller->request = new ResetRequest($group, $post);
        return $controller->resetProxyAction();
    };
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
        foreach ([null, '', [], 123] as $invalid) {
            expect($reset($invalid)['status'] === 'failed', 'Invalid reset name rejected');
        }
        expect($reset('Group', false)['status'] === 'failed', 'Reset requires POST');
        expect(\OPNsense\Mihomo\ControllerHttpFixture::$requests === [], 'Rejected reset does no controller I/O');

        $name = ' 中文 /?%#" &gt; ';
        $url = 'http://127.0.0.1:9090/proxies/' . rawurlencode($name);
        foreach (['URLTest', 'Fallback'] as $type) {
            // Empty fixed is also safe: reset is idempotent if another operator already reset it.
            foreach (['Pinned', ''] as $fixed) {
                \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
                \OPNsense\Mihomo\ControllerHttpFixture::$responses = [
                    [200, json_encode(['type' => $type, 'fixed' => $fixed])], [204, ''],
                ];
                $result = $reset($name);
                expect($result['status'] === 'ok' && str_contains($result['message'], $name), 'Reset success preserves exact group name');
                expect(\OPNsense\Mihomo\ControllerHttpFixture::$requests === [['GET', $url], ['DELETE', $url]],
                    'Reset validates live type then deletes only the encoded group override');
            }
        }
        foreach ([['type' => 'Selector'], ['type' => 'LoadBalance'], ['type' => 'Direct'], [], 'invalid'] as $data) {
            \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
            \OPNsense\Mihomo\ControllerHttpFixture::$responses = [[200, json_encode($data)]];
            expect($reset($name)['status'] === 'failed', 'Unsupported or malformed group rejected');
            expect(count(\OPNsense\Mihomo\ControllerHttpFixture::$requests) === 1, 'Unsupported type never reaches DELETE');
        }
        foreach ([[404, '{}'], [503, '{}'], [0, false]] as $failure) {
            foreach ([false, true] as $failDelete) {
                \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
                \OPNsense\Mihomo\ControllerHttpFixture::$responses = $failDelete
                    ? [[200, '{"type":"URLTest"}'], $failure] : [$failure];
                $result = $reset($name);
                expect($result['status'] === 'failed' && $result['message'] !== '', 'Reset reports read/write failures');
                expect(count(\OPNsense\Mihomo\ControllerHttpFixture::$requests) === ($failDelete ? 2 : 1), 'Failed read prevents mutation');
            }
        }
        $nodes = [];
        foreach (['URLTest', 'Fallback', 'Selector', 'LoadBalance'] as $type) {
            foreach (['', 'Pinned', '0', null, []] as $i => $fixed) {
                $nodes[$type . $i] = ['type' => $type, 'fixed' => $fixed, 'all' => ['First', 'Pinned'], 'now' => 'Pinned'];
            }
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$responses = [[200, json_encode(['proxies' => $nodes])]];
        foreach (\OPNsense\Mihomo\Controller::proxyGroups()['groups'] as $group) {
            $node = $nodes[$group['name']];
            $expected = in_array($node['type'], ['URLTest', 'Fallback'], true)
                && is_string($node['fixed']) && $node['fixed'] !== '';
            expect($group['canReset'] === $expected, 'Only overridden automatic groups advertise reset');
            expect($group['members'][1]['selected'], 'Reset capability preserves selection');
        }
    } finally {
        \OPNsense\Mihomo\ControllerHttpFixture::$responses = [];
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Automatic selection reset: guards, exact names, group types and controller failures passed\n";
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
    foreach (['api/mihomo/settings/config_get', 'api/mihomo/subscription/get', 'api/mihomo/dashboard/set_mode', 'api/mihomo/dashboard/reset_proxy', 'api/mihomo/routing/history_show'] as $path) {
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
