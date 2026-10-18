# os-mihomo —— 应用/回滚插件中文词条
#
#   .\tools\i18n.ps1            # 应用（备份 + 合并 + 校验 + 只增不改校验）
#   .\tools\i18n.ps1 -Rollback  # 还原到最近一次备份
#   .\tools\i18n.ps1 -Status    # 查看状态
#
# 说明：OPNsense 用单一 gettext 域，插件中文只能合并进
#       /usr/local/share/locale/<locale>/LC_MESSAGES/OPNsense.mo。
#       本步骤是**显式**的，不在 deploy.ps1 里自动执行（避免动系统文件）。
param(
    [switch]$Rollback,
    [switch]$Status,
    [string]$Locale = 'zh_CN'
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root

$action = if ($Rollback) { 'rollback' } elseif ($Status) { 'status' } else { 'apply' }

Write-Host "`n=== 推送词条与工具 ===" -ForegroundColor Cyan
& .\tools\remote.ps1 -Push ".\locales\zh_CN.po" -PushTo "/tmp/os-mihomo-zh_CN.po" 2>&1 | Select-Object -Last 1
& .\tools\remote.ps1 -Push ".\tools\mo_editor.py" -PushTo "/tmp/os-mihomo-mo_editor.py" 2>&1 | Select-Object -Last 1

Write-Host "`n=== 执行 $action（locale=$Locale）===" -ForegroundColor Cyan
& .\tools\remote.ps1 -Script .\scripts\i18n_apply.sh -ScriptArgs "$action $Locale" 2>&1
$rc = $LASTEXITCODE

if ($action -eq 'apply' -and $rc -eq 0) {
    Write-Host "`n=== 让 php-cgi 重新加载词库（重启 WebGUI）===" -ForegroundColor Cyan
    # 注意：WebGUI 用的是 /usr/local/etc/lighttpd_webgui/lighttpd.conf 那个实例，
    # 由 /usr/local/etc/rc.restart_webgui 管理；`service lighttpd` 管的是别的实例。
    # php-cgi 会在进程内缓存 gettext 词库，因此必须重启才会生效。
    & .\tools\remote.ps1 -Cmd "/usr/local/etc/rc.restart_webgui" 2>&1 | Select-Object -First 3
    Start-Sleep -Seconds 4
    & .\tools\remote.ps1 -Cmd "curl -sk -o /dev/null -w 'webgui: %{http_code}\n' https://127.0.0.1/; ps -ax -o pid,etime,command | grep '[p]hp-cgi' | head -2" 2>&1 | Select-Object -First 4
}

Write-Host "`n退出码: $rc" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })
Pop-Location
exit $rc
