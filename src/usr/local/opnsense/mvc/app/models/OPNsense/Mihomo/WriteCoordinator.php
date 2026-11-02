<?php
namespace OPNsense\Mihomo;

require_once __DIR__ . '/ActionResult.php';

/** One advisory lock for every plugin configuration writer. Never unlink the lock inode. */
class WriteCoordinator
{
    public const LOCK = '/usr/local/etc/mihomo/.write.lock';
    private $lock;

    public function __construct(?string $lockPath = null, float $timeout = 10.0)
    {
        $path = $lockPath ?? self::LOCK;
        if (is_link($path)) {
            throw new \RuntimeException('Unsafe write lock');
        }
        $old = umask(0077);
        $this->lock = @fopen($path, 'c');
        umask($old);
        if ($this->lock === false || !@chmod($path, 0600)) {
            throw new \RuntimeException('Unable to open the configuration lock');
        }
        $deadline = microtime(true) + $timeout;
        do {
            if (flock($this->lock, LOCK_EX | LOCK_NB)) {
                return;
            }
            usleep(20000);
        } while (microtime(true) < $deadline);
        fclose($this->lock);
        $this->lock = null;
        throw new \RuntimeException('Configuration is busy; retry after the current write completes.');
    }

    public function __destruct()
    {
        if (is_resource($this->lock)) {
            flock($this->lock, LOCK_UN);
            fclose($this->lock);
        }
    }

    public static function revision(string $path): string
    {
        clearstatcache(true, $path);
        if (!file_exists($path)) {
            return 'missing';
        }
        $hash = @hash_file('sha256', $path);
        if ($hash === false) {
            throw new \RuntimeException('Unable to read configuration revision');
        }
        return $hash;
    }

    public static function revisions(array $paths): array
    {
        $result = [];
        foreach ($paths as $path) {
            $result[$path] = self::revision($path);
        }
        ksort($result);
        return $result;
    }

    public static function version(array $paths): string
    {
        return hash('sha256', json_encode(self::revisions($paths), JSON_UNESCAPED_SLASHES));
    }

    /** Overridable only for deterministic failure injection in isolated tests. */
    protected function replace(string $source, string $destination): bool
    {
        return @rename($source, $destination);
    }

    protected function restore(string $source, string $destination): bool
    {
        return @rename($source, $destination);
    }

    private function stage(string $path, string $content): string
    {
        $tmp = tempnam(dirname($path), '.mihomo-');
        if ($tmp === false || realpath(dirname($tmp)) !== realpath(dirname($path))) {
            if ($tmp !== false) {
                @unlink($tmp);
            }
            throw new \RuntimeException('Unable to stage a file on the target filesystem');
        }
        if (!chmod($tmp, 0600) || file_put_contents($tmp, $content) !== strlen($content)) {
            @unlink($tmp);
            throw new \RuntimeException('Unable to write the complete staging file');
        }
        $handle = fopen($tmp, 'r+');
        if ($handle !== false) {
            fflush($handle);
            if (function_exists('fsync')) {
                fsync($handle);
            }
            fclose($handle);
        }
        return $tmp;
    }

    /** All inputs are prepared and validated before the first target changes.
     * $validate receives target=>staged-path and must throw on rejection.
     * Runtime failures restore every already-replaced target before releasing the lock.
     */
    public function commit(array $files, array $expected = [], ?callable $validate = null): array
    {
        $staged = $before = $backups = $installed = [];
        try {
            foreach ($expected as $path => $hash) {
                if (!is_string($hash) || !hash_equals(self::revision($path), $hash)) {
                    return ActionResult::make('failed', false, 'conflict', 'Configuration changed; reload before saving.');
                }
            }
            foreach ($files as $path => $content) {
                if (is_link($path) || (file_exists($path) && !is_file($path)) || !is_string($content)) {
                    throw new \RuntimeException('Unsafe configuration target');
                }
                $before[$path] = is_file($path) ? file_get_contents($path) : null;
                if ($before[$path] === false) {
                    throw new \RuntimeException('Unable to read the current configuration');
                }
                foreach (glob($path . '.bak.*') ?: [] as $history) {
                    if (is_file($history) && !is_link($history) && !chmod($history, 0600)) {
                        throw new \RuntimeException('Unable to protect a configuration backup');
                    }
                }
                if ($before[$path] === $content) {
                    // Existing secrets must not retain a historical world-readable mode.
                    if (!chmod($path, 0600)) {
                        throw new \RuntimeException('Unable to protect configuration permissions');
                    }
                    continue;
                }
                $staged[$path] = $this->stage($path, $content);
            }
            if ($validate !== null) {
                $validate($staged);
            }
            if ($staged === []) {
                return ActionResult::make('unchanged', false, 'unchanged', 'Configuration is already up to date.', ['versions' => self::revisions(array_keys($files))]);
            }
            foreach ($staged as $path => $tmp) {
                if ($before[$path] !== null) {
                    $backup = $path . '.bak.' . gmdate('Ymd_His') . '_' . bin2hex(random_bytes(6));
                    $backupTmp = $this->stage($path, $before[$path]);
                    if (!@rename($backupTmp, $backup)) {
                        @unlink($backupTmp);
                        throw new \RuntimeException('Unable to preserve the previous configuration');
                    }
                    $backups[$path] = $backup;
                }
            }
            foreach ($staged as $path => $tmp) {
                if (!$this->replace($tmp, $path)) {
                    throw new \RuntimeException('Unable to replace a configuration file');
                }
                $installed[] = $path;
            }
            foreach ($backups as $path => $backup) {
                $history = glob($path . '.bak.*') ?: [];
                rsort($history);
                foreach (array_slice($history, 20) as $old) {
                    if (is_file($old) && !is_link($old)) {
                        @unlink($old);
                    }
                }
            }
            return ActionResult::make('completed', true, 'saved', 'Configuration saved.', ['backups' => $backups, 'versions' => self::revisions(array_keys($files))]);
        } catch (\Throwable $error) {
            $unrestored = [];
            foreach (array_reverse($installed) as $path) {
                try {
                    if ($before[$path] === null) {
                        if (!@unlink($path)) {
                            throw new \RuntimeException('remove failed');
                        }
                    } else {
                        $restore = $this->stage($path, $before[$path]);
                        if (!$this->restore($restore, $path)) {
                            @unlink($restore);
                            throw new \RuntimeException('restore failed');
                        }
                    }
                } catch (\Throwable $restoreError) {
                    $unrestored[] = $path;
                }
            }
            return ActionResult::make($unrestored === [] ? 'failed' : 'partial', $unrestored !== [],
                $unrestored === [] ? 'write_failed' : 'rollback_failed', $error->getMessage(),
                ['backups' => $backups, 'unrestored' => $unrestored]);
        } finally {
            foreach ($staged as $tmp) {
                if (is_file($tmp)) {
                    @unlink($tmp);
                }
            }
        }
    }
}
