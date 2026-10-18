# Helper: run commands / copy files on the OPNsense appliance (OpenSSH + key auth).
#
# 注意：脚本传输曾因 PowerShell 5.1 的 Get-Content 默认按 ANSI 读取而损坏
# UTF-8 脚本内容（中文注释被转成乱码并破坏 shell 语法）。现在：
#   1) 显式以 UTF-8 读取；2) 传输后用 sha256 校验，不一致立即失败。
#
# Usage:
#   .\tools\remote.ps1 -Cmd "uname -a"
#   .\tools\remote.ps1 -Script .\scripts\recon.sh [-Args "--flag value"]
#   .\tools\remote.ps1 -Push local_path -PushTo /tmp/x
#   .\tools\remote.ps1 -Pull /tmp/x -PullTo .
param(
    [string]$Cmd,
    [string]$Script,
    [string]$Push,
    [string]$PushTo,
    [string]$Pull,
    [string]$PullTo,
    [string]$ScriptArgs
)

$ErrorActionPreference = 'Continue'
$TARGET = 'root@192.168.1.1'
$KEY = "$env:USERPROFILE\.ssh\opn_ed25519"
$KNOWN = "$env:USERPROFILE\.ssh\known_hosts_opn"
$SSH_OPTS = @('-i', $KEY, '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KNOWN", '-o', 'BatchMode=yes')
$SCP_OPTS = @('-i', $KEY, '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KNOWN", '-o', 'BatchMode=yes')

function Get-Sha256([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

if ($Cmd) {
    & ssh @SSH_OPTS $TARGET $Cmd 2>&1
    exit $LASTEXITCODE
}

if ($Script) {
    $tmp = Join-Path $env:TEMP ('opn_' + [guid]::NewGuid().ToString('N') + '.sh')
    $content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Script).Path, [System.Text.Encoding]::UTF8)
    if (-not $content.EndsWith("`n")) { $content += "`n" }
    $content = $content -replace "`r`n", "`n"    # normalize to LF

    # 安全护栏：脚本自身引用 /tmp/__remote.sh 会导致无限递归（2026-10-18 事故）
    if ($content -match '__remote\.sh') {
        Write-Host "REFUSED: script references /tmp/__remote.sh (would recurse infinitely): $Script" -ForegroundColor Red
        exit 3
    }

    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))

    & scp @SCP_OPTS $tmp "${TARGET}:/tmp/__remote.sh" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "scp failed ($LASTEXITCODE)" -ForegroundColor Red; exit $LASTEXITCODE }

    # 传输完整性校验：远端 sha256 必须与本地一致，否则拒绝执行（避免半损坏的脚本被跑起来）
    $localHash = Get-Sha256 $tmp
    $remoteHash = (& ssh @SSH_OPTS $TARGET "sha256 -q /tmp/__remote.sh" 2>&1 | Select-Object -First 1)
    if ($remoteHash -ne $localHash) {
        Write-Host "transfer integrity check FAILED" -ForegroundColor Red
        Write-Host "  local : $localHash"
        Write-Host "  remote: $remoteHash"
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        exit 1
    }

    & ssh @SSH_OPTS $TARGET "exec sh /tmp/__remote.sh $ScriptArgs" 2>&1
    $rc = $LASTEXITCODE
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    exit $rc
}

if ($Push) {
    $dest = if ($PushTo) { "${TARGET}:$PushTo" } else { $TARGET }
    & scp @SCP_OPTS -r $Push $dest 2>&1
    exit $LASTEXITCODE
}

if ($Pull) {
    $dest = if ($PullTo) { $PullTo } else { '.' }
    & scp @SCP_OPTS -r "${TARGET}:$Pull" $dest 2>&1
    exit $LASTEXITCODE
}

Write-Host "nothing to do"
