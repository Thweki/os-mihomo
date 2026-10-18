# Compare the pre-existing plugin tree at the repo root with the upstream src/os-mihomo.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\17187\Documents\os-mihomo'
$up = Join-Path $root 'upstream\src\os-mihomo'

function Get-RelFiles($base) {
    Get-ChildItem -Recurse -File -LiteralPath $base | ForEach-Object {
        $_.FullName.Substring($base.Length + 1).Replace('\', '/')
    } | Sort-Object
}

$localFiles = Get-RelFiles $root | Where-Object { $_ -match '^(src|packaging|images)/' -or $_ -match '^(Makefile|build.sh|README\.md|README\.US\.md)$' }
$upFiles = Get-RelFiles $up

Write-Host "=== local-only files ==="
Compare-Object $localFiles $upFiles | Where-Object SideIndicator -eq '<=' | ForEach-Object { $_.InputObject }
Write-Host "=== upstream-only files ==="
Compare-Object $localFiles $upFiles | Where-Object SideIndicator -eq '=>' | ForEach-Object { $_.InputObject }
Write-Host "=== content diff (common files) ==="
foreach ($f in $localFiles) {
    if ($upFiles -contains $f) {
        $a = Join-Path $root $f
        $b = Join-Path $up $f
        $ha = (Get-FileHash $a -Algorithm SHA256).Hash
        $hb = (Get-FileHash $b -Algorithm SHA256).Hash
        if ($ha -ne $hb) { Write-Host "DIFF: $f" }
    }
}
Write-Host "=== done ==="
