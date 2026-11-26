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
# Validate the launcher graph as well as file hashes. This catches missing scripts and invalid batch labels.
$launcherPath = Join-Path $PSScriptRoot 'LocalAI-Studio.bat'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    Write-Host 'MISSING: LocalAI-Studio.bat (the only launcher)' -ForegroundColor Red
    $bad++
} else {
    $launcherText = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
    if ([regex]::IsMatch($launcherText, '(?im)^\s*call\s+:')) {
        Write-Host 'INVALID: launcher uses nested CALL :label batch subroutines.' -ForegroundColor Red
        $bad++
    }
    $labels = @{}
    foreach ($match in [regex]::Matches($launcherText, '(?im)^\s*:([A-Z0-9_-]+)\s*
)) {
        $labels[$match.Groups[1].Value.ToUpperInvariant()] = $true
    }
    foreach ($match in [regex]::Matches($launcherText, '(?im)\bgoto\s+:?([A-Z0-9_-]+)')) {
        $target = $match.Groups[1].Value.ToUpperInvariant()
        if (-not $labels.ContainsKey($target)) {
            Write-Host "INVALID: launcher jumps to missing batch label: $target" -ForegroundColor Red
            $bad++
        }
    }
    foreach ($match in [regex]::Matches($launcherText, '(?i)-File\s+"%~dp0([^"]+)"')) {
        $scriptName = $match.Groups[1].Value
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $scriptName) -PathType Leaf)) {
            Write-Host "MISSING LAUNCHER DEPENDENCY: $scriptName" -ForegroundColor Red
            $bad++
        }
    }
    $requiredRuntimeFiles = @(
        'REPAIR-AND-RESUME.ps1',
        'START-CHAT.ps1',
        'STOP-CHAT.ps1',
        'CHECK-LOCALAI.ps1',
        'VERIFY-MODEL.ps1',
        'IMPORT-FILTERS.ps1',
        'RESTORE-OPENWEBUI-STYLE.ps1',
        'TEST-FILTERS.py',
        'Filters\01-Trusted-Content-Guard.py',
        'Filters\02-Accuracy-Thinking.py',
        'Filters\03-Selective-Self-Review.py'
    )
    foreach ($requiredFile in $requiredRuntimeFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $requiredFile) -PathType Leaf)) {
            Write-Host "MISSING REQUIRED PROJECT FILE: $requiredFile" -ForegroundColor Red
            $bad++
        }
    }
    if ($bad -eq 0) {
        Write-Host '[OK] Launcher labels and all referenced runtime files are valid.' -ForegroundColor Green
    }
}

Write-Host ("Package verification: OK={0} BAD={1}" -f $ok,$bad)
if ($bad -gt 0) { exit 1 }
Write-Host 'PACKAGE_INTEGRITY: SUCCESS' -ForegroundColor Green
exit 0
