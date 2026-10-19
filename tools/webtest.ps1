# os-mihomo —— 通过 HTTPS 端到端验证 WebGUI（登录 + 页面 + API）
#
#   .\tools\webtest.ps1              # 全部检查
#   .\tools\webtest.ps1 -PageOnly    # 只看页面
#   .\tools\webtest.ps1 -Post        # 额外测试会写数据的 POST 端点（默认跳过）
param(
    [switch]$PageOnly,
    [switch]$Post,
    [string]$BaseUrl = 'https://192.168.1.1'
)
$ErrorActionPreference = 'Continue'
$user = 'root'
$pass = $env:OPN_PW
if (-not $pass) { Write-Host "缺少 WebGUI 口令：$env:OPN_PW=..." -ForegroundColor Red; exit 2 }
$jar = Join-Path $env:TEMP ('opn_jar_' + [guid]::NewGuid().ToString('N') + '.txt')

function CallCurl([string[]]$argsList) {
    $out = & curl.exe -k -s -c $jar -b $jar @argsList 2>&1
    return ($out -join "`n")
}

# ---------------------------------------------------------------- 1. 登录
Write-Host "=== 1. 登录（含 CSRF）===" -ForegroundColor Cyan
$page = CallCurl @("$BaseUrl/index.php")
$csrfName = $null; $csrfValue = $null
if ($page -match '<input type="hidden" name="([^"]+)" value="([^"]+)"') {
    $csrfName = $matches[1]; $csrfValue = $matches[2]
    Write-Host ("  csrf field: {0}" -f $csrfName)
} else {
    Write-Host "  !! 未找到 CSRF 字段" -ForegroundColor Yellow
}

$form = "login=1&usernamefld=$user&passwordfld=$pass"
if ($csrfName) { $form += "&$([uri]::EscapeDataString($csrfName))=$([uri]::EscapeDataString($csrfValue))" }
$login = CallCurl @('-i', '-d', $form, "$BaseUrl/index.php")
$loginStatus = if ($login -match 'HTTP/\S+ (\d+)') { $matches[1] } else { '?' }
$loggedIn = -not ($login -match 'HTTP/\S+ 403')
Write-Host ("  status={0}  {1}" -f $loginStatus, $(if ($loggedIn) { 'OK' } else { 'FAILED' })) -ForegroundColor $(if ($loggedIn) { 'Green' } else { 'Red' })

# ---------------------------------------------------------------- 2. 页面
Write-Host "`n=== 2. 页面 ===" -ForegroundColor Cyan
$checks = @(
    @{ name = 'Overview   /ui/mihomo';              url = '/ui/mihomo';                must = 'proxy-groups'; expect = 200 },
    @{ name = 'Settings   /ui/mihomo/settings';     url = '/ui/mihomo/settings';       must = 'frm_Settings'; expect = 200 },
    @{ name = 'DNS tab    /ui/mihomo/settings';     url = '/ui/mihomo/settings';       must = 'dnsStatusTab'; expect = 200 },
    @{ name = 'Subscribe  /ui/mihomo/subscription'; url = '/ui/mihomo/subscription';   must = 'log-viewer';   expect = 200 },
    @{ name = 'Log        /ui/mihomo/log';          url = '/ui/mihomo/log';            must = 'log-source';   expect = 200 },
    @{ name = 'Legacy     /mihomo.php';             url = '/mihomo.php';               must = 'Location: /ui/mihomo'; expect = 302 }
)
$csrfToken = $null
foreach ($c in $checks) {
    $body = CallCurl @('-i', "$BaseUrl$($c.url)")
    $status = if ($body -match 'HTTP/\S+ (\d+)') { $matches[1] } else { '?' }
    $ok = ($status -eq "$($c.expect)") -and ($c.must -eq '' -or $body.Contains($c.must))
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}  (status={2}, expect={3})" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $c.name, $status, $c.expect) -ForegroundColor $color

    $phpErrors = $body -split "`r?`n" | Where-Object { $_ -match '\b(Fatal error|Parse error|Uncaught \w+|PHP Warning|PHP Notice)\b' }
    if ($phpErrors) {
        Write-Host "     !! 页面含 PHP 错误" -ForegroundColor Red
        $phpErrors | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" }
    }
    if ($csrfToken -eq $null -and $body -match 'X-CSRFToken", "([^"]+)"') { $csrfToken = $matches[1] }
}
if ($csrfToken) { Write-Host ("  ajax CSRF token captured: {0}…" -f $csrfToken.Substring(0, [Math]::Min(12, $csrfToken.Length))) }

if ($PageOnly) { Remove-Item -Force $jar -ErrorAction SilentlyContinue; exit 0 }

# ---------------------------------------------------------------- 3. API GET
Write-Host "`n=== 3. API（GET）===" -ForegroundColor Cyan
$apis = @(
    '/api/mihomo/service/status',
    '/api/mihomo/service/safety',
    '/api/mihomo/settings/get',
    '/api/mihomo/settings/dns_status',
    '/api/mihomo/settings/config_get',
    '/api/mihomo/subscription/get',
    '/api/mihomo/subscription/log',
    '/api/mihomo/log/tail?key=mihomo&lines=10',
    '/api/mihomo/dashboard/overview',
    '/api/mihomo/dashboard/proxies',
    '/api/mihomo/dashboard/connections'
)
foreach ($a in $apis) {
    $body = CallCurl @('-w', "`n__HTTP:%{http_code}", "$BaseUrl$a")
    $code = if ($body -match '__HTTP:(\d+)') { $matches[1] } else { '?' }
    $payload = (($body -replace '__HTTP:\d+', '') -split "`r?`n" | Where-Object { $_ -notmatch '^\s*$' } | Select-Object -First 1)
    if ($payload -eq $null) { $payload = '' }
    if ($payload.Length -gt 240) { $payload = $payload.Substring(0, 240) + '…' }
    $color = if ($code -eq '200') { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $code, $a) -ForegroundColor $color
    Write-Host ("        {0}" -f $payload)
}

# ---------------------------------------------------------------- 4. POST 测试
if ($Post) {
    Write-Host "`n=== 4. API（POST，只读/安全端点）===" -ForegroundColor Cyan
    $posts = @(
        @{ url = '/api/mihomo/service/safety';       body = '{"validate":0}';   desc = 'safety check' },
        @{ url = '/api/mihomo/dashboard/set_mode';   body = '{"mode":"rule"}';  desc = 'set mode (no-op when stopped)' },
        @{ url = '/api/mihomo/settings/config_test'; body = '{}';               desc = 'validate active config' },
        @{ url = '/api/mihomo/settings/import';      body = '{}';               desc = 'import settings from config.yaml' }
    )
    foreach ($p in $posts) {
        # JSON body 必须经文件传递：PowerShell 会吃掉命令行参数里的双引号
        $bodyFile = Join-Path $env:TEMP ('opn_body_' + [guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::WriteAllText($bodyFile, $p.body, (New-Object System.Text.UTF8Encoding($false)))
        $body = CallCurl @('-w', "`n__HTTP:%{http_code}", '-H', "X-CSRFToken: $csrfToken", '-H', 'Content-Type: application/json', '--data-binary', "@$bodyFile", "$BaseUrl$($p.url)")
        Remove-Item -Force $bodyFile -ErrorAction SilentlyContinue
        $code = if ($body -match '__HTTP:(\d+)') { $matches[1] } else { '?' }
        $payload = (($body -replace '__HTTP:\d+', '') -split "`r?`n" | Where-Object { $_ -notmatch '^\s*$' } | Select-Object -First 1)
        if ($payload -eq $null) { $payload = '' }
        if ($payload.Length -gt 240) { $payload = $payload.Substring(0, 240) + '…' }
        $color = if ($code -eq '200') { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}  — {2}" -f $code, $p.url, $p.desc) -ForegroundColor $color
        Write-Host ("        {0}" -f $payload)
    }
}

# ---------------------------------------------------------------- 5. 未授权
Write-Host "`n=== 5. 未授权访问检查（不带 cookie）===" -ForegroundColor Cyan
foreach ($u in @('/ui/mihomo', '/api/mihomo/service/status')) {
    $r = & curl.exe -k -s -o NUL -w '%{http_code}' "$BaseUrl$u" 2>&1
    Write-Host ("  {0} -> {1}" -f $u, ($r -join ''))
}

Remove-Item -Force $jar -ErrorAction SilentlyContinue
Write-Host "`n=== done ===" -ForegroundColor Cyan
