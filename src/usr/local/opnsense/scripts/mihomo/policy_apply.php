#!/usr/local/bin/php
<?php
/* Prepare both policy targets under the common lock; validate before either changes. */
require_once __DIR__ . '/write_common.php';
require_once dirname(__DIR__, 2) . '/mvc/app/models/OPNsense/Mihomo/Config.php';

use OPNsense\Mihomo\Config;
use OPNsense\Mihomo\WriteCoordinator;

$staging = $argv[2] ?? '';
$cleanup = false;
try {
    if (($argv[1] ?? '') !== 'apply') {
        throw new RuntimeException('Unsupported policy action');
    }
    $raw = mihomo_staging($staging);
    $cleanup = true;
    $payload = json_decode($raw, true);
    if (!is_array($payload) || !is_array($payload['rules'] ?? null) || !is_array($payload['expected'] ?? null)) {
        throw new RuntimeException('Policy requires rules and baseline revisions');
    }
    $rules = [];
    foreach ($payload['rules'] as $rule) {
        if (!is_string($rule) || preg_match('/[\x00-\x1f]/', $rule)) {
            throw new RuntimeException('Invalid policy rule');
        }
        if (trim($rule) !== '') {
            $rules[] = trim($rule);
        }
    }
    $writer = new WriteCoordinator();
    $files = [];
    foreach ([Config::FILE, Config::TEMPLATE_FILE] as $path) {
        if (!isset($payload['expected'][$path])) {
            throw new RuntimeException('Missing policy baseline revision');
        }
        if (!is_file($path)) {
            if ($path === Config::FILE) {
                throw new RuntimeException('Configuration file not found');
            }
            continue;
        }
        $content = file_get_contents($path);
        if ($content === false) {
            throw new RuntimeException('Unable to read policy target');
        }
        $files[$path] = Config::applyPolicyBlock($content, $rules);
    }
    $expected = array_intersect_key($payload['expected'], array_flip([Config::FILE, Config::TEMPLATE_FILE, '/conf/config.xml']));
    $result = $writer->commit($files, $expected, function (array $staged): void {
        if (isset($staged[Config::FILE])) {
            mihomo_validate($staged[Config::FILE], dirname(Config::FILE));
        }
    });
    $result['messages'] = [$result['message']];
    @unlink($staging);
    mihomo_result($result);
} catch (Throwable $error) {
    if ($cleanup) {
        @unlink($staging);
    }
    mihomo_fail('policy_failed', $error->getMessage());
}
