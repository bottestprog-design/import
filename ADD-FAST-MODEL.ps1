$ErrorActionPreference = 'Stop'
$Api = 'http://127.0.0.1:11434'
$Model = 'qwen3.5:4b'
Write-Host 'OPTIONAL Qwen 3.5 4B ADD-ON' -ForegroundColor Cyan
Write-Host 'The existing Qwen 3.5 9B will not be deleted, renamed, replaced or re-downloaded.'
$tags = Invoke-RestMethod -Uri ($Api + '/api/tags') -TimeoutSec 10
$primary = @($tags.models | Where-Object { $_.name -like 'local-qwen35*' -or $_.name -like 'qwen3.5:9b*' })
if ($primary.Count -eq 0) { throw 'Existing Qwen 3.5 9B was not found; no download will start.' }
$existing = @($tags.models | Where-Object { $_.name -eq $Model -or $_.name -like 'qwen3.5:4b-*' })
if ($existing.Count -gt 0) { Write-Host "[OK] $($existing[0].name) already exists; no download needed."; exit 0 }
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
$free = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { 0 }
Write-Host "Detected RAM: $ram GB; free D: space: $free GB."
if ($ram -lt 12) { throw 'At least 12 GB system RAM is recommended for this optional model.' }
if ($free -lt 8) { throw 'At least 8 GB free disk space is required.' }
if ((Read-Host 'Type Y to explicitly approve qwen3.5:4b download') -notmatch '^(?i)y$') {
    Write-Host 'Cancelled; no model data was changed.' -ForegroundColor Yellow
    exit 0
}
$ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue
if (-not $ollama) {
    foreach ($candidate in @((Join-Path $env:ProgramFiles 'Ollama\ollama.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $ollama = [pscustomobject]@{Source=$candidate}; break }
    }
}
if (-not $ollama) { throw 'ollama.exe was not found; no download was started.' }
& $ollama.Source pull $Model
if ($LASTEXITCODE -ne 0) { throw "ollama pull failed with exit code $LASTEXITCODE." }
$after = Invoke-RestMethod -Uri ($Api + '/api/tags') -TimeoutSec 15
$verified = @($after.models | Where-Object { $_.name -eq $Model -or $_.name -like 'qwen3.5:4b-*' })
if ($verified.Count -eq 0) { throw 'Ollama did not report the model after pull.' }
Write-Host "[SUCCESS] Added $($verified[0].name); primary model remains $($primary[0].name)." -ForegroundColor Green
