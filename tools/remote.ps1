# Helper: run commands / copy files on the OPNsense appliance (OpenSSH + key auth).
# Usage:
#   .\tools\remote.ps1 -Cmd "uname -a"
#   .\tools\remote.ps1 -Script .\scripts\recon.sh
#   .\tools\remote.ps1 -Push local_path -PushTo /tmp/x
#   .\tools\remote.ps1 -Pull /tmp/x -PullTo .
param(
    [string]$Cmd,
    [string]$Script,
    [string]$Push,
    [string]$PushTo,
    [string]$Pull,
    [string]$PullTo
)

$ErrorActionPreference = 'Continue'
$TARGET = 'root@192.168.1.1'
$KEY = "$env:USERPROFILE\.ssh\opn_ed25519"
$KNOWN = "$env:USERPROFILE\.ssh\known_hosts_opn"
$SSH_OPTS = @('-i', $KEY, '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KNOWN", '-o', 'BatchMode=yes')
$SCP_OPTS = @('-i', $KEY, '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KNOWN", '-o', 'BatchMode=yes')

if ($Cmd) {
    & ssh @SSH_OPTS $TARGET $Cmd 2>&1
    exit $LASTEXITCODE
}

if ($Script) {
    $tmp = Join-Path $env:TEMP ('opn_' + [guid]::NewGuid().ToString('N') + '.sh')
    $content = Get-Content -Raw -LiteralPath $Script
    $content = $content -replace "`r`n", "`n"   # normalize to LF
    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))
    & scp @SCP_OPTS $tmp "${TARGET}:/tmp/__remote.sh" 2>&1 | Out-Null
    & ssh @SSH_OPTS $TARGET "exec sh /tmp/__remote.sh" 2>&1
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
