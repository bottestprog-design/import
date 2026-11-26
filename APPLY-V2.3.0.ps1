$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Join-Path $root 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'MANIFEST-SHA256.txt is missing. Extract the complete package first.' }
Write-Host 'LOCALAI STUDIO v2.3.0 - SAFE PACKAGE PATCH' -ForegroundColor Cyan
$oldLines = @(Get-Content -LiteralPath $manifest -Encoding ASCII | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+(.+)$' })
if ($oldLines.Count -lt 20) { throw 'Original package manifest is incomplete.' }
foreach ($line in $oldLines) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "Invalid manifest line: $line" }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2].Trim().TrimStart('*')
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing original package file: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Original package integrity mismatch: $relative. Re-extract the original package." }
}
Write-Host "[OK] Original package verified ($($oldLines.Count) files)." -ForegroundColor Green
function Replace-Once([string]$RelativePath,[string]$OldText,[string]$NewText,[string]$Description) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required patch target missing: $RelativePath" }
    $content = [IO.File]::ReadAllText($path)
    $crlf = ([string][char]13) + ([string][char]10)
    $lf = [string][char]10
    $normalized = $content.Replace($crlf,$lf).Replace([string][char]13,$lf)
    $oldNormalized = $OldText.Replace($crlf,$lf).Replace([string][char]13,$lf)
    $newNormalized = $NewText.Replace($crlf,$lf).Replace([string][char]13,$lf)
    if ($normalized.Contains($newNormalized)) {
        Write-Host "[OK] Already applied: $Description" -ForegroundColor DarkGreen
        return
    }
    if (-not $normalized.Contains($oldNormalized)) { throw "Patch marker mismatch in $RelativePath ($Description). No install was started." }
    $updated = $normalized.Replace($oldNormalized,$newNormalized)
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($path,$updated,$encoding)
    Write-Host "[OK] Applied: $Description" -ForegroundColor Green
}
Replace-Once 'INSTALL-PLATFORM.ps1' @'
    $proc.WaitForExit()
    $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
'@ @'
    $proc.WaitForExit()
    $proc.Refresh()
    $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
'@ 'Refresh process state after WaitForExit'
Replace-Once 'INSTALL-PLATFORM.ps1' @'
    $exitCode = [int]$proc.ExitCode
    if ($exitCode -eq 0) { Write-Host "[OK] $Label completed successfully." -ForegroundColor Green }
'@ @'
    $exitCode = $null
    try {
        $rawExitCode = $proc.ExitCode
        if ($null -ne $rawExitCode) { $exitCode = [int]$rawExitCode }
    } catch { $exitCode = $null }
    if ($null -eq $exitCode) {
        throw "$Label finished but Windows did not expose ExitCode after WaitForExit. Logs: $outFile | $errFile"
    }
    if ($exitCode -eq 0) { Write-Host "[OK] $Label completed successfully." -ForegroundColor Green }
'@ 'Validate native process ExitCode'
Replace-Once 'REPAIR-AND-RESUME.ps1' @'
        $proc.Refresh()
        $out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
'@ @'
        $proc.WaitForExit()
        $proc.Refresh()
        $out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
'@ 'Wait and refresh repair probes before reading process output'
Replace-Once 'REPAIR-AND-RESUME.ps1' @'
        return [pscustomobject]@{ExitCode=[int]$proc.ExitCode;StdOut=$out;StdErr=$err;TimedOut=$false}
'@ @'
        $exitCode = $null
        try { $rawExitCode = $proc.ExitCode; if ($null -ne $rawExitCode) { $exitCode = [int]$rawExitCode } } catch { $exitCode = $null }
        if ($null -eq $exitCode) {
            return [pscustomobject]@{ExitCode=$null;StdOut=$out;StdErr=($err + [Environment]::NewLine + 'Windows did not expose ExitCode after WaitForExit.');TimedOut=$false}
        }
        return [pscustomobject]@{ExitCode=$exitCode;StdOut=$out;StdErr=$err;TimedOut=$false}
'@ 'Reject unavailable repair-probe exit codes explicitly'
Replace-Once 'REPAIR-AND-RESUME.ps1' @'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$active=@(Get-ActiveInstallProcesses)
'@ @'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
foreach ($maintenanceFile in @('DIAGNOSTICS.ps1','DIAGNOSTICS.bat','BACKUP-LOCALAI.ps1','BACKUP-LOCALAI.bat')) {
    $source = Join-Path $PSScriptRoot $maintenanceFile
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Maintenance file missing from package: $maintenanceFile" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $Platform $maintenanceFile) -Force
}
$active=@(Get-ActiveInstallProcesses)
'@ 'Deploy diagnostics and backup even when repair exits early'
Replace-Once 'START-CHAT.ps1' @'
$env:DEFAULT_MODEL_METADATA = '{"capabilities":{"vision":true,"web_search":true}}'
'@ @'
$env:DEFAULT_MODEL_METADATA = '{"capabilities":{"web_search":true}}'
'@ 'Do not force an unsupported vision capability'
Replace-Once 'INSTALL-PLATFORM.ps1' @'
    Copy-Item (Join-Path $PSScriptRoot 'FILTER-IMPORT-GUIDE-AR.md') (Join-Path $Platform 'FILTER-IMPORT-GUIDE-AR.md') -Force
'@ @'
    Copy-Item (Join-Path $PSScriptRoot 'FILTER-IMPORT-GUIDE-AR.md') (Join-Path $Platform 'FILTER-IMPORT-GUIDE-AR.md') -Force
    Copy-Item (Join-Path $PSScriptRoot 'DIAGNOSTICS.ps1') (Join-Path $Platform 'DIAGNOSTICS.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'DIAGNOSTICS.bat') (Join-Path $Platform 'DIAGNOSTICS.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'BACKUP-LOCALAI.ps1') (Join-Path $Platform 'BACKUP-LOCALAI.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'BACKUP-LOCALAI.bat') (Join-Path $Platform 'BACKUP-LOCALAI.bat') -Force
'@ 'Install maintenance tools with the platform'
$versionContent = @'
LocalAI Studio Complete v2.3.0
Open WebUI target: 0.13.5
Reuse existing Ollama/Qwen installation only; never reinstall or pull model blobs.
'@
$encoding = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText((Join-Path $root 'VERSION.txt'),$versionContent,$encoding)
$additional = @(
    'APPLY-V2.3.0.ps1','ONE-CLICK-SETUP.bat',
    'DIAGNOSTICS.ps1','DIAGNOSTICS.bat',
    'BACKUP-LOCALAI.ps1','BACKUP-LOCALAI.bat',
    'README-AR-V2.3.0.md','CHANGELOG-AR-V2.3.0.md'
)
$paths = New-Object System.Collections.Generic.List[string]
foreach ($line in $oldLines) {
    if ($line -match '^[0-9a-fA-F]{64}\s+(.+)$') {
        $relative = $matches[1].Trim().TrimStart('*')
        if (-not $paths.Contains($relative)) { $null = $paths.Add($relative) }
    }
}
foreach ($relative in $additional) {
    if (-not $paths.Contains($relative)) { $null = $paths.Add($relative) }
}
$newManifest = New-Object System.Collections.Generic.List[string]
foreach ($relative in $paths) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Cannot sign missing package file: $relative" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $null = $newManifest.Add("$hash  $relative")
}
Set-Content -LiteralPath $manifest -Value $newManifest -Encoding ASCII
foreach ($line in Get-Content -LiteralPath $manifest -Encoding ASCII) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "Invalid generated manifest line: $line" }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2].Trim()
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing signed file: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Generated manifest verification failed: $relative" }
}
Write-Host "PATCH_APPLIED: SUCCESS ($($newManifest.Count) manifest entries)" -ForegroundColor Green
exit 0
