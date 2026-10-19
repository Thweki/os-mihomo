#!/usr/local/bin/php
<?php
/*
 * os-mihomo —— 把全局 DNS 上游同步到订阅模板
 *
 * 只替换 template_config.yaml 里 dns: 内的 DNS 上游受管区块，
 * 其余内容（fake-ip 过滤、TUN、代理占位等）原样保留。
 * 模板含 `# __MIHOMO_PROXIES__` 占位，不能直接 mihomo -t；
 * 这里用「最小 DNS 配置」验证片段，变更前备份模板。
 *
 * 用法：tools/remote.ps1 -Push scripts/dns_sync_template.php -PushTo /tmp/dns_sync_template.php
 *       tools/remote.ps1 -Cmd "/usr/local/bin/php /tmp/dns_sync_template.php"
 */

require_once('/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php');

use OPNsense\Mihomo\Config;

$fragment = <<<'YAML'
default-nameserver:
  - 1.1.1.1
  - 8.8.8.8
nameserver:
  - https://1.1.1.1/dns-query#RULES
  - https://1.0.0.1/dns-query#RULES
proxy-server-nameserver:
  - https://1.12.12.12/dns-query
  - https://120.53.53.53/dns-query
respect-rules: true
YAML;

$path = '/usr/local/etc/mihomo/sub/template_config.yaml';
$before = (string)file_get_contents($path);
$after = Config::applyDnsUpstreamBlock($before, $fragment);
if ($after === $before) {
    echo "Template already up to date.\n";
    exit(0);
}

$tmp = tempnam('/tmp', 'mihomo-tpl-');
if ($tmp === false) {
    fwrite(STDERR, "Unable to create staging file.\n");
    exit(2);
}
chmod($tmp, 0600);
file_put_contents($tmp, $after);

/* 模板本身有代理占位，不能整体 -t；单独验证 DNS 片段 */
$indented = preg_replace('/^/m', '  ', $fragment);
$minimal = "dns:\n  enable: true\n  listen: 127.0.0.1:1053\n  enhanced-mode: redir-host\n  ipv6: false\n"
    . $indented . "\nproxies: []\n";
$check = tempnam('/tmp', 'mihomo-dns-');
chmod($check, 0600);
file_put_contents($check, $minimal);
exec('/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f ' . escapeshellarg($check) . ' 2>&1', $out, $rc);
@unlink($check);
if ($rc !== 0) {
    @unlink($tmp);
    fwrite(STDERR, "DNS fragment validation failed:\n" . implode("\n", $out) . "\n");
    exit(1);
}

$backup = $path . '.bak.' . date('Ymd_His');
if (!copy($path, $backup)) {
    @unlink($tmp);
    fwrite(STDERR, "Unable to back up the template.\n");
    exit(3);
}
chmod($backup, 0644);
chown($backup, 'root');
chgrp($backup, 'wheel');

exec('/usr/bin/install -m 0644 -o root -g wheel ' . escapeshellarg($tmp) . ' ' . escapeshellarg($path), $out2, $rc2);
@unlink($tmp);
if ($rc2 !== 0) {
    fwrite(STDERR, "Template install failed:\n" . implode("\n", $out2) . "\n");
    exit(3);
}

echo "Template updated (backup " . basename($backup) . ").\n";
echo "DNS fragment validation: OK\n";
