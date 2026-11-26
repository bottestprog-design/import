$ErrorActionPreference='Stop'
# LocalAI Studio one-click launcher. Open WebUI runs in the background.
$Root='D:\LocalAI'; $Platform=Join-Path $Root 'Platform'; $Data=Join-Path $Platform 'Data'
$Logs=Join-Path $Platform 'Logs'; $Python=Join-Path $Platform '.venv\Scripts\python.exe'
$OpenWebUI=Join-Path $Platform '.venv\Scripts\open-webui.exe'; $SecretPath=Join-Path $Platform 'Secrets\webui_secret_key.txt'
$FfmpegPathFile=Join-Path $Platform 'ffmpeg-path.txt'; $TempRoot=Join-Path $Data 'Temp'
$PidFile=Join-Path $Platform 'open-webui.pid'

function Show-RecentLogs([string]$Out,[string]$Err) {
    Write-Host ([Environment]::NewLine+'--- Recent Open WebUI output ---') -ForegroundColor Yellow
    if(Test-Path -LiteralPath $Err -PathType Leaf){Get-Content -LiteralPath $Err -Tail 45 -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $Out -PathType Leaf){Get-Content -LiteralPath $Out -Tail 25 -ErrorAction SilentlyContinue}
    Write-Host "Logs: $Out | $Err" -ForegroundColor DarkGray
}
function Set-TempEnvironment {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
    $env:TEMP=$TempRoot; $env:TMP=$TempRoot; $env:TMPDIR=$TempRoot
}
function Get-LocalAIListener {
    try { return Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction Stop | Select-Object -First 1 }
    catch { return $null }
}
function Test-LocalAIReadyEndpoint {
    try { Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 3 -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}
function Assert-TrackedOpenWebUIProcess([int]$ListenerPid) {
    if (-not (Test-Path -LiteralPath $PidFile -PathType Leaf)) {
        throw 'Port 8080 responds as Open WebUI, but no LocalAI PID file exists. Refusing to adopt an untracked service.'
    }
    $rawPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    $trackedPid = 0
    if (-not [int]::TryParse($rawPid, [ref]$trackedPid) -or $trackedPid -le 0) {
        throw 'LocalAI PID file is invalid. Refusing to stop or adopt any process.'
    }
    if ($trackedPid -ne $ListenerPid) {
        throw "Port 8080 is owned by PID $ListenerPid, but LocalAI tracks PID $trackedPid. Refusing to adopt another service."
    }
    $tracked = Get-CimInstance Win32_Process -Filter "ProcessId=$trackedPid" -ErrorAction SilentlyContinue
    if (-not $tracked -or [string]::IsNullOrWhiteSpace([string]$tracked.ExecutablePath)) {
        throw "Tracked LocalAI process $trackedPid could not be verified through Windows process information."
    }
    $actual = [IO.Path]::GetFullPath([string]$tracked.ExecutablePath)
    $expected = [IO.Path]::GetFullPath($OpenWebUI)
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "PID $trackedPid is not this project's Open WebUI executable. Actual path: $actual"
    }
    return $trackedPid
}
function Invoke-PythonText([string]$Code) {
    $scriptPath = Join-Path $TempRoot ('localai-python-' + [guid]::NewGuid().ToString('N') + '.py')
    [IO.File]::WriteAllText($scriptPath,$Code,[System.Text.UTF8Encoding]::new($false))
    try {
        $lines = @(& $Python $scriptPath 2>&1)
        $exitCode = [int]$LASTEXITCODE
        return [pscustomobject]@{ ExitCode=$exitCode; Output=@($lines) }
    } finally { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue }
}
function Repair-OpenWebUIWindowsTempPath {
    # Open WebUI 0.13.5 has a Unix-only /tmp argument in utils/machines/managed.py.
    # Replace only that line and preserve the original vendor file once.
    $probeCode='import importlib.util,json; from importlib.metadata import version; from pathlib import Path; s=importlib.util.find_spec("open_webui"); print(json.dumps({"version":version("open-webui"),"package":str(Path(s.origin).parent) if s and s.origin else ""}))'
    $probeResult=Invoke-PythonText $probeCode
    $probe=$probeResult.Output
    if($probeResult.ExitCode -ne 0 -or $probe.Count -eq 0){throw "Could not locate the installed Open WebUI package: $($probe -join ' ')"}
    try{$info=([string]($probe|Select-Object -Last 1))|ConvertFrom-Json}catch{throw "Could not parse Open WebUI package information: $($probe -join ' ')"}
    if(-not $info.package){throw 'Open WebUI package folder was not found.'}
    if($info.version -ne '0.13.5'){throw "This Windows compatibility patch is validated for Open WebUI 0.13.5, not $($info.version). No vendor source was changed."}
    $managed=Join-Path ([string]$info.package) 'utils\machines\managed.py'
    if(-not(Test-Path -LiteralPath $managed -PathType Leaf)){throw "Open WebUI compatibility source missing: $managed"}
    $source=[IO.File]::ReadAllText($managed)
    $old="RUN_DIR = Path(tempfile.mkdtemp(prefix='open-webui-', dir='/tmp'))"
    $fixed="RUN_DIR = Path(tempfile.mkdtemp(prefix='open-webui-', dir=str(_RUN_TMP_ROOT)))"
    $backup=Join-Path $Platform 'Backups\OpenWebUI\managed.py.original'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup)|Out-Null
    if($source.Contains($old)){
        if(-not(Test-Path -LiteralPath $backup -PathType Leaf)){Copy-Item -LiteralPath $managed -Destination $backup -Force}
        $replacement="_RUN_TMP_ROOT = Path(tempfile.gettempdir())"+[Environment]::NewLine+"_RUN_TMP_ROOT.mkdir(parents=True, exist_ok=True)"+[Environment]::NewLine+$fixed
        $encoding=[System.Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($managed,$source.Replace($old,$replacement),$encoding)
        Write-Host '[OK] Applied Open WebUI Windows temp-path fix.' -ForegroundColor Green
    }elseif($source.Contains($fixed)-and $source.Contains('tempfile.gettempdir()')){
        Write-Host '[OK] Windows temp-path fix already applied.' -ForegroundColor Green
    }else{
        throw "Expected /tmp line was not found. No vendor file was changed: $managed"
    }
    $test='import os,tempfile; p=tempfile.gettempdir(); d=tempfile.mkdtemp(prefix="localai-check-",dir=p); os.rmdir(d); print("TEMP_OK="+p)'
    $result=Invoke-PythonText $test
    if($result.ExitCode -ne 0 -or -not(($result.Output -join [Environment]::NewLine)-match 'TEMP_OK=')){throw "Windows temp folder is not writable: $TempRoot. $($result.Output -join ' ')"}
    Write-Host "[OK] Python temp folder: $TempRoot" -ForegroundColor Green
}
function Apply-LocalAITheme {
    $source=Join-Path $PSScriptRoot 'LOCALAI-STUDIO-THEME.css'
    $target=Join-Path $Platform 'LOCALAI-STUDIO-THEME.css'
    if((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target))){Copy-Item -LiteralPath $source -Destination $target -Force}
    if(-not(Test-Path -LiteralPath $target -PathType Leaf)){return}
    try{
        $code='import importlib.util,pathlib; s=importlib.util.find_spec("open_webui"); print(str(pathlib.Path(s.origin).parent/"static"/"custom.css") if s and s.origin else "")'
        $probe=Invoke-PythonText $code
        $o=$probe.Output
        if($probe.ExitCode -ne 0 -or $o.Count -eq 0){throw 'Could not locate Open WebUI static assets.'}
        $css=([string]($o|Select-Object -Last 1)).Trim()
        if(-not $css){throw 'Open WebUI custom.css path is empty.'}
        $static=Split-Path -Parent $css
        if(-not(Test-Path -LiteralPath $static -PathType Container)){throw "Static assets folder missing: $static"}
        $backup=Join-Path $Platform 'Backups\OpenWebUI\custom.css.original'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup)|Out-Null
        if(-not(Test-Path -LiteralPath $backup -PathType Leaf)){
            if(Test-Path -LiteralPath $css -PathType Leaf){Copy-Item -LiteralPath $css -Destination $backup -Force}
            else{[IO.File]::WriteAllText($backup,'')}
        }
        Copy-Item -LiteralPath $target -Destination $css -Force
        Write-Host '[OK] LocalAI Studio styling applied.' -ForegroundColor Green
    }catch{Write-Host "Theme skipped; chat can still run: $($_.Exception.Message)" -ForegroundColor Yellow}
}

$startMutex = $null
$ownsStartMutex = $false
try{
    New-Item -ItemType Directory -Force -Path $Data,$Logs,$Platform|Out-Null
    Set-TempEnvironment
    $startMutex = [System.Threading.Mutex]::new($false, 'Local\LocalAIStudio-Start')
    try { $ownsStartMutex = $startMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsStartMutex = $true }
    if (-not $ownsStartMutex) { throw 'Another LocalAI Studio start request is already running. Wait for that start to finish.' }

    $earlyListener = Get-LocalAIListener
    if ($earlyListener) {
        if (-not (Test-LocalAIReadyEndpoint)) {
            throw "Port 8080 already has a listener (PID $($earlyListener.OwningProcess)) that is not ready. No second server was started."
        }
        [void](Assert-TrackedOpenWebUIProcess -ListenerPid ([int]$earlyListener.OwningProcess))
        try { Start-Process 'http://127.0.0.1:8080' } catch { Write-Host 'LocalAI Studio is ready; open http://127.0.0.1:8080 manually if needed.' -ForegroundColor Yellow }
        Write-Host 'LocalAI Studio is already running and its tracked process owns port 8080.' -ForegroundColor Green
        exit 0
    }
    if (Test-Path -LiteralPath $PidFile -PathType Leaf) {
        $staleRawPid = (Get-Content -LiteralPath $PidFile -Raw).Trim()
        $stalePid = 0
        if (-not [int]::TryParse($staleRawPid, [ref]$stalePid) -or $stalePid -le 0) { throw 'LocalAI PID file is invalid. Refusing to start another server.' }
        $staleProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$stalePid" -ErrorAction SilentlyContinue
        if ($staleProcess) {
            $staleExe = [string]$staleProcess.ExecutablePath
            if (-not $staleExe -or -not [IO.Path]::GetFullPath($staleExe).Equals([IO.Path]::GetFullPath($OpenWebUI), [StringComparison]::OrdinalIgnoreCase)) {
                throw "PID file points to a process that is not this project's Open WebUI. PID $stalePid was not touched."
            }
            throw "Tracked Open WebUI process $stalePid is still running but port 8080 is not listening. Inspect its logs before starting another copy."
        }
        Remove-Item -LiteralPath $PidFile -Force
    }
    if(-not(Test-Path -LiteralPath $Python -PathType Leaf)){throw "Project Python missing: $Python. Run LocalAI-Studio.bat repair only if platform is not installed."}
    if(-not(Test-Path -LiteralPath $OpenWebUI -PathType Leaf)){throw "Open WebUI missing: $OpenWebUI. Run LocalAI-Studio.bat repair only if platform is not installed."}
    if(-not(Test-Path -LiteralPath $SecretPath -PathType Leaf)){throw "Persistent WebUI secret missing: $SecretPath. Do not delete Data; run LocalAI-Studio.bat repair."}
    try{Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 8|Out-Null}
    catch{throw 'Ollama is not running. Open Ollama, wait for its local API, then double-click LocalAI-Studio.bat.'}
    $tags=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    $model=$tags.models|Where-Object{$_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*'}|Select-Object -First 1
    if(-not $model){$model=$tags.models|Where-Object{$_.name -like 'qwen3.5:9b-q4_K_M*'}|Select-Object -First 1}
    if(-not $model){
        $modelManager=Join-Path $PSScriptRoot 'ENSURE-MODELS.ps1'
        if(-not(Test-Path -LiteralPath $modelManager -PathType Leaf)){throw "Model manager missing: $modelManager. Run LocalAI-Studio.bat repair."}
        $managerOutput=@(& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $modelManager 2>&1)
        $managerExit=[int]$LASTEXITCODE
        if($managerExit -ne 0){throw "Model verification failed with exit code $managerExit. Review D:\LocalAI\Platform\MODEL-STATUS.txt. $($managerOutput -join ' ')"}
        $tags=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
        $model=$tags.models|Where-Object{$_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*'}|Select-Object -First 1
        if(-not $model){$model=$tags.models|Where-Object{$_.name -like 'qwen3.5:9b-q4_K_M*'}|Select-Object -First 1}
    }
    if(-not $model){throw 'Qwen 3.5 9B is not registered in the running Ollama API. Run LocalAI-Studio.bat repair to verify or restore its local manifest.'}
    $ModelId=[string]$model.name

    $env:DATA_DIR=$Data
    $env:WEBUI_SECRET_KEY=(Get-Content -LiteralPath $SecretPath -Raw).Trim()
    $env:OLLAMA_BASE_URL='http://127.0.0.1:11434'
    $env:ENABLE_OLLAMA_API='true'
    $env:DEFAULT_MODELS=$ModelId
    # Do not advertise vision/search support globally for every model.
    Remove-Item Env:DEFAULT_MODEL_METADATA -ErrorAction SilentlyContinue
    $env:DEFAULT_LOCALE='ar'
    $env:WEBUI_NAME='LocalAI Studio'
    $env:DEFAULT_INTERFACE_SETTINGS='{"widescreenMode":true,"chatBubble":false,"copyFormatted":true,"showChatTitleInTab":true,"title":{"auto":false},"autoFollowUps":false,"autoTags":false,"promptAutocomplete":false}'
    $env:ENABLE_AUTOCOMPLETE_GENERATION='false'
    $env:ENABLE_FOLLOW_UP_GENERATION='false'
    $env:ENABLE_TAGS_GENERATION='false'
    $env:WEBUI_URL='http://127.0.0.1:8080'
    $env:ENABLE_WEB_SEARCH='true'
    $env:ENABLE_WEB_SEARCH_CONFIRMATION='true'
    $env:WEB_SEARCH_ENGINE='duckduckgo'
    $env:DDGS_BACKEND='auto'
    $env:ENABLE_FUNCTIONS='true'
    $env:ENABLE_PLUGINS='true'
    $env:ENABLE_API_KEYS='true'
    $env:ENABLE_PIP_INSTALL_FRONTMATTER_REQUIREMENTS='false'
    $env:UVICORN_WORKERS='1'
    if(Test-Path -LiteralPath $FfmpegPathFile){
        $ffmpeg=(Get-Content -LiteralPath $FfmpegPathFile -Raw).Trim()
        if(Test-Path -LiteralPath $ffmpeg -PathType Leaf){
            $ffdir=Split-Path -Parent $ffmpeg
            if(($env:Path -split ';') -notcontains $ffdir){$env:Path=$ffdir+';'+$env:Path}
        }else{Write-Host 'FFmpeg path record is stale; text chat still works.' -ForegroundColor Yellow}
    }
    $env:OMP_NUM_THREADS='3';$env:MKL_NUM_THREADS='3';$env:TOKENIZERS_PARALLELISM='false'
    $env:WHISPER_MODEL='base'
    $env:WHISPER_MODEL_DIR=Join-Path $Data 'cache\whisper\models'
    $modelStatusPath=Join-Path $Platform 'MODEL-STATUS.json'
    if(Test-Path -LiteralPath $modelStatusPath -PathType Leaf){
        try {
            $modelStatus=Get-Content -LiteralPath $modelStatusPath -Raw -Encoding UTF8|ConvertFrom-Json
            $candidateCache=[string]$modelStatus.whisper.cache_dir
            $snapshot=[string]$modelStatus.whisper.path
            if($modelStatus.whisper.status -eq 'ready' -and
               (Test-Path -LiteralPath $snapshot -PathType Container) -and
               (Test-Path -LiteralPath (Join-Path $snapshot 'model.bin') -PathType Leaf) -and
               (Test-Path -LiteralPath $candidateCache -PathType Container)){
                # Keep the Open WebUI model alias ("base") aligned with its persisted STT setting.
                # Point only the regular download-root variable at the verified Hugging Face cache.
                $env:WHISPER_MODEL=[string]$modelStatus.whisper.model
                $env:WHISPER_MODEL_DIR=$candidateCache
            }
        }catch{Write-Host 'Whisper cache status could not be loaded; using the configured default cache.' -ForegroundColor Yellow}
    }
    $env:HF_HOME=Join-Path $Data 'cache\huggingface';$env:HUGGINGFACE_HUB_CACHE=Join-Path $env:HF_HOME 'hub'
    $env:WHISPER_COMPUTE_TYPE='int8';$env:WHISPER_MULTILINGUAL='true';$env:WHISPER_VAD_FILTER='true'
    $env:WHISPER_LANGUAGE='';$env:AUDIO_STT_ENGINE='';$env:AUDIO_TTS_ENGINE=''
    New-Item -ItemType Directory -Force -Path $env:WHISPER_MODEL_DIR,$env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE|Out-Null

    Repair-OpenWebUIWindowsTempPath
    $listener=Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1
    if($listener){throw 'Port 8080 is occupied by a process that is not a ready Open WebUI instance. No process was stopped.'}

    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdout=Join-Path $Logs ('webui-'+$stamp+'.stdout.log')
    $stderr=Join-Path $Logs ('webui-'+$stamp+'.stderr.log')
    $process=Start-Process -FilePath $OpenWebUI -ArgumentList 'serve --host 127.0.0.1 --port 8080' -WorkingDirectory $Data -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII
    Write-Host "Starting LocalAI Studio with $ModelId ..." -ForegroundColor Cyan
    $ready=$false
    for($i=0;$i -lt 180;$i++){
        Start-Sleep -Seconds 2
        $process.Refresh()
        if($process.HasExited){
            $process.WaitForExit();$exitCode='unavailable'
            try{$exitCode=[string]$process.ExitCode}catch{}
            Show-RecentLogs -Out $stdout -Err $stderr
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
            throw "Open WebUI stopped during startup (exit code: $exitCode)."
        }
        try{Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 2|Out-Null;$ready=$true;break}catch{}
        if(($i%20)-eq 0){Write-Host 'First startup may perform database migrations; still starting...' -ForegroundColor Yellow}
    }
    if(-not $ready){
        Show-RecentLogs -Out $stdout -Err $stderr
        throw "Open WebUI did not become ready within 6 minutes. Process was left running for inspection. Logs: $stdout and $stderr"
    }
    Apply-LocalAITheme
    try { Start-Process 'http://127.0.0.1:8080' } catch { Write-Host 'The server is ready; open http://127.0.0.1:8080 manually if needed.' -ForegroundColor Yellow }
    Write-Host 'SUCCESS: LocalAI Studio is ready. The server continues in the background.' -ForegroundColor Green
    Write-Host 'Open WebUI: http://127.0.0.1:8080' -ForegroundColor Cyan
    Write-Host 'To stop it, double-click LocalAI-Studio.bat stop. Ollama and Qwen remain running.' -ForegroundColor DarkGray
    exit 0
}catch{
    Write-Host ([Environment]::NewLine+"LOCALAI START FAILED: $($_.Exception.Message)") -ForegroundColor Red
    exit 1
}finally{
    if($ownsStartMutex -and $startMutex){try{$startMutex.ReleaseMutex()}catch{}}
    if($startMutex){$startMutex.Dispose()}
}
