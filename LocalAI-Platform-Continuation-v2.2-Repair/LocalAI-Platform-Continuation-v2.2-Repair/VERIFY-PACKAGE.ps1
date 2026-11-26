$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host 'FAIL: MANIFEST-SHA256.txt is missing.' -ForegroundColor Red
    exit 2
}
$lines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') })
if ($lines.Count -lt 10) {
    Write-Host 'FAIL: Manifest is incomplete.' -ForegroundColor Red
    exit 2
}
$ok = 0
$bad = 0
foreach ($line in $lines) {
    if ($line -notmatch '^([0-9A-Fa-f]{64})\s+(.+)$') {
        Write-Host "BAD MANIFEST LINE: $line" -ForegroundColor Red
        $bad++
        continue
    }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2].Trim()
    if ($relative.StartsWith('*')) { $relative = $relative.Substring(1) }
    $path = Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "MISSING: $relative" -ForegroundColor Red
        $bad++
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Write-Host "HASH MISMATCH: $relative" -ForegroundColor Red
        $bad++
    } else {
        Write-Host "OK: $relative" -ForegroundColor Green
        $ok++
    }
}
Write-Host "`nPackage verification: OK=$ok BAD=$bad"
if ($bad -gt 0) { exit 1 }
Write-Host 'PACKAGE_INTEGRITY: SUCCESS' -ForegroundColor Green
exit 0
