<?php
/* Minimal appliance boundary: a cached singleton, inode lock/reload, in-place save.
 * Fixtures run only against a temporary path supplied by the test harness.
 */
namespace OPNsense\Core;
class Config
{
    private static $instance;
    private $handle;
    private $xml;
    public static function getInstance()
    {
        return self::$instance ??= new self();
    }
    private function __construct()
    {
        $this->handle = fopen(getenv('NETWORK_FIXTURE') . '/config.xml', 'r+');
        $this->load();
    }
    private function load(): void
    {
        rewind($this->handle);
        $this->xml = simplexml_load_string(stream_get_contents($this->handle));
    }
    public function lock()
    {
        flock($this->handle, LOCK_EX);
        $this->load();
        return $this;
    }
    public function unlock(): void { flock($this->handle, LOCK_UN); }
    public function object() { return $this->xml; }
    public function __toString(): string { return $this->xml->asXML(); }
    public function save(): void
    {
        // Like core, save releases the inode lock but retains the cached object.
        flock($this->handle, LOCK_EX);
        rewind($this->handle);
        ftruncate($this->handle, 0);
        fwrite($this->handle, (string)$this);
        fflush($this->handle);
        $this->unlock();
    }
}
