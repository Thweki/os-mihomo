# 语法检查：webtest.ps1
$err = $null
$tok = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'C:\Users\17187\Documents\os-mihomo\tools\webtest.ps1',
    [ref]$tok,
    [ref]$err
) | Out-Null
if ($err.Count -eq 0) { 'webtest.ps1 语法 OK' } else { $err | ForEach-Object { $_.Message } }
