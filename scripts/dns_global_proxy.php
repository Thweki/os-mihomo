#!/usr/local/bin/php
<?php
/*
 * os-mihomo —— 全局 DNS 走代理（无按距离/geosite 分流）
 *
 * 目标：
 *   · 客户端 DNS 全部按 mihomo 路由规则走代理（Cloudflare DoH，#RULES）
 *   · 不使用国内 DNS 解析客户端域名
 *   · 代理节点域名用 DNSPod DoH（IP 直连）做 bootstrap —— 仅此一处直连
 *   · 不使用 nameserver-policy / geosite 分流
 *
 * 写入方式：复用 config_apply.php（mihomo -t + 时间戳备份 + 原子替换），
 * 然后重启服务；DNS 查询失败时自动还原最近一次备份。
 *
 * 用法：tools/remote.ps1 -Push scripts/dns_global_proxy.php -PushTo /tmp/dns_global_proxy.php
 *       tools/remote.ps1 -Cmd "/usr/local/bin/php /tmp/dns_global_proxy.php"
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

function run(string $cmd): array
{
    $out = [];
    $rc = 0;
    exec($cmd . ' 2>&1', $out, $rc);
    return [$rc, implode("\n", $out)];
}

$before = Config::rawText();
$after = Config::applyDnsUpstreamBlock($before, $fragment);
if ($after === $before) {
    echo "DNS upstream block is already up to date.\n";
} else {
    $staging = tempnam('/tmp', 'mihomo-');
    if ($staging === false) {
        fwrite(STDERR, "Unable to create staging file.\n");
        exit(2);
    }
    chmod($staging, 0600);
    file_put_contents($staging, $after);
    [$rc, $out] = run('/usr/local/bin/php /usr/local/opnsense/scripts/mihomo/config_apply.php install ' . escapeshellarg($staging));
    echo $out . "\n";
    if ($rc !== 0) {
        fwrite(STDERR, "Configuration was not installed (rc=$rc); the original file is unchanged.\n");
        exit($rc);
    }
}

echo "Restarting mihomo...\n";
[$rc, $out] = run('configctl mihomo restart');
echo $out . "\n";
sleep(6);

/* ---- 验证：服务 + 本机 DNS 查询 ---- */
[$svcRc, $svcOut] = run('service mihomo status');
[$dnsRc, $dnsOut] = run('/usr/local/bin/drill @127.0.0.1 -p 1053 example.com A');
$dnsOk = $dnsRc === 0 && str_contains($dnsOut, 'NOERROR');
echo "service: " . trim($svcOut) . "\n";
echo "dns query: " . ($dnsOk ? 'OK' : 'FAILED') . "\n";
if (!$dnsOk) {
    echo $dnsOut . "\n";
}

/* ---- 验证：日志里 DNS 是否真的走了 US-EXIT ---- */
[$logRc, $logOut] = run("grep -E '1\\.1\\.1\\.1:443|1\\.0\\.0\\.1:443' /var/log/mihomo.log | tail -5");
if (trim($logOut) !== '') {
    echo "recent DNS connections:\n" . $logOut . "\n";
}

if (!$dnsOk) {
    echo "DNS query failed; rolling back...\n";
    [$bRc, $bOut] = run('ls -1t /usr/local/etc/mihomo/config.yaml.bak.* 2>/dev/null | head -1');
    $backup = trim($bOut);
    if ($backup !== '') {
        [$rRc, $rOut] = run('/usr/local/bin/php /usr/local/opnsense/scripts/mihomo/config_apply.php restore ' . escapeshellarg($backup));
        echo $rOut . "\n";
        run('configctl mihomo restart');
    } else {
        echo "No backup found; manual attention required.\n";
    }
    exit(1);
}

echo "Done. DNS follows the routing rules (MATCH -> proxy group); bootstrap uses DNSPod DoH only.\n";
