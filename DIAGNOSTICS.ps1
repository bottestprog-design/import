# LocalAI Studio diagnostic. Read-only except for writing its own report.
$ErrorActionPreference = 'Continue'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Logs = Join-Path $Root 'Logs'
$Python = Join-Path $Platform '.venv\Scripts\python.exe'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Report = Join-Path $Logs ('diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$Lines = New-Object System.Collections.Generic.List[string]
$script:Problems = 0

function Add-Check([string]$Name,[bool]$Ok,[string]$Detail) {
    $state = if ($Ok) { 'PASS' } else { 'CHECK' }
    if (-not $Ok) { $script:Problems++ }
    $line = "[$state] $Name : $Detail"
    $null = $script:Lines.Add($line)
    Write-Host $line -ForegroundColor $(if ($Ok) { 'Green' } else { 'Yellow' })
}
$null = $Lines.Add('LOCALAI STUDIO READ-ONLY DIAGNOSTIC')
$null = $Lines.Add("Generated: $(Get-Date -Format o)")
$null = $Lines.Add('No models, settings, credentials, databases or services are changed.')
Write-Host 'LOCALAI STUDIO - DIAGNOSTICS (READ ONLY)' -ForegroundColor Cyan

try {
    $version = Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 5
    Add-Check 'Ollama API' $true $version.version
    $tags = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 12
    $model = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*' -or $_.name -like 'qwen3.5:9b-q4_K_M*' } | Select-Object -First 1
    Add-Check 'Existing Qwen model' ([bool]$model) $(if ($model) { "$($model.name) / $([math]::Round($model.size/1GB,2)) GB" } else { 'Not found; no model download attempted' })
} catch { Add-Check 'Ollama API/model' $false $_.Exception.Message }

Add-Check 'Platform folder' (Test-Path -LiteralPath $Platform -PathType Container) $Platform
Add-Check 'Project Python' (Test-Path -LiteralPath $Python -PathType Leaf) $Python
$OpenWebUI = Join-Path $Platform '.venv\Scripts\open-webui.exe'
Add-Check 'Open WebUI launcher' (Test-Path -LiteralPath $OpenWebUI -PathType Leaf) $OpenWebUI
if (Test-Path -LiteralPath $Python -PathType Leaf) {
    $probe = 'import sys,importlib.metadata as m; names=("open-webui","av","faster-whisper"); installed={d.metadata["Name"].lower() for d in m.distributions()}; print("PYTHON="+sys.version.split()[0]); [print(n.upper().replace("-","_")+"="+(m.version(n) if n in installed else "MISSING")) for n in names]'
    $output = @(& $Python -c $probe 2>&1)
    $rc = $LASTEXITCODE
    Add-Check 'Python package probe' ($rc -eq 0) ($output -join ' ')
}
try {
    Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 4 | Out-Null
    Add-Check 'Open WebUI readiness' $true '127.0.0.1:8080/ready'
} catch { Add-Check 'Open WebUI readiness' $false $_.Exception.Message }

$ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    $saved = Join-Path $Platform 'ffmpeg-path.txt'
    if (Test-Path -LiteralPath $saved) {
        $savedPath = (Get-Content -LiteralPath $saved -Raw).Trim()
        if (Test-Path -LiteralPath $savedPath -PathType Leaf) { $ffmpeg = [pscustomobject]@{ Source = $savedPath } }
    }
}
Add-Check 'FFmpeg' ([bool]$ffmpeg) $(if ($ffmpeg) { $ffmpeg.Source } else { 'Not found; text chat remains available' })
$whisperRoot = Join-Path $Platform 'Data\cache\whisper\models'
$whisperFile = if (Test-Path -LiteralPath $whisperRoot) { Get-ChildItem -LiteralPath $whisperRoot -Filter 'model.bin' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
Add-Check 'Whisper model cache' ($null -ne $whisperFile) $(if ($whisperFile) { $whisperRoot } else { 'Not found; speech-to-text may need a first-use download' })
foreach ($name in @('01-Trusted-Content-Guard.py','02-Accuracy-Thinking.py','03-Selective-Self-Review.py')) {
    $path = Join-Path $Platform ('Filters\' + $name)
    Add-Check ("Filter " + $name) (Test-Path -LiteralPath $path -PathType Leaf) $path
}
try {
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'" -ErrorAction Stop
    $free = [math]::Round($drive.FreeSpace/1GB,1)
    Add-Check 'D: free space' ($free -ge 10) "$free GB"
} catch { Add-Check 'D: free space' $false $_.Exception.Message }

$null = $Lines.Add('')
$null = $Lines.Add("Checks needing attention: $Problems")
$Lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host ("Report: " + $Report) -ForegroundColor Cyan
Write-Host 'No Ollama/Qwen files, database, configuration or secrets were changed.' -ForegroundColor Green
if ($Problems -gt 0) { exit 1 }
exit 0
