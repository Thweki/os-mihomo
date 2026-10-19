#!/usr/local/bin/php
<?php
/*
 * os-mihomo —— 把运行配置里的 DNS 上游同步回 WebUI 模型
 *
 * 背景：通过 scripts/dns_global_proxy.php 在命令行改了 config.yaml 之后，
 * 页面模型（config.xml 的 <OPNsense><mihomo><dns><upstream>）还是旧值。
 * 这里用标准模型序列化把模型同步到当前文件内容，避免用户打开页面后
 * 误点「应用」把旧的分流配置写回去。
 *
 * 只写插件自己的 <OPNsense><mihomo> 节点；写前备份 config.xml。
 *
 * 用法：tools/remote.ps1 -Push scripts/dns_sync_model.php -PushTo /tmp/dns_sync_model.php
 *       tools/remote.ps1 -Cmd "/usr/local/bin/php /tmp/dns_sync_model.php"
 */

$config = require('/usr/local/opnsense/mvc/app/config/config.php');
require('/usr/local/opnsense/mvc/app/config/loader.php');

use OPNsense\Mihomo\Config as MihomoConfig;

$mdl = new \OPNsense\Mihomo\Mihomo();
$before = (string)$mdl->dns->upstream;
$after = MihomoConfig::dnsUpstreamBlock();
if ($before === $after) {
    echo "Model DNS upstream already up to date.\n";
    exit(0);
}

$backupDir = '/usr/local/opnsense/_bak/os-mihomo/model-sync-' . date('Ymd_His');
if (!is_dir($backupDir) && !mkdir($backupDir, 0700, true)) {
    fwrite(STDERR, "Unable to create backup directory.\n");
    exit(3);
}
if (!copy('/conf/config.xml', $backupDir . '/config.xml')) {
    fwrite(STDERR, "Unable to back up config.xml.\n");
    exit(3);
}

$mdl->dns->upstream = $after;
$mdl->serializeToConfig();
\OPNsense\Core\Config::getInstance()->save();

$check = new \OPNsense\Mihomo\Mihomo();
if ((string)$check->dns->upstream !== $after) {
    fwrite(STDERR, "Model write verification failed; restore from $backupDir/config.xml\n");
    exit(1);
}

exec('diff -u ' . escapeshellarg($backupDir . '/config.xml') . ' /conf/config.xml', $diff, $rc);
echo "Model updated (backup $backupDir/config.xml).\n";
if ($rc !== 0) {
    echo "diff summary (first 40 changed lines):\n";
    $shown = 0;
    foreach ($diff as $line) {
        if (preg_match('/^[+-]/', $line) && !preg_match('/^(\+\+\+|---)/', $line)) {
            echo $line . "\n";
            if (++$shown >= 40) {
                break;
            }
        }
    }
}
