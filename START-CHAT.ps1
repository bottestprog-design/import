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
function Repair-OpenWebUIWindowsTempPath {
    # Open WebUI 0.13.5 has a Unix-only /tmp argument in utils/machines/managed.py.
    # Replace only that line and preserve the original vendor file once.
    $probeCode='import importlib.util,json; from importlib.metadata import version; from pathlib import Path; s=importlib.util.find_spec("open_webui"); print(json.dumps({"version":version("open-webui"),"package":str(Path(s.origin).parent) if s and s.origin else ""}))'
    $probe=@(& $Python -c $probeCode 2>&1)
    if($LASTEXITCODE -ne 0 -or $probe.Count -eq 0){throw 'Could not locate the installed Open WebUI package.'}
    try{$info=([string]($probe|Select-Object -Last 1))|ConvertFrom-Json}catch{throw 'Could not parse Open WebUI package information.'}
    if(-not $info.package){throw 'Open WebUI package folder was not found.'}
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
    $result=@(& $Python -c $test 2>&1)
    if($LASTEXITCODE -ne 0 -or -not(($result -join [Environment]::NewLine)-match 'TEMP_OK=')){throw "Windows temp folder is not writable: $TempRoot"}
    Write-Host "[OK] Python temp folder: $TempRoot" -ForegroundColor Green
}
function Apply-LocalAITheme {
    $source=Join-Path $PSScriptRoot 'LOCALAI-STUDIO-THEME.css'
    $target=Join-Path $Platform 'LOCALAI-STUDIO-THEME.css'
    if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination $target -Force}
    if(-not(Test-Path -LiteralPath $target -PathType Leaf)){return}
    try{
        $code='import importlib.util,pathlib; s=importlib.util.find_spec("open_webui"); print(str(pathlib.Path(s.origin).parent/"static"/"custom.css") if s and s.origin else "")'
        $o=@(& $Python -c $code 2>&1)
        if($LASTEXITCODE -ne 0 -or $o.Count -eq 0){throw 'Could not locate Open WebUI static assets.'}
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

try{
    New-Item -ItemType Directory -Force -Path $Data,$Logs,$Platform|Out-Null
    Set-TempEnvironment
    if(-not(Test-Path -LiteralPath $Python -PathType Leaf)){throw "Project Python missing: $Python. Run RUN-REPAIR.bat only if platform is not installed."}
    if(-not(Test-Path -LiteralPath $OpenWebUI -PathType Leaf)){throw "Open WebUI missing: $OpenWebUI. Run RUN-REPAIR.bat only if platform is not installed."}
    if(-not(Test-Path -LiteralPath $SecretPath -PathType Leaf)){throw "Persistent WebUI secret missing: $SecretPath. Do not delete Data; run RUN-REPAIR.bat."}
    try{Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 8|Out-Null}
    catch{throw 'Ollama is not running. Open Ollama, wait for its local API, then double-click START-LOCALAI.bat.'}
    $tags=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    $model=$tags.models|Where-Object{$_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*'}|Select-Object -First 1
    if(-not $model){$model=$tags.models|Where-Object{$_.name -like 'qwen3.5:9b-q4_K_M*'}|Select-Object -First 1}
    if(-not $model){throw 'Existing Qwen 3.5 9B tag was not found. No model download was attempted.'}
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
    $env:WHISPER_MODEL='small';$env:WHISPER_MODEL_DIR=Join-Path $Data 'cache\whisper\models'
    $env:HF_HOME=Join-Path $Data 'cache\huggingface';$env:HUGGINGFACE_HUB_CACHE=Join-Path $env:HF_HOME 'hub'
    $env:WHISPER_COMPUTE_TYPE='int8';$env:WHISPER_MULTILINGUAL='true';$env:WHISPER_VAD_FILTER='true'
    $env:WHISPER_LANGUAGE='';$env:AUDIO_STT_ENGINE='';$env:AUDIO_TTS_ENGINE=''
    New-Item -ItemType Directory -Force -Path $env:WHISPER_MODEL_DIR,$env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE|Out-Null

    Repair-OpenWebUIWindowsTempPath
    try{
        Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 3|Out-Null
        Apply-LocalAITheme
        Start-Process 'http://127.0.0.1:8080'
        Write-Host 'LocalAI Studio is already running. Browser opened.' -ForegroundColor Green
        exit 0
    }catch{}
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
    Start-Process 'http://127.0.0.1:8080'
    Write-Host 'SUCCESS: LocalAI Studio is ready. The server continues in the background.' -ForegroundColor Green
    Write-Host 'Open WebUI: http://127.0.0.1:8080' -ForegroundColor Cyan
    Write-Host 'To stop it, double-click STOP-CHAT.bat. Ollama and Qwen remain running.' -ForegroundColor DarkGray
    exit 0
}catch{
    Write-Host ([Environment]::NewLine+"LOCALAI START FAILED: $($_.Exception.Message)") -ForegroundColor Red
    exit 1
}
