$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Venv = Join-Path $Platform '.venv'
$OpenWebUI = Join-Path $Venv 'Scripts\open-webui.exe'
$SecretPath = Join-Path $Platform 'webui_secret_key.txt'
$BaseUrl = 'http://127.0.0.1:8080'
if (-not (Test-Path -LiteralPath $OpenWebUI -PathType Leaf)) { throw 'Open WebUI executable is missing. Run RUN-REPAIR.bat from the extracted recovery package.' }
if (-not (Test-Path -LiteralPath $SecretPath -PathType Leaf)) { throw 'WEBUI_SECRET_KEY is missing. Run RUN-REPAIR.bat again.' }

# Keep all services bound to loopback; preserve the already-installed Ollama service and model store.
$env:OLLAMA_BASE_URL = 'http://127.0.0.1:11434'
$env:DATA_DIR = $Data
$env:DEFAULT_MODELS = 'local-qwen35:latest'
$env:DEFAULT_LOCALE = 'ar'
$env:WEBUI_SECRET_KEY = (Get-Content -LiteralPath $SecretPath -Raw).Trim()
$env:WHISPER_MODEL = 'base'
$env:HF_HOME = Join-Path $Data 'cache\huggingface'
$env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
$env:WHISPER_MODEL_DIR = Join-Path $Data 'cache\whisper\models'
$env:WHISPER_COMPUTE_TYPE = 'int8'
$env:WHISPER_MULTILINGUAL = 'true'
$env:WHISPER_VAD_FILTER = 'true'
$env:WHISPER_LANGUAGE = ''
$env:AUDIO_STT_ENGINE = ''
$env:AUDIO_TTS_ENGINE = ''
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

try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 5 | Out-Null }
catch {
    $engineStart = Join-Path $Root 'START-ENGINE.ps1'
    if (-not (Test-Path -LiteralPath $engineStart)) { throw 'Ollama is offline and the preserved START-ENGINE.ps1 helper is missing.' }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $engineStart
    if ($LASTEXITCODE -ne 0) { throw "Could not start Ollama (exit code $LASTEXITCODE)." }
}
$tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
if (-not ($tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -eq 'local-qwen35' })) { throw 'The existing Ollama model alias local-qwen35 is missing. No model download was attempted.' }

function Test-WebUIReady {
    try {
        $r = Invoke-WebRequest -Uri ($BaseUrl + '/ready') -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}
if (Test-WebUIReady) {
    Start-Process $BaseUrl
    Write-Host 'Open WebUI is already running and healthy.' -ForegroundColor Green
    exit 0
}
$listener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) { throw "Port 8080 is already used by PID $($listener.OwningProcess), but it is not a ready Open WebUI instance. The repair will not stop another process." }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $Data ("open-webui-$stamp.stdout.log")
$stderr = Join-Path $Data ("open-webui-$stamp.stderr.log")
$pidFile = Join-Path $Data 'open-webui.pid'
Write-Host 'Starting Open WebUI in the background and waiting for the real HTTP readiness endpoint...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $OpenWebUI -ArgumentList @('serve','--host','127.0.0.1','--port','8080') -WorkingDirectory $Platform -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ASCII
$ready = $false
for ($i=0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    $proc.Refresh()
    if ($proc.HasExited) { break }
    if (Test-WebUIReady) { $ready = $true; break }
    if (($i % 10) -eq 9) { Write-Host ("Still starting... {0}/180 seconds (PID {1})" -f (($i+1)*2),$proc.Id) -ForegroundColor Yellow }
}
if (-not $ready) {
    $outText = if (Test-Path $stdout) { Get-Content $stdout -Tail 50 -ErrorAction SilentlyContinue | Out-String } else { '' }
    $errText = if (Test-Path $stderr) { Get-Content $stderr -Tail 80 -ErrorAction SilentlyContinue | Out-String } else { '' }
    $detail = "Open WebUI did not become ready. PID=$($proc.Id); stdout=$stdout; stderr=$stderr`n$outText`n$errText"
    throw $detail
}
Start-Process $BaseUrl
Write-Host 'SUCCESS: Open WebUI is healthy at http://127.0.0.1:8080' -ForegroundColor Green
Write-Host "Server PID: $($proc.Id) | Logs: $stdout and $stderr" -ForegroundColor DarkGray
