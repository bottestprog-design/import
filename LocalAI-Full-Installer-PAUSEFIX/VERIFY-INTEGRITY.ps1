$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Manifest = Join-Path $Root 'MANIFEST-SHA256.txt'
if (-not (Test-Path $Manifest)) { throw 'MANIFEST-SHA256.txt is missing.' }
$lines = Get-Content -Path $Manifest -Encoding UTF8
$failed = @()
$checked = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^([A-Fa-f0-9]{64})  (.+)$') { $failed += "Malformed manifest line: $line"; continue }
    $expected = $Matches[1].ToUpperInvariant()
    $relative = $Matches[2].Replace('/', '\')
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $failed += "MISSING: $relative"; continue }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    $checked++
    if ($actual -ne $expected) { $failed += "HASH MISMATCH: $relative" }
}
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "Integrity check failed. Checked $checked files. Re-extract the archive from the original download."
}
Write-Host "Integrity OK: $checked files match MANIFEST-SHA256.txt" -ForegroundColor Green
