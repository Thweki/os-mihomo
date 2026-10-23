# 一键部署：本地净化 -> scp 暂存 -> 远端安全安装 -> 语法检查
#
#   .\tools\deploy.ps1              # 只装 WebUI / 脚本（不动内核二进制）
#   .\tools\deploy.ps1 -WithBinary  # 同时安装 mihomo 内核（首次需要）
param(
    [switch]$WithBinary,
    [switch]$UiOnly
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root

if ($UiOnly) {
    if ($WithBinary) { throw '-UiOnly cannot be combined with -WithBinary' }
    python tools/build_locales.py --check
    if ($LASTEXITCODE -ne 0) { throw 'Locale validation failed' }
    New-Item -ItemType Directory -Force logs | Out-Null
    tar -cf logs/ui-stage.tar -C src usr/local/opnsense/mvc/app/models/OPNsense/Mihomo usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo usr/local/opnsense/mvc/app/views/OPNsense/Mihomo usr/local/www/js/mihomo
    if ($LASTEXITCODE -ne 0) { throw 'UI archive failed' }
    & .\tools\remote.ps1 -Push logs/ui-stage.tar -PushTo /tmp/mihomo-ui-stage.tar
    if ($LASTEXITCODE -ne 0) { throw 'UI upload failed' }
    & .\tools\remote.ps1 -Cmd "mkdir -p /tmp/mihomo-stage/src && tar -xf /tmp/mihomo-ui-stage.tar -C /tmp/mihomo-stage/src"
    if ($LASTEXITCODE -ne 0) { throw 'UI staging failed' }
    & .\tools\remote.ps1 -Script scripts/deploy.sh -ScriptArgs '--ui-only'
    $result = $LASTEXITCODE
    Pop-Location
    exit $result
}

Write-Host "=== 1/4 净化源码（去 BOM / 统一 LF）===" -ForegroundColor Cyan
python tools\sanitize.py --write

Write-Host "`n=== 2/4 清理并重建远端暂存区 ===" -ForegroundColor Cyan
& .\tools\remote.ps1 -Cmd "rm -rf /tmp/mihomo-stage && mkdir -p /tmp/mihomo-stage"
if ($LASTEXITCODE -ne 0) { Write-Host "failed to prepare staging" -ForegroundColor Red; Pop-Location; exit 1 }

Write-Host "`n=== 3/4 上传源码树 ===" -ForegroundColor Cyan
& .\tools\remote.ps1 -Push ".\src" -PushTo "/tmp/mihomo-stage/"
if ($LASTEXITCODE -ne 0) { Write-Host "scp failed" -ForegroundColor Red; Pop-Location; exit 1 }

Write-Host "`n=== 3.5/4 上传测试用例 ===" -ForegroundColor Cyan
& .\tools\remote.ps1 -Cmd "mkdir -p /tmp/mihomo-stage/tests" | Out-Null
& .\tools\remote.ps1 -Push ".\tests" -PushTo "/tmp/mihomo-stage/" | Out-Null

Write-Host "`n=== 4/4 远端安装 ===" -ForegroundColor Cyan
$arg = if ($WithBinary) { " --with-binary" } else { "" }
& .\tools\remote.ps1 -Script ".\scripts\deploy.sh" -ScriptArgs $arg

Pop-Location
exit $LASTEXITCODE
