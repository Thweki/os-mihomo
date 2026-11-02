<?php
namespace OPNsense\Mihomo;

/** Caller holds the configuration lock. A failed reload remains retryable after page reload. */
class CronApply
{
    public static function run(bool $changed, callable $save, callable $reload,
        string $marker = '/usr/local/etc/mihomo/.cron-pending'): bool
    {
        if (!$changed && !is_file($marker)) {
            return false;
        }
        if (is_link($marker)) {
            throw new \RuntimeException('Unsafe Cron pending marker.');
        }
        if ($changed) {
            $temporary = tempnam(dirname($marker), '.cron-');
            if ($temporary === false) {
                throw new \RuntimeException('Unable to preserve the pending Cron update.');
            }
            try {
                if (!chmod($temporary, 0600) || file_put_contents($temporary, "pending\n") !== 8
                    || !rename($temporary, $marker)) {
                    throw new \RuntimeException('Unable to preserve the pending Cron update.');
                }
            } finally {
                if (is_file($temporary)) { unlink($temporary); }
            }
            $save();
        }
        $output = strtolower(trim((string)$reload()));
        if (!in_array($output, ['ok', 'ok.'], true)) {
            throw new \RuntimeException('Cron reload was not confirmed; apply again to retry.');
        }
        if (!unlink($marker)) {
            throw new \RuntimeException('Cron reloaded, but its pending marker could not be cleared.');
        }
        return true;
    }
}
