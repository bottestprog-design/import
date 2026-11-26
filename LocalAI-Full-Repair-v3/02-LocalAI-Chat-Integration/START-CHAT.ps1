$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Venv = Join-Path $Platform '.venv'
$OpenWebUI = Join-Path $Venv 'Scripts\open-webui.exe'
$SecretPath = Join-Path $Platform 'webui_secret_key.txt'
if (-not (Test-Path $OpenWebUI)) { throw 'Open WebUI is not installed. Run INSTALL-CHAT-PLATFORM.bat first.' }
if (-not (Test-Path $SecretPath)) { throw 'WEBUI_SECRET_KEY is missing. Rerun INSTALL-CHAT-PLATFORM.bat.' }

# All services stay on loopback. No public/LAN listener is created.
$env:OLLAMA_BASE_URL = 'http://127.0.0.1:11434'
$env:DATA_DIR = $Data
$env:DEFAULT_MODELS = 'local-qwen35:latest'
$env:DEFAULT_LOCALE = 'ar'
$env:WEBUI_SECRET_KEY = (Get-Content $SecretPath -Raw).Trim()
$env:WHISPER_MODEL = 'small'
$env:HF_HOME = Join-Path $Data 'cache\huggingface'
$env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
$env:WHISPER_MODEL_DIR = Join-Path $Data 'cache\whisper\models'
$env:WHISPER_COMPUTE_TYPE = 'int8'
$env:WHISPER_MULTILINGUAL = 'true'
$env:WHISPER_VAD_FILTER = 'true'
$env:WHISPER_LANGUAGE = ''
$env:AUDIO_STT_ENGINE = ''
$env:AUDIO_TTS_ENGINE = ''
# Enable DDGS web search (bundled with non-slim Open WebUI) but ask before
# sending any query to an external search provider.
$env:ENABLE_WEB_SEARCH = 'true'
$env:ENABLE_API_KEYS = 'true'
$env:ENABLE_FUNCTIONS = 'true'
$env:UVICORN_WORKERS = '1'
$env:WEB_SEARCH_ENGINE = 'duckduckgo'
$env:DDGS_BACKEND = 'auto'
$env:ENABLE_WEB_SEARCH_CONFIRMATION = 'true'
$env:WEB_SEARCH_CONFIRMATION_CONTENT = 'سيتم إرسال عبارة البحث إلى مزود بحث خارجي. لا توافق إذا كانت العبارة تحتوي على كلمات مرور أو بيانات شخصية.'
$env:OMP_NUM_THREADS = '4'
$env:MKL_NUM_THREADS = '4'
$env:TOKENIZERS_PARALLELISM = 'false'
New-Item -ItemType Directory -Force -Path $Data, $env:WHISPER_MODEL_DIR, $env:HF_HOME, $env:HUGGINGFACE_HUB_CACHE | Out-Null

try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3 | Out-Null }
catch {
    $engineStart = Join-Path $Root 'START-ENGINE.ps1'
    if (-not (Test-Path $engineStart)) { throw 'Ollama is offline. Install package 01 or run D:\LocalAI\START-ENGINE.bat.' }
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $engineStart
        $engineStartExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($engineStartExit -ne 0) { throw "Could not start Ollama (exit code $engineStartExit)." }
}
try {
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
    if (-not ($tags.models | Where-Object { $_.name -like 'local-qwen35*' })) { throw 'The local-qwen35 model alias is missing. Run D:\LocalAI\01-LocalAI-Engine\INSTALL-ENGINE.bat from the extracted package.' }
} catch { throw "Ollama is not ready or local-qwen35 is missing: $($_.Exception.Message)" }

$existingListener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($existingListener) {
    Write-Host 'An app is already listening on 8080; checking whether Open WebUI is still starting...' -ForegroundColor Yellow
    for ($i = 0; $i -lt 60; $i++) {
        try {
            Invoke-RestMethod -Uri 'http://127.0.0.1:8080/ready' -TimeoutSec 2 | Out-Null
            Start-Process 'http://127.0.0.1:8080'
            Write-Host 'Open WebUI is ready and already running.' -ForegroundColor Green
            exit 0
        } catch { Start-Sleep -Seconds 2 }
    }
    throw 'Port 8080 is listening, but Open WebUI did not become ready within 120 seconds. Check the existing process/log; do not start a second server.'
}
if (-not (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)) { throw 'FFmpeg is missing from PATH. Run INSTALL-CHAT-PLATFORM.bat again or repair Gyan.FFmpeg.' }
Write-Host 'Starting Open WebUI. Keep this window open while using the chat.' -ForegroundColor Cyan
Write-Host 'The readiness probe is http://127.0.0.1:8080/ready' -ForegroundColor Green
Set-Location $Platform
$savedPreference = $ErrorActionPreference
try {
    # Uvicorn/Open WebUI may write routine logs to stderr; PowerShell 5.1 must not abort on that stream.
    $ErrorActionPreference = 'Continue'
    & $OpenWebUI serve --host 127.0.0.1 --port 8080
    $webuiExit = $LASTEXITCODE
} finally { $ErrorActionPreference = $savedPreference }
if ($webuiExit -ne 0) { throw "Open WebUI exited with code $webuiExit. Review D:\LocalAI\Platform\Data and the console output." }
