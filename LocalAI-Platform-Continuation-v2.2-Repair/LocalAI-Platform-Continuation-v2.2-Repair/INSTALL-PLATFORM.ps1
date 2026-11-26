$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Logs = Join-Path $Root 'Logs'
$FilterDir = Join-Path $Platform 'Filters'
$Cache = Join-Path $Root 'Cache'
# Verify the extracted package before touching the target installation.
$manifestPath = Join-Path $PSScriptRoot 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Package manifest is missing. Re-extract the complete ZIP before installing.' }
$manifestLines = Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') }
if (@($manifestLines).Count -lt 10) { throw 'Package manifest is incomplete. Re-download and re-extract the ZIP.' }
foreach ($manifestLine in $manifestLines) {
    if ($manifestLine -notmatch '^([0-9A-Fa-f]{64})\s+(.+)$') { throw "Invalid manifest line: $manifestLine" }
    $expectedHash = $matches[1].ToLowerInvariant()
    $relativePath = $matches[2].Trim()
    if ($relativePath.StartsWith('*')) { $relativePath = $relativePath.Substring(1) }
    $candidatePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Package file is missing: $relativePath" }
    $actualHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw "Package integrity mismatch: $relativePath. Extract the ZIP again." }
}
Write-Host "[OK] Package integrity verified ($(@($manifestLines).Count) files)." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $Root,$Platform,$Data,$Logs,$FilterDir,$Cache,(Join-Path $Cache 'pip'),(Join-Path $Data 'cache\huggingface'),(Join-Path $Data 'cache\whisper\models'),(Join-Path $Platform 'Secrets') | Out-Null
$script:Logs = $Logs
$LogFile = Join-Path $Logs ('platform-continuation-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $LogFile -Force | Out-Null
$StatusFile = Join-Path $Platform 'PLATFORM-STATUS.txt'
$FullStatusFile = Join-Path $Root 'FULL-STATUS.txt'
$EngineStatusFile = Join-Path $Root 'ENGINE-STATUS.txt'
$RequiredWebUI = '0.13.5'
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
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED: prevent idle sleep only while this installer runs.
    $powerState = [LocalAI.PowerManagement]::SetThreadExecutionState([Convert]::ToUInt32('2147483649'))
    if ($powerState -eq 0) { throw 'Windows did not accept the temporary stay-awake request.' }
    $script:KeepAwakeEnabled = $true
} catch { Write-Host "Could not request temporary keep-awake state: $($_.Exception.Message)" -ForegroundColor Yellow }
$Warnings = New-Object System.Collections.Generic.List[string]
$Failures = New-Object System.Collections.Generic.List[string]
function Quote-Arg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"','\"') + '"'
}
function Read-AppendedLogText([string]$Path,[long]$Offset) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ Text=''; Offset=$Offset } }
    $stream = $null; $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
        if ($stream.Length -lt $Offset) { $Offset = 0 }
        [void]$stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
        $reader = [System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,4096,$true)
        $text = $reader.ReadToEnd()
        return [pscustomobject]@{ Text=$text; Offset=[long]$stream.Position }
    } catch {
        # Console streaming is best-effort. A log file lock must never abort pip installation.
        return [pscustomobject]@{ Text=''; Offset=$Offset }
    } finally {
        if ($reader) { $reader.Dispose() }; if ($stream) { $stream.Dispose() }
    }
}
function Write-LogDelta([string]$Text,[ConsoleColor]$Color) {
    if ([string]::IsNullOrEmpty($Text)) { return }
    foreach ($line in (($Text -replace "`r", "`n") -split "`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line -ForegroundColor $Color }
    }
}
function Invoke-NativeLogged {
    param([string]$Executable,[string[]]$Arguments,[string]$Label,[int]$NoticeSeconds=45)
    $id = [guid]::NewGuid().ToString('N')
    $outFile = Join-Path $script:Logs ($id + '.stdout.log')
    $errFile = Join-Path $script:Logs ($id + '.stderr.log')
    $argLine = (($Arguments | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
    Write-Host "`n>>> $Label" -ForegroundColor Cyan
    Write-Host "Live logs: $outFile | $errFile" -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $Executable -ArgumentList $argLine -PassThru -NoNewWindow `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    $outOffset = [long]0; $errOffset = [long]0
    $lastNotice = Get-Date; $lastOutput = Get-Date
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 2; $proc.Refresh()
        $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
        $ed = Read-AppendedLogText -Path $errFile -Offset $errOffset
        $outOffset = $od.Offset; $errOffset = $ed.Offset
        if ($od.Text) { Write-LogDelta -Text $od.Text -Color Gray; $lastOutput = Get-Date }
        if ($ed.Text) { Write-LogDelta -Text $ed.Text -Color DarkYellow; $lastOutput = Get-Date }
        if (-not $proc.HasExited -and ((Get-Date)-$lastNotice).TotalSeconds -ge $NoticeSeconds) {
            $ob = if (Test-Path $outFile) { (Get-Item $outFile).Length } else { 0 }
            $eb = if (Test-Path $errFile) { (Get-Item $errFile).Length } else { 0 }
            $quiet = [int]((Get-Date)-$lastOutput).TotalSeconds
            Write-Host ("$Label is still running (PID {0}); stdout {1:N0} KB, stderr {2:N0} KB; last output {3}s ago." -f $proc.Id,($ob/1KB),($eb/1KB),$quiet) -ForegroundColor Yellow
            Write-Host "Logs: $outFile | $errFile" -ForegroundColor DarkGray
            $lastNotice = Get-Date
        }
    }
    $proc.WaitForExit()
    $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
    $ed = Read-AppendedLogText -Path $errFile -Offset $errOffset
    Write-LogDelta -Text $od.Text -Color Gray; Write-LogDelta -Text $ed.Text -Color DarkYellow
    $stdout = if (Test-Path $outFile) { [IO.File]::ReadAllText($outFile) } else { '' }
    $stderr = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    $exitCode = [int]$proc.ExitCode
    if ($exitCode -eq 0) { Write-Host "[OK] $Label completed successfully." -ForegroundColor Green }
    else { Write-Host "[FAIL] $Label exited with code $exitCode. See $outFile and $errFile" -ForegroundColor Red }
    return [pscustomobject]@{ ExitCode=$exitCode; StdOut=$stdout; StdErr=$stderr; StdOutPath=$outFile; StdErrPath=$errFile }
}
function Refresh-UserPath {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user = [Environment]::GetEnvironmentVariable('Path','User')
    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $parts = @($machine,$user,$links) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = [string]::Join(';',$parts)
}

function Find-Python {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python311\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe'),
        'C:\Python311\python.exe','C:\Python312\python.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $probe = Invoke-NativeLogged -Executable $candidate -Arguments @('-c','import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")') -Label 'Validate system Python'
            if ($probe.ExitCode -eq 0) {
                $v = ($probe.StdOut -split "`r?`n" | Where-Object { $_ -match '^3\.(11|12)\.' } | Select-Object -First 1)
                if ($v) { return [pscustomobject]@{Exe=$candidate; Version=$v} }
            }
        }
    }
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        foreach ($minor in @('3.11','3.12')) {
            $p = Invoke-NativeLogged -Executable $launcher.Source -Arguments @('-'+$minor,'-c','import sys;print(sys.executable);print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")') -Label "Probe Python $minor launcher"
            if ($p.ExitCode -eq 0 -and $p.StdOut -match '(?m)^3\.(11|12)\.') {
                $lines = $p.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                return [pscustomobject]@{Exe=$launcher.Source; Prefix=@('-'+$minor); Version=$lines[-1]}
            }
        }
    }
    return $null
}
function Invoke-Python([string]$Python,[string[]]$Arguments,[string]$Label) {
    $res = Invoke-NativeLogged -Executable $Python -Arguments $Arguments -Label $Label -NoticeSeconds 45
    if ($res.ExitCode -ne 0) { throw "$Label failed (exit $($res.ExitCode)). STDERR: $($res.StdErr) | STDOUT: $($res.StdOut)" }
    return $res
}
function Get-Ffmpeg {
    Refresh-UserPath
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'),
        (Join-Path $env:ProgramFiles 'FFmpeg\bin\ffmpeg.exe'),
        'C:\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p -PathType Leaf) { return $p } }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $packages) {
        $found = Get-ChildItem -Path $packages -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Gyan\.FFmpeg' } | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

try {
    Write-Host 'LOCAL AI - PLATFORM CONTINUATION INSTALLER v2.2' -ForegroundColor Cyan
    Write-Host 'This installer starts AFTER Ollama and Qwen are installed.'
    Write-Host 'It will NOT reinstall Ollama, download Qwen, delete model blobs, or change the Ollama model store.'
    if (Test-Path $StatusFile) { Copy-Item $StatusFile (Join-Path $Platform ('PLATFORM-STATUS-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')) -Force }

    # Verify the real running Ollama API and existing model tag. No ENGINE-STATUS marker is required.
    try { $version = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 8 }
    catch { throw 'Ollama local API is not responding on 127.0.0.1:11434. Start the Ollama app first; this installer will not restart it.' }
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 20
    $model = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*' } | Select-Object -First 1
    if (-not $model) { $model = $tags.models | Where-Object { $_.name -like 'qwen3.5:9b-q4_K_M*' } | Select-Object -First 1 }
    if (-not $model) { throw 'Neither local-qwen35 nor qwen3.5:9b-q4_K_M exists in Ollama. No model downloads were attempted.' }
    $ModelId = [string]$model.name
    Write-Host "[OK] Ollama $($version.version); found model $ModelId ($([math]::Round($model.size/1GB,2)) GB)." -ForegroundColor Green
    $ModelStore = Join-Path $Root 'Models'
    if (Test-Path (Join-Path $ModelStore 'manifests')) {
        @("STATUS: API_READY_MODEL_TAG_PRESENT","Inference test: run D:\LocalAI\Platform\VERIFY-MODEL.bat","Ollama: $($version.version)","API: http://127.0.0.1:11434","Model: $ModelId","Model size bytes: $($model.size)","Model store: $ModelStore","Model files were verified by Ollama /api/tags; no files changed by this installer.") | Set-Content -Path $EngineStatusFile -Encoding UTF8
        Set-Content -Path (Join-Path $Root 'MODEL-STORE-PATH.txt') -Value $ModelStore -Encoding UTF8
    } else {
        @("STATUS: API_READY_MODEL_TAG_PRESENT","Inference test: run D:\LocalAI\Platform\VERIFY-MODEL.bat","Ollama: $($version.version)","API: http://127.0.0.1:11434","Model: $ModelId","Model size bytes: $($model.size)","Model store: see Ollama server.log") | Set-Content -Path $EngineStatusFile -Encoding UTF8
    }

    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
    if (-not $drive -or ($drive.FreeSpace/1GB) -lt 20) { throw 'D: needs at least 20 GB free for Open WebUI, dependencies and audio cache.' }

    # Use the existing Python 3.11.9 reported by the diagnostic. Python 3.11 and 3.12 are supported.
    $venv = Join-Path $Platform '.venv'
    $VenvPython = Join-Path $venv 'Scripts\python.exe'
    $PythonVersion = $null
    if (Test-Path $VenvPython) {
        $existing = Invoke-NativeLogged -Executable $VenvPython -Arguments @('-c','import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")') -Label 'Check existing project Python'
        if ($existing.ExitCode -eq 0 -and (($existing.StdOut.Trim() -eq '3.11') -or ($existing.StdOut.Trim() -eq '3.12'))) { $PythonVersion = $existing.StdOut.Trim() }
        else {
            $backup = Join-Path $Platform ('.venv-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Write-Host "Existing invalid/incompatible virtualenv will be preserved as $backup" -ForegroundColor Yellow
            Move-Item -LiteralPath $venv -Destination $backup
        }
    }
    if (-not (Test-Path $VenvPython)) {
        $python = Find-Python
        if (-not $python) { throw 'Python 3.11 or 3.12 was not found. Install Python 3.11/3.12 from python.org, then rerun this installer.' }
        $PythonVersion = $python.Version
        if ($python.Prefix) { $venvArgs = @($python.Prefix + @('-m','venv',$venv)) }
        else { $venvArgs = @('-m','venv',$venv) }
        $null = Invoke-Python $python.Exe $venvArgs 'Create isolated platform virtual environment'
    }
    if (-not (Test-Path $VenvPython)) { throw 'The project virtual environment was not created.' }
    $actual = Invoke-NativeLogged -Executable $VenvPython -Arguments @('-c','import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")') -Label 'Verify virtual environment Python'
    if ($actual.ExitCode -ne 0 -or $actual.StdOut -notmatch '^3\.(11|12)\.') { throw 'The project venv is not running supported Python 3.11/3.12.' }
    $PythonVersion = ($actual.StdOut -split "`r?`n" | Select-Object -First 1).Trim()
    Write-Host "[OK] Project venv uses Python $PythonVersion." -ForegroundColor Green

    $env:PIP_CACHE_DIR = Join-Path $Cache 'pip'
    $env:PIP_PROGRESS_BAR = 'on'
    $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
    $env:PIP_DEFAULT_TIMEOUT = '180'
    $env:PIP_RETRIES = '5'
    $env:HF_HOME = Join-Path $Data 'cache\huggingface'
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
    $env:WHISPER_MODEL_DIR = Join-Path $Data 'cache\whisper\models'
    New-Item -ItemType Directory -Force -Path $env:PIP_CACHE_DIR,$env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE,$env:WHISPER_MODEL_DIR | Out-Null

    $null = Invoke-Python $VenvPython @('-m','pip','install','--upgrade','pip','setuptools','wheel','--retries','5','--timeout','180','--disable-pip-version-check') 'Upgrade pip build tools'
    $webuiPackage = 'open-webui==' + $RequiredWebUI
    $null = Invoke-Python $VenvPython @('-m','pip','install','--progress-bar','on','--prefer-binary','--retries','5','--timeout','180','--disable-pip-version-check',$webuiPackage) "Install Open WebUI $RequiredWebUI"
    # The official audio troubleshooting guide pins PyAV 14.0.1 for Local Whisper on pip installs.
    $null = Invoke-Python $VenvPython @('-m','pip','install','--retries','5','--timeout','180','--disable-pip-version-check','av==14.0.1','faster-whisper') 'Install compatible local audio dependencies'
    $null = Invoke-Python $VenvPython @('-m','pip','check') 'Check Python dependency consistency'
    $probeCode = 'import open_webui, av, faster_whisper; from importlib.metadata import version; print("OPEN_WEBUI="+version("open-webui")); print("AV="+av.__version__); print("FASTER_WHISPER="+version("faster-whisper"))'
    $probe = Invoke-NativeLogged -Executable $VenvPython -Arguments @('-c',$probeCode) -Label 'Verify Open WebUI and audio imports'
    if ($probe.ExitCode -ne 0 -or $probe.StdOut -notmatch 'OPEN_WEBUI=0\.13\.5' -or $probe.StdOut -notmatch 'AV=14\.0\.1' -or $probe.StdOut -notmatch 'FASTER_WHISPER=') {
        throw 'Open WebUI/audio import verification failed. See the detailed probe log.'
    }
    $OpenWebUIExe = Join-Path $venv 'Scripts\open-webui.exe'
    if (-not (Test-Path $OpenWebUIExe)) { throw 'open-webui.exe is missing from the virtual environment after installation.' }

    # Install/locate FFmpeg. A failure is non-fatal for text chat, but is reported as an audio warning.
    $FfmpegExe = Get-Ffmpeg
    if (-not $FfmpegExe) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            $wg = Invoke-NativeLogged -Executable $winget.Source -Arguments @('install','--exact','--id','Gyan.FFmpeg','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent') -Label 'Install FFmpeg (Gyan.FFmpeg)' -NoticeSeconds 45
            Refresh-UserPath
            $FfmpegExe = Get-Ffmpeg
            if (-not $FfmpegExe) { $null = $Warnings.Add('FFmpeg installation was attempted but ffmpeg.exe is still not discoverable. Text chat works; local audio preprocessing needs FFmpeg.') }
        } else { $null = $Warnings.Add('WinGet was not available; FFmpeg is missing. Text chat works; local audio preprocessing needs FFmpeg.') }
    }
    if ($FfmpegExe) {
        # Ensure ffmpeg.exe is visible to child processes such as Open WebUI/PyDub.
        $ffmpegDir = Split-Path -Parent $FfmpegExe
        if (($env:Path -split ';') -notcontains $ffmpegDir) { $env:Path = $ffmpegDir + ';' + $env:Path }
        # Store the exact executable path for the launcher instead of mutating the user's global PATH.
        Set-Content -Path (Join-Path $Platform 'ffmpeg-path.txt') -Value $FfmpegExe -Encoding UTF8
        $ff = Invoke-NativeLogged -Executable $FfmpegExe -Arguments @('-version') -Label 'Validate FFmpeg executable'
        if ($ff.ExitCode -ne 0) { $null = $Warnings.Add('FFmpeg was found but its version command failed.') }
        else { $FfmpegLine = ($ff.StdOut -split "`r?`n" | Select-Object -First 1); Write-Host "[OK] $FfmpegLine" -ForegroundColor Green }
    }

    # Pre-download Whisper Small in a short-lived child process; no model remains resident in RAM.
    # If Hugging Face is temporarily unreachable, platform installation still completes with a warning.
    $env:OMP_NUM_THREADS = '3'
    $env:CT2_FORCE_CPU = '1'
    $env:HF_HUB_ETAG_TIMEOUT = '30'
    $env:HF_HUB_DOWNLOAD_TIMEOUT = '120'
    $env:HF_HUB_DISABLE_TELEMETRY = '1'
    $whisperCode = 'import os; from faster_whisper import WhisperModel; m=WhisperModel("small",device="cpu",compute_type="int8",download_root=os.environ["WHISPER_MODEL_DIR"]); print("WHISPER_SMALL_READY")'
    $whisper = Invoke-NativeLogged -Executable $VenvPython -Arguments @('-c',$whisperCode) -Label 'Download and validate Whisper Small (multilingual CPU INT8)' -NoticeSeconds 45
    if ($whisper.ExitCode -ne 0 -or $whisper.StdOut -notmatch 'WHISPER_SMALL_READY') {
        $null = $Warnings.Add('Whisper Small download/load test did not complete. Open WebUI is installed; speech-to-text will need retry after network is available.')
    }

    # Keep one stable random signing key. It is never printed or included in the package.
    $secret = Join-Path $Platform 'Secrets\webui_secret_key.txt'
    if (-not (Test-Path $secret)) {
        $bytes = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($bytes); $rng.Dispose()
        [IO.File]::WriteAllText($secret,([BitConverter]::ToString($bytes) -replace '-','').ToLowerInvariant())
    }
    $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $icacls = Get-Command icacls.exe -ErrorAction Stop
    $acl = Invoke-NativeLogged -Executable $icacls.Source -Arguments @($secret,'/inheritance:r','/grant:r',($account+':(F)'),'SYSTEM:(F)') -Label 'Protect WebUI signing key'
    if ($acl.ExitCode -ne 0) { $null = $Warnings.Add('Could not restrict signing-key ACL. Review Windows folder permissions before storing sensitive chats.') }

    # Install only the platform files; do not touch D:\LocalAI\Models or the Ollama server.
    Copy-Item -Path (Join-Path $PSScriptRoot 'Filters\*.py') -Destination $FilterDir -Force
    Copy-Item (Join-Path $PSScriptRoot 'TEST-FILTERS.py') (Join-Path $Platform 'TEST-FILTERS.py') -Force
    Copy-Item (Join-Path $PSScriptRoot 'START-CHAT.bat') (Join-Path $Platform 'START-CHAT.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'START-CHAT.ps1') (Join-Path $Platform 'START-CHAT.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'STOP-CHAT.bat') (Join-Path $Platform 'STOP-CHAT.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'STOP-CHAT.ps1') (Join-Path $Platform 'STOP-CHAT.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'CHECK-LOCALAI.bat') (Join-Path $Platform 'CHECK-LOCALAI.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'CHECK-LOCALAI.ps1') (Join-Path $Platform 'CHECK-LOCALAI.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'VERIFY-MODEL.bat') (Join-Path $Platform 'VERIFY-MODEL.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'VERIFY-MODEL.ps1') (Join-Path $Platform 'VERIFY-MODEL.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'IMPORT-FILTERS.bat') (Join-Path $Platform 'IMPORT-FILTERS.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'IMPORT-FILTERS.ps1') (Join-Path $Platform 'IMPORT-FILTERS.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'FILTER-IMPORT-GUIDE-AR.md') (Join-Path $Platform 'FILTER-IMPORT-GUIDE-AR.md') -Force
    Copy-Item (Join-Path $PSScriptRoot 'README-AR.md') (Join-Path $Platform 'README-AR-INTEGRATION.md') -Force

    $filterTest = Invoke-NativeLogged -Executable $VenvPython -Arguments @((Join-Path $Platform 'TEST-FILTERS.py'),'--filters-dir',$FilterDir) -Label 'Run filter syntax and behavior tests'
    if ($filterTest.ExitCode -ne 0 -or $filterTest.StdOut -notmatch 'FILTER_TESTS: SUCCESS') { throw 'Filter tests did not pass. See the filter-test child log.' }

    $status = if ($Warnings.Count -gt 0) { 'SUCCESS_WITH_WARNINGS' } else { 'SUCCESS' }
    $warningText = if ($Warnings.Count -gt 0) { $Warnings -join "`r`n- " } else { 'None' }
    @"
STATUS: $status
Open WebUI: $RequiredWebUI
Python: $PythonVersion
Ollama URL: http://127.0.0.1:11434
Verified model tag: $ModelId
Platform: $Platform
Data: $Data
Open WebUI executable: $OpenWebUIExe
FFmpeg: $FfmpegExe
Whisper: small / multilingual / CPU INT8 / VAD enabled by launcher
Filter sources copied: 3; syntax and behavior tests passed
Web search: ENABLE_WEB_SEARCH=true; WEB_SEARCH_ENGINE=duckduckgo; DDGS_BACKEND=auto
Network scope: localhost only (127.0.0.1:8080)
Warnings:
- $warningText
Installer log: $LogFile
IMPORTANT: The model was not downloaded or modified by this installer.
"@ | Set-Content -Path $StatusFile -Encoding UTF8
    @"
STATUS: $status
Ollama: $($version.version)
Model: $ModelId
Open WebUI: $RequiredWebUI
Platform: $Platform
Warnings: $warningText
Completed: $(Get-Date -Format o)
"@ | Set-Content -Path $FullStatusFile -Encoding UTF8

    Write-Host "`nPLATFORM INSTALLATION $status" -ForegroundColor Green
    Write-Host "Open WebUI: $RequiredWebUI; Model: $ModelId; Python: $PythonVersion"
    Write-Host "Status: $StatusFile"
    Write-Host "Log: $LogFile"
    if ($Warnings.Count -gt 0) {
        Write-Host 'Warnings:' -ForegroundColor Yellow
        foreach ($w in $Warnings) { Write-Host (' - '+$w) -ForegroundColor Yellow }
    }
    Write-Host 'Next: run D:\LocalAI\Platform\START-CHAT.bat, create the first administrator, then import filters.' -ForegroundColor Cyan
}
catch {
    $msg = $_.Exception.Message
    $Failures.Add($msg)
    @"
STATUS: FAILED
Error: $msg
Installer log: $LogFile
Existing Ollama/Qwen model files were not intentionally deleted or modified.
"@ | Set-Content -Path $StatusFile -Encoding UTF8
    @"
STATUS: FAILED
Error: $msg
Completed: $(Get-Date -Format o)
"@ | Set-Content -Path $FullStatusFile -Encoding UTF8
    Write-Host "`nPLATFORM INSTALLATION FAILED: $msg" -ForegroundColor Red
    Write-Host "Read the newest platform-continuation log in $Logs" -ForegroundColor Yellow
    exit 1
}
finally {
    if ($script:KeepAwakeEnabled -and ('LocalAI.PowerManagement' -as [type])) {
        # ES_CONTINUOUS alone clears this installer's temporary stay-awake request.
        [void][LocalAI.PowerManagement]::SetThreadExecutionState([Convert]::ToUInt32('2147483648'))
    }
    try { Stop-Transcript | Out-Null } catch {}
}
