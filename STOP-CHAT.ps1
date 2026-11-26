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
$commandLine = [string]$proc.CommandLine
$actualPath = if ($actual) { [IO.Path]::GetFullPath($actual) } else { '' }
$expectedPath = [IO.Path]::GetFullPath($ExpectedExe)
$expectedCommand = ($commandLine -match '(?i)(^|\s)serve(\s|$)' -and
    $commandLine -match '(?i)--host\s+127\.0\.0\.1' -and
    $commandLine -match '(?i)--port\s+8080')
if ($actualPath -ne $expectedPath -or -not $expectedCommand) {
    throw "PID $targetPid is not the tracked LocalAI Open WebUI server on 127.0.0.1:8080. Refusing to stop it. Executable: $actual; command: $commandLine"
}
Stop-Process -Id $targetPid -Force
Remove-Item $PidFile -Force
Write-Host 'Only the tracked Open WebUI process was stopped. Ollama and model files were not touched.' -ForegroundColor Green
