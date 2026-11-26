$ErrorActionPreference = 'Stop'
$Platform = 'D:\LocalAI\Platform'
$PidFile = Join-Path $Platform 'open-webui.pid'
$ExpectedExe = Join-Path $Platform '.venv\Scripts\open-webui.exe'
if (-not (Test-Path $PidFile)) { Write-Host 'No tracked Open WebUI PID file. Nothing was stopped.' -ForegroundColor Yellow; exit 0 }
$raw = (Get-Content $PidFile -Raw).Trim()
$targetPid = 0
if (-not [int]::TryParse($raw,[ref]$targetPid)) { throw 'PID file is invalid; refusing to stop any process.' }
$proc = Get-CimInstance Win32_Process -Filter "ProcessId=$targetPid" -ErrorAction SilentlyContinue
if (-not $proc) { Remove-Item $PidFile -Force; Write-Host 'Tracked Open WebUI process is already closed.' -ForegroundColor Yellow; exit 0 }
$actual = [string]$proc.ExecutablePath
if (-not $actual -or [IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($ExpectedExe)) {
    throw "PID $targetPid is not the expected Open WebUI executable. Refusing to stop it. Actual path: $actual"
}
Stop-Process -Id $targetPid -Force
Remove-Item $PidFile -Force
Write-Host 'Only the tracked Open WebUI process was stopped. Ollama and model files were not touched.' -ForegroundColor Green
