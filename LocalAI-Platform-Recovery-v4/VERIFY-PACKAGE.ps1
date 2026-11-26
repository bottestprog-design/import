$ErrorActionPreference = 'Stop'
$manifest = Join-Path $PSScriptRoot 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Write-Host 'MANIFEST-SHA256.txt is missing.' -ForegroundColor Red; exit 2 }
$bad = @(); $checked = 0
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) { $bad += "Invalid manifest line: $line"; continue }
    $expected = $parts[0].ToLowerInvariant()
    $relative = $parts[1].Replace('/', '\')
    $path = Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bad += "MISSING: $relative"; continue }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $checked++
    if ($actual -ne $expected) { $bad += "HASH MISMATCH: $relative" }
}
if ($bad.Count -gt 0) {
    $bad | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "PACKAGE INTEGRITY FAILED ($checked checked)." -ForegroundColor Red
    exit 1
}
Write-Host "PACKAGE INTEGRITY OK - $checked files verified." -ForegroundColor Green
exit 0
