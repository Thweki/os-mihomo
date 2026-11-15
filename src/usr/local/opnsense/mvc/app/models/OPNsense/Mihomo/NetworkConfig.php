<?php
namespace OPNsense\Mihomo;

require_once __DIR__ . '/WriteCoordinator.php';

/** A short XML transaction. Release before calling configd or reloading services. */
class NetworkConfig
{
    private ?WriteCoordinator $writer = null;
    private $core = null;
    private string $path;
    public string $before;
    public string $version;

    public function __construct(?string $expected = null, string $path = '/conf/config.xml', ?string $lock = null)
    {
        $this->path = $path;
        // All plugin writers take this lock before the appliance configuration lock.
        $this->writer = new WriteCoordinator($lock);
        try {
            $this->core = \OPNsense\Core\Config::getInstance();
            $this->core->lock(); // reloads the authoritative configuration under lock
            $content = file_get_contents($path);
            if ($content === false) {
                throw new \RuntimeException('Unable to read appliance configuration.');
            }
            $this->before = $content;
            $this->version = hash('sha256', $this->before);
            if ($expected !== null && !hash_equals($this->version, $expected)) {
                throw new \RuntimeException('Configuration changed; reload the network plan before continuing.');
            }
        } catch (\Throwable $error) {
            $this->close();
            throw $error;
        }
    }

    public function close(): void
    {
        if ($this->core !== null) {
            $this->core->unlock();
            $this->core = null;
        }
        $this->writer = null;
    }

    public function __destruct()
    {
        $this->close();
    }

    /** Save already-mutated core models, retaining the revision actually saved. */
    public function save(): string
    {
        if (!hash_equals($this->version, WriteCoordinator::revision($this->path))) {
            throw new \RuntimeException('Configuration changed during the network update.');
        }
        $this->core->save();
        // save() unlocks the inode. Hash our saved object, never a subsequent writer's bytes.
        return hash('sha256', (string)$this->core);
    }

    public function commit(string $xml, string $backupTag = 'mihomo-bak'): array
    {
        if ($xml === $this->before) {
            return ['version' => $this->version, 'backup' => null];
        }
        $doc = new \DOMDocument();
        $errors = libxml_use_internal_errors(true);
        try {
            if (!$doc->loadXML($xml, LIBXML_NONET) || $doc->documentElement->tagName !== 'opnsense') {
                throw new \RuntimeException('Generated configuration is not valid appliance XML.');
            }
        } finally {
            libxml_clear_errors();
            libxml_use_internal_errors($errors);
        }
        $stamp = microtime(true);
        $backup = $this->path . '.' . $backupTag . '.' . gmdate('Ymd_His', (int)$stamp)
            . sprintf('_%06d_', (int)(($stamp - floor($stamp)) * 1000000)) . bin2hex(random_bytes(6));
        $result = $this->writer->commit([$backup => $this->before], [$this->path => $this->version]);
        if ($result['status'] !== 'ok') {
            throw new \RuntimeException($result['message']);
        }
        // Keep the core's open inode and persistence hooks; never rename over config.xml.
        $root = dom_import_simplexml($this->core->object());
        while ($root->firstChild !== null) {
            $root->removeChild($root->firstChild);
        }
        foreach ($doc->documentElement->childNodes as $child) {
            $root->appendChild($root->ownerDocument->importNode($child, true));
        }
        $version = $this->save();
        $result = $this->writer->commit([$backup . '.revision' => $version]);
        if ($result['status'] !== 'ok') {
            throw new \RuntimeException($result['message']);
        }
        return ['version' => $version, 'backup' => $backup];
    }

    public function rollback(string $backup): array
    {
        if (dirname($backup) !== dirname($this->path)
            || !preg_match('/^' . preg_quote(basename($this->path), '/') . '\.mihomo-bak\.[0-9]{8}_[0-9]{6}_[0-9]{6}_[a-f0-9]{12}$/D', basename($backup))
            || is_link($backup) || !is_file($backup)
            || !is_file($backup . '.revision')
            || !hash_equals($this->version, (string)file_get_contents($backup . '.revision'))) {
            throw new \RuntimeException('Configuration changed since this backup; automatic rollback refused.');
        }
        return $this->commit((string)file_get_contents($backup));
    }

    /** Extend a rollback baseline only across a revision-checked API stage. */
    public function advanceBackup(?string $backup, string $version): void
    {
        if ($backup === null) {
            return;
        }
        if (!str_starts_with($backup, $this->path . '.mihomo-bak.')
            || dirname($backup) !== dirname($this->path)
            || !is_file($backup . '.revision')
            || !hash_equals($this->version, (string)file_get_contents($backup . '.revision'))) {
            throw new \RuntimeException('Network backup revision changed.');
        }
        $result = $this->writer->commit([$backup . '.revision' => $version]);
        if ($result['status'] !== 'ok') {
            throw new \RuntimeException($result['message']);
        }
    }
}
