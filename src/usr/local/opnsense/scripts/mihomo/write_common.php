<?php
/* Shared configd helpers. No service or network operation on include. */
require_once dirname(__DIR__, 2) . '/mvc/app/models/OPNsense/Mihomo/WriteCoordinator.php';

use OPNsense\Mihomo\ActionResult;

function mihomo_result(array $result): never
{
    ActionResult::emit($result);
    // configd must preserve the structured failure instead of discarding stdout.
    exit(0);
}

function mihomo_fail(string $code, string $message): never
{
    mihomo_result(ActionResult::make('failed', false, $code, $message));
}

function mihomo_staging(string $path): string
{
    if (!preg_match('@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@', $path) || is_link($path) || !is_file($path)) {
        throw new RuntimeException('Invalid staging file');
    }
    $stat = stat($path);
    if ($stat === false || ($stat['mode'] & 0777) !== 0600 || $stat['size'] === 0) {
        throw new RuntimeException('Staging file must be non-empty and private');
    }
    $content = file_get_contents($path);
    if ($content === false) {
        throw new RuntimeException('Unable to read staging file');
    }
    return $content;
}

function mihomo_validate(string $path, string $dir, string $binary = '/usr/local/bin/mihomo'): void
{
    if (!is_file($binary)) {
        throw new RuntimeException('The mihomo binary is missing.');
    }
    $lines = [];
    $code = 0;
    exec(escapeshellarg($binary) . ' -t -d ' . escapeshellarg($dir) . ' -f ' . escapeshellarg($path) . ' 2>&1', $lines, $code);
    if ($code !== 0) {
        // Validator output may quote complete proxy URLs/passwords; never expose it.
        throw new RuntimeException('Mihomo rejected the configuration (exit ' . $code . ').');
    }
}
