# os-mihomo —— 回滚演练（两阶段，已针对 Windows OpenSSH 抖动做最小化 SSH 往返）
#
#   阶段一：快照 LATEST → 暂存配置 → 从旧备份集回滚代码 → 校验（与备份逐字节比对 + 页面可用性）
#   中间  ：重新部署最新版（= 文档里的升级路径）
#   阶段二：校验回到 LATEST → 恢复配置数据 → 清理 → 打印结果
param(
    [switch]$SkipRedeploy
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root

Write-Host "`n准备：推送受管文件清单" -ForegroundColor DarkCyan
& .\tools\remote.ps1 -Push ".\tests\managed_files.txt" -PushTo "/tmp/mihomo-managed-files.txt" 2>&1 | Select-Object -Last 1

Write-Host "`n########## 阶段一：回滚 ##########" -ForegroundColor Cyan
& .\tools\remote.ps1 -Script .\scripts\rollback_phase1.sh 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "阶段一失败，终止" -ForegroundColor Red; Pop-Location; exit 1 }

if (-not $SkipRedeploy) {
    Write-Host "`n########## 中间：重新部署最新版 ##########" -ForegroundColor Cyan
    & .\tools\deploy.ps1 2>&1 | Select-String -Pattern 'syntax errors|actions:|deploy done|kept existing'
} else {
    Write-Host "`n（已跳过重新部署，仅保留回滚状态）" -ForegroundColor Yellow
    Pop-Location
    exit 0
}

Write-Host "`n########## 阶段二：校验与恢复 ##########" -ForegroundColor Cyan
& .\tools\remote.ps1 -Script .\scripts\rollback_phase2.sh 2>&1
$rc = $LASTEXITCODE

Write-Host "`n########## 演练退出码: $rc ##########" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })
Pop-Location
exit $rc
