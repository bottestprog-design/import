$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$StoreFile = Join-Path $Root 'MODEL-STORE-PATH.txt'
$Models = if (Test-Path -LiteralPath $StoreFile) { (Get-Content -LiteralPath $StoreFile -Raw).Trim() } else { [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','User') }
if ($Models -match '^UNCONFIRMED') {
    throw 'Ollama model storage was not confirmed during recovery. Open Ollama > Settings > Model location, note the exact folder, then update D:\LocalAI\MODEL-STORE-PATH.txt before starting a new server. This safety check prevents an empty second model store.'
}
if (-not $Models) { $Models = Join-Path $env:USERPROFILE '.ollama\models' }
$env:OLLAMA_MODELS = $Models
$env:OLLAMA_HOST = '127.0.0.1:11434'
$env:OLLAMA_MAX_LOADED_MODELS = '1'
$env:OLLAMA_NUM_PARALLEL = '1'
$env:OLLAMA_KEEP_ALIVE = '10m'
$env:OLLAMA_NOPRUNE = '1'
$Candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
    (Join-Path $env:ProgramFiles 'Ollama\ollama.exe'),
    'C:\Program Files\Ollama\ollama.exe'
)
$Ollama = (Get-Command ollama.exe -ErrorAction SilentlyContinue).Source
if (-not $Ollama) { $Ollama = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1 }
if (-not $Ollama) { throw 'Ollama is not installed. Run 01-LocalAI-Engine\INSTALL-ENGINE.bat first.' }
$ready = $false
try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 2 | Out-Null; $ready = $true } catch {}
if (-not $ready) {
    Start-Process -FilePath $Ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 2 | Out-Null; $ready = $true; break } catch {}
    }
}
if (-not $ready) { throw 'Ollama did not start. Check %LOCALAPPDATA%\Ollama\server.log.' }
Write-Host 'Ollama is ready at http://127.0.0.1:11434' -ForegroundColor Green
