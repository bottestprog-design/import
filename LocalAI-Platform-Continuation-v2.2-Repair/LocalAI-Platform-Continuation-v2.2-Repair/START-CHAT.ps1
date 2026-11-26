$ErrorActionPreference = 'Stop'
$script:KeepAwakeEnabled = $false
try {
    if (-not ('LocalAI.PowerManagement' -as [type])) {
        $powerTypeDefinition = @'
using System;
using System.Runtime.InteropServices;
namespace LocalAI {
    public static class PowerManagement {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint esFlags);
    }
}
'@
        Add-Type -TypeDefinition $powerTypeDefinition -ErrorAction Stop
    }
    # Keep Windows awake while the chat server is active; allow the display to turn off.
    $powerState = [LocalAI.PowerManagement]::SetThreadExecutionState([Convert]::ToUInt32('2147483649'))
    if ($powerState -eq 0) { throw 'Windows did not accept the temporary stay-awake request.' }
    $script:KeepAwakeEnabled = $true
} catch { Write-Host "Could not request temporary keep-awake state: $($_.Exception.Message)" -ForegroundColor Yellow }
try {
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Python = Join-Path $Platform '.venv\Scripts\python.exe'
$OpenWebUI = Join-Path $Platform '.venv\Scripts\open-webui.exe'
$SecretPath = Join-Path $Platform 'Secrets\webui_secret_key.txt'
$FfmpegPathFile = Join-Path $Platform 'ffmpeg-path.txt'
$Logs = Join-Path $Platform 'Logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
if (-not (Test-Path $OpenWebUI)) { throw 'Open WebUI is not installed. Run INSTALL-PLATFORM.bat from the continuation package.' }
if (-not (Test-Path $SecretPath)) { throw 'Persistent WebUI secret is missing. Re-run INSTALL-PLATFORM.bat.' }
try { Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 8 | Out-Null }
catch { throw 'Ollama is not running. Open Ollama from the Windows Start menu and wait for its local API, then retry. This launcher will not create a second Ollama server.' }
$tags = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
$model = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*' } | Select-Object -First 1
if (-not $model) { $model = $tags.models | Where-Object { $_.name -like 'qwen3.5:9b-q4_K_M*' } | Select-Object -First 1 }
if (-not $model) { throw 'Ollama responds, but the Qwen model tag is missing. Do not reinstall; run CHECK-LOCALAI.bat and inspect Ollama tags.' }
$ModelId = [string]$model.name
# Runtime configuration is process-scoped; no keys are printed.
$env:DATA_DIR = $Data
$env:WEBUI_SECRET_KEY = (Get-Content -LiteralPath $SecretPath -Raw).Trim()
$env:OLLAMA_BASE_URL = 'http://127.0.0.1:11434'
$env:ENABLE_OLLAMA_API = 'true'
$env:DEFAULT_MODELS = $ModelId
$env:DEFAULT_MODEL_METADATA = '{"capabilities":{"vision":true,"web_search":true}}'
$env:DEFAULT_LOCALE = 'ar'
$env:WEBUI_URL = 'http://127.0.0.1:8080'
$env:ENABLE_WEB_SEARCH = 'true'
$env:ENABLE_WEB_SEARCH_CONFIRMATION = 'true'
$env:WEB_SEARCH_ENGINE = 'duckduckgo'
$env:DDGS_BACKEND = 'auto'
$env:ENABLE_FUNCTIONS = 'true'
$env:ENABLE_PLUGINS = 'true'
$env:ENABLE_API_KEYS = 'true'
$env:ENABLE_PIP_INSTALL_FRONTMATTER_REQUIREMENTS = 'false'
$env:UVICORN_WORKERS = '1'
if (Test-Path -LiteralPath $FfmpegPathFile) {
    $ffmpegExe = (Get-Content -LiteralPath $FfmpegPathFile -Raw).Trim()
    if (Test-Path -LiteralPath $ffmpegExe -PathType Leaf) {
        $ffmpegDir = Split-Path -Parent $ffmpegExe
        if (($env:Path -split ';') -notcontains $ffmpegDir) { $env:Path = $ffmpegDir + ';' + $env:Path }
    } else { Write-Host 'Saved FFmpeg path is no longer valid; audio conversion may be unavailable.' -ForegroundColor Yellow }
}
$env:OMP_NUM_THREADS = '3'
$env:MKL_NUM_THREADS = '3'
$env:TOKENIZERS_PARALLELISM = 'false'
$env:WHISPER_MODEL = 'small'
$env:WHISPER_MODEL_DIR = Join-Path $Data 'cache\whisper\models'
$env:HF_HOME = Join-Path $Data 'cache\huggingface'
$env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
$env:WHISPER_COMPUTE_TYPE = 'int8'
$env:WHISPER_MULTILINGUAL = 'true'
$env:WHISPER_VAD_FILTER = 'true'
$env:WHISPER_LANGUAGE = ''
$env:AUDIO_STT_ENGINE = ''
$env:AUDIO_TTS_ENGINE = ''
New-Item -ItemType Directory -Force -Path $Data,$env:WHISPER_MODEL_DIR,$env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE | Out-Null

# If already healthy, do not start a duplicate server.
try {
    Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 3 | Out-Null
    Start-Process 'http://127.0.0.1:8080'
    Write-Host 'Open WebUI is already running and ready.' -ForegroundColor Green
    return
} catch {}
$listener = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($listener) { throw 'Port 8080 is already occupied by a process that is not a ready Open WebUI instance. Stop/check that process before starting.' }
$stdout = Join-Path $Logs ('webui-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.stdout.log')
$stderr = Join-Path $Logs ('webui-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.stderr.log')
$process = Start-Process -FilePath $OpenWebUI -ArgumentList 'serve --host 127.0.0.1 --port 8080' -WorkingDirectory $Data -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$pidFile = Join-Path $Platform 'open-webui.pid'
Set-Content -Path $pidFile -Value $process.Id -Encoding ASCII
Write-Host "Starting Open WebUI with model $ModelId ..." -ForegroundColor Cyan
$ready = $false
for ($i=0; $i -lt 180; $i++) {
    Start-Sleep -Seconds 2
    $process.Refresh()
    if ($process.HasExited) {
        Write-Host 'Open WebUI exited during startup. Last log lines:' -ForegroundColor Red
        if (Test-Path $stderr) { Get-Content $stderr -Tail 60 }
        if (Test-Path $stdout) { Get-Content $stdout -Tail 30 }
        throw "Open WebUI exited with code $($process.ExitCode). Logs: $stdout and $stderr"
    }
    try { Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 2 | Out-Null; $ready=$true; break } catch {}
    if (($i % 15) -eq 0) { Write-Host 'Waiting for first startup/database migrations...' -ForegroundColor Yellow }
}
if (-not $ready) {
    Write-Host 'Open WebUI is still not ready. Last log lines:' -ForegroundColor Red
    if (Test-Path $stderr) { Get-Content $stderr -Tail 60 }
    if (Test-Path $stdout) { Get-Content $stdout -Tail 30 }
    throw "Readiness timeout. Logs: $stdout and $stderr"
}
Write-Host 'Open WebUI is READY at http://127.0.0.1:8080' -ForegroundColor Green
Write-Host 'Leave this window open while using the chat. Press Ctrl+C only when you want to stop the foreground launcher (the WebUI process is separate).' -ForegroundColor Yellow
Start-Process 'http://127.0.0.1:8080'
while (-not $process.HasExited) { Start-Sleep -Seconds 3; $process.Refresh() }
Write-Host "Open WebUI exited ($($process.ExitCode)). Logs: $stdout / $stderr" -ForegroundColor Yellow
}
finally {
    if ($script:KeepAwakeEnabled -and ('LocalAI.PowerManagement' -as [type])) {
        [void][LocalAI.PowerManagement]::SetThreadExecutionState([Convert]::ToUInt32('2147483648'))
    }
}
