$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$targetScript = Join-Path $packageRoot 'ONE-TIME-SETUP.ps1'
$manifest = Join-Path $packageRoot 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) { throw 'ONE-TIME-SETUP.ps1 not found. Extract this fix into the original LocalAI-OneClick package folder and overwrite the old file.' }
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'MANIFEST-SHA256.txt not found. You are not inside the extracted original package folder.' }
$lines = @(Get-Content -LiteralPath $manifest -Encoding UTF8)
$found = $false
$hash = (Get-FileHash -LiteralPath $targetScript -Algorithm SHA256).Hash.ToLowerInvariant()
$newLines = foreach ($line in $lines) {
    if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and [IO.Path]::GetFileName($matches[2]) -ieq 'ONE-TIME-SETUP.ps1') {
        $found = $true
        "$hash  ONE-TIME-SETUP.ps1"
    } else { $line }
}
if (-not $found) { $newLines += "$hash  ONE-TIME-SETUP.ps1" }
Set-Content -LiteralPath $manifest -Value $newLines -Encoding ASCII

# Verify all entries after updating the one intentional replacement.
$checked = 0; $bad = @()
foreach ($line in Get-Content -LiteralPath $manifest -Encoding ASCII) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { continue }
    $expected = $matches[1].ToLowerInvariant(); $relative = $matches[2].Trim().TrimStart('*')
    $path = Join-Path $packageRoot $relative
    $checked++
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bad += "MISSING $relative"; continue }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { $bad += "HASH MISMATCH $relative" }
}
if ($bad.Count -gt 0) {
    $bad | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw 'Package verification still fails. Re-extract the original package and the fix, keeping both in the same folder.'
}
Write-Host "FIX APPLIED. Package integrity verified ($checked files)." -ForegroundColor Green
Write-Host 'Now run the original ONE-TIME-SETUP.bat once.' -ForegroundColor Cyan
