$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Logs = Join-Path $Root 'Logs'
$FilterDir = Join-Path $Platform 'Filters'
New-Item -ItemType Directory -Force -Path $Platform, $Data, $Logs, $FilterDir, (Join-Path $Data 'cache\whisper\models') | Out-Null
$LogFile = Join-Path $Logs ('platform-install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $LogFile -Force | Out-Null
$StatusFile = Join-Path $Platform 'PLATFORM-STATUS.txt'
$RequiredWebUI = '0.13.4'

function ConvertTo-ProcessArgumentLine([string[]]$Arguments) {
    $quoted = @()
    foreach ($argument in $Arguments) { $quoted += ('"' + ([string]$argument).Replace('"','\"') + '"') }
    return [string]::Join(' ', $quoted)
}
function Invoke-NativeLogged([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $id = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $Logs ($id + '.stdout.tmp')
    $stderrPath = Join-Path $Logs ($id + '.stderr.tmp')
    $proc = $null
    try {
        $argLine = ConvertTo-ProcessArgumentLine $Arguments
        Write-Host "$Label ..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $Executable -ArgumentList $argLine -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        $lastNotice = Get-Date
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 15
            $proc.Refresh()
            if (-not $proc.HasExited -and ((Get-Date) - $lastNotice).TotalSeconds -ge 45) {
                Write-Host "$Label is still running (PID $($proc.Id)); leave this window open." -ForegroundColor Yellow
                $lastNotice = Get-Date
            }
        }
        $proc.WaitForExit()
        $stdout = if (Test-Path $stdoutPath) { [System.IO.File]::ReadAllText($stdoutPath) } else { '' }
        $stderr = if (Test-Path $stderrPath) { [System.IO.File]::ReadAllText($stderrPath) } else { '' }
        foreach ($line in ($stdout -replace "`r", "`n" -split "`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line } }
        foreach ($line in ($stderr -replace "`r", "`n" -split "`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line -ForegroundColor DarkYellow } }
        return [pscustomobject]@{ ExitCode=[int]$proc.ExitCode; StdOut=$stdout; StdErr=$stderr }
    }
    finally { Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue }
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $wingetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $env:Path = @($machine, $user, $wingetLinks) -join ';'
}
function Find-Python312 {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        try {
            $probe = Invoke-NativeLogged -Executable $launcher.Source -Arguments @('-3.12','--version') -Label 'Check Python 3.12 launcher'
            if ($probe.ExitCode -eq 0 -and (($probe.StdOut + $probe.StdErr) -match 'Python\s+3\.12')) { return @{ Launcher=$launcher.Source; Prefix=@('-3.12') } }
        } catch {}
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe'),
        'C:\Python312\python.exe'
    )
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return @{ Launcher=$candidate; Prefix=@() } } }
    return $null
}
function Invoke-Python([string]$PythonExe, [string[]]$Prefix, [string[]]$Arguments) {
    $allArgs = @()
    if ($Prefix) { $allArgs += $Prefix }
    if ($Arguments) { $allArgs += $Arguments }
    $result = Invoke-NativeLogged -Executable $PythonExe -Arguments $allArgs -Label ("Python: " + ($Arguments -join ' '))
    if ($result.ExitCode -ne 0) { throw "Python command failed (exit code $($result.ExitCode)): $($Arguments -join ' '). $($result.StdErr)" }
    return $result
}

try {
    if (Test-Path $StatusFile) { Remove-Item $StatusFile -Force -ErrorAction Stop }
    Write-Host 'LOCAL AI CHAT PLATFORM INSTALLER - Open WebUI 0.13.4' -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $Root 'ENGINE-STATUS.txt'))) { throw 'Engine package 01 is not installed. Complete 01-LocalAI-Engine first.' }
    $engineStatus = Get-Content (Join-Path $Root 'ENGINE-STATUS.txt') -Raw
    if ($engineStatus -notmatch 'STATUS:\s*SUCCESS') { throw 'Engine status is not SUCCESS. Re-run package 01 and verify the model test.' }
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3 | Out-Null } catch { throw 'Ollama is not running. Start D:\LocalAI\START-ENGINE.bat first.' }
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
    if (-not ($tags.models | Where-Object { $_.name -like 'local-qwen35*' })) { throw 'Model alias local-qwen35 is missing from Ollama. Re-run package 01.' }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget is missing. Install Microsoft App Installer from Microsoft Store, restart Windows, and retry.' }
    $dataDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
    if (-not $dataDrive -or ($dataDrive.FreeSpace / 1GB) -lt 15) { throw 'At least 15 GB free on D: is required for the Python environment, Open WebUI, and Whisper Small.' }
    $cacheRoot = Join-Path $Root 'Cache'
    $pipCache = Join-Path $cacheRoot 'pip'
    $hfCache = Join-Path $Data 'cache\huggingface'
    New-Item -ItemType Directory -Force -Path $cacheRoot, $pipCache, $hfCache | Out-Null
    $env:PIP_CACHE_DIR = $pipCache
    $env:HF_HOME = $hfCache
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $hfCache 'hub'

    $pythonInfo = Find-Python312
    if (-not $pythonInfo) {
        Write-Host 'Installing Python 3.12...' -ForegroundColor Yellow
        $winget = Get-Command winget.exe -ErrorAction Stop
        $wingetResult = Invoke-NativeLogged -Executable $winget.Source -Arguments @('install','--exact','--id','Python.Python.3.12','--source','winget','--scope','user','--accept-package-agreements','--accept-source-agreements','--silent') -Label 'Install Python 3.12 with WinGet'
        if ($wingetResult.ExitCode -ne 0) { throw "Python 3.12 installation failed (winget exit code $($wingetResult.ExitCode)). $($wingetResult.StdErr)" }
        Refresh-Path
        $pythonInfo = Find-Python312
    }
    if (-not $pythonInfo) { throw 'Python 3.12 was not detected after installation. Restart Windows, then rerun this package.' }

    # FFmpeg is required for audio preprocessing and long recording chunking.
    Refresh-Path
    if (-not (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing FFmpeg static full build from WinGet...' -ForegroundColor Yellow
        $winget = Get-Command winget.exe -ErrorAction Stop
        $wingetResult = Invoke-NativeLogged -Executable $winget.Source -Arguments @('install','--exact','--id','Gyan.FFmpeg','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent') -Label 'Install FFmpeg with WinGet'
        if ($wingetResult.ExitCode -ne 0) { throw "FFmpeg installation failed (winget exit code $($wingetResult.ExitCode)). $($wingetResult.StdErr)" }
        Refresh-Path
    }
    $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        $ffmpegCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'),
            (Join-Path $env:ProgramFiles 'FFmpeg\bin\ffmpeg.exe'),
            'C:\ffmpeg\bin\ffmpeg.exe'
        )
        $ffmpegPath = $ffmpegCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $ffmpegPath) {
            $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            if (Test-Path $wingetPackages) {
                $ffmpegPath = Get-ChildItem -Path $wingetPackages -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -match 'Gyan\.FFmpeg' } | Select-Object -ExpandProperty FullName -First 1
            }
        }
        if ($ffmpegPath) {
            $ffmpegDir = Split-Path $ffmpegPath -Parent
            $userPath = [string][Environment]::GetEnvironmentVariable('Path','User')
            if (($userPath -split ';') -notcontains $ffmpegDir) {
                $newUserPath = (($userPath.TrimEnd(';') + ';' + $ffmpegDir).Trim(';'))
                [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            }
            Refresh-Path
            $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
        }
    }
    if (-not $ffmpeg) { throw 'FFmpeg was installed but ffmpeg.exe is not on PATH. Restart Windows, verify `ffmpeg -version`, then rerun the installer.' }
    $ffmpegResult = Invoke-NativeLogged -Executable $ffmpeg.Source -Arguments @('-version') -Label 'Validate FFmpeg'
    if ($ffmpegResult.ExitCode -ne 0) { throw 'FFmpeg executable was found but failed its version check.' }
    $ffmpegVersion = ($ffmpegResult.StdOut + $ffmpegResult.StdErr) -split "`r?`n" | Select-Object -First 1
    Write-Host $ffmpegVersion -ForegroundColor DarkGray

    $venv = Join-Path $Platform '.venv'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    $venvIs312 = $false
    if (Test-Path $venvPython) {
        try {
            $versionProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import sys;print(str(sys.version_info.major)+'.'+str(sys.version_info.minor))") -Label 'Check existing virtual environment version'
            $venvVersion = ($versionProbe.StdOut + $versionProbe.StdErr).Trim()
            $venvIs312 = ($versionProbe.ExitCode -eq 0 -and $venvVersion -eq '3.12')
        } catch { $venvIs312 = $false }
    }
    if ((Test-Path $venvPython) -and -not $venvIs312) {
        $backupVenv = Join-Path $Platform ('.venv-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Host "Existing virtual environment is not Python 3.12; moving it to $backupVenv" -ForegroundColor Yellow
        Move-Item -Path $venv -Destination $backupVenv
    }
    if (-not (Test-Path $venvPython)) {
        Write-Host 'Creating the isolated Python 3.12 environment...' -ForegroundColor Yellow
        Invoke-Python $pythonInfo.Launcher $pythonInfo.Prefix @('-m','venv',$venv)
    }
    if (-not (Test-Path $venvPython)) { throw 'The Python virtual environment was not created.' }
    $actualVenvProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import sys;print(str(sys.version_info.major)+'.'+str(sys.version_info.minor))") -Label 'Validate virtual environment Python'
    if ($actualVenvProbe.ExitCode -ne 0) { throw 'Could not query Python version inside the virtual environment.' }
    $actualVenvVersion = ($actualVenvProbe.StdOut + $actualVenvProbe.StdErr).Trim()
    if ($actualVenvVersion -ne '3.12') { throw "The virtual environment uses Python $actualVenvVersion instead of 3.12." }

    Invoke-Python $venvPython @() @('-m','pip','install','--upgrade','pip','setuptools','wheel')
    $installedVersion = $null
    try {
        $showResult = Invoke-NativeLogged -Executable $venvPython -Arguments @('-m','pip','show','open-webui') -Label 'Check installed Open WebUI version'
        $versionLine = [regex]::Match(($showResult.StdOut + "`n" + $showResult.StdErr), '(?m)^Version:\s*(.+)$')
        if ($showResult.ExitCode -eq 0 -and $versionLine.Success) { $installedVersion = $versionLine.Groups[1].Value.Trim() }
    } catch {}
    if ([string]$installedVersion -ne $RequiredWebUI) {
        Write-Host "Installing pinned Open WebUI $RequiredWebUI..." -ForegroundColor Yellow
        Invoke-Python $venvPython @() @('-m','pip','install',"open-webui==$RequiredWebUI")
    }
    $showResult = Invoke-NativeLogged -Executable $venvPython -Arguments @('-m','pip','show','open-webui') -Label 'Verify Open WebUI installation'
    $versionLine = [regex]::Match(($showResult.StdOut + "`n" + $showResult.StdErr), '(?m)^Version:\s*(.+)$')
    if ($showResult.ExitCode -ne 0 -or -not $versionLine.Success) { throw 'Could not verify installed Open WebUI package with pip show.' }
    $installedVersion = $versionLine.Groups[1].Value.Trim()
    if ($installedVersion -ne $RequiredWebUI) { throw "Open WebUI version check failed. Expected $RequiredWebUI; found $installedVersion." }
    # Pin the PyAV build documented by Open WebUI for local Whisper compatibility on pip installs.
    Invoke-Python $venvPython @() @('-m','pip','install','av==14.0.1')
    $openWebUI = Join-Path $venv 'Scripts\open-webui.exe'
    if (-not (Test-Path $openWebUI)) { throw 'open-webui.exe was not created. Review pip errors in the install log.' }

    # Ensure the local Whisper backend dependency is present in the same venv as Open WebUI.
    $fasterWhisperProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import faster_whisper;print('FASTER_WHISPER_READY')") -Label 'Check faster-whisper dependency'
    if ($fasterWhisperProbe.ExitCode -ne 0 -or (($fasterWhisperProbe.StdOut + $fasterWhisperProbe.StdErr) -notmatch 'FASTER_WHISPER_READY')) {
        Invoke-Python $venvPython @() @('-m','pip','install','faster-whisper')
        $fasterWhisperProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import faster_whisper;print('FASTER_WHISPER_READY')") -Label 'Verify faster-whisper dependency'
        if ($fasterWhisperProbe.ExitCode -ne 0 -or (($fasterWhisperProbe.StdOut + $fasterWhisperProbe.StdErr) -notmatch 'FASTER_WHISPER_READY')) { throw 'faster-whisper could not be installed or imported in the Open WebUI environment.' }
    }

    # Download and load Whisper Small once now, so first voice use does not surprise the user with a large download.
    $whisperModelDir = Join-Path $Data 'cache\whisper\models'
    New-Item -ItemType Directory -Force -Path $whisperModelDir | Out-Null
    $env:WHISPER_MODEL_DIR = $whisperModelDir
    $env:OMP_NUM_THREADS = '4'
    Write-Host 'Downloading and validating multilingual Whisper Small (CPU INT8)...' -ForegroundColor Yellow
    $whisperCode = "import os;from faster_whisper import WhisperModel;m=WhisperModel('small',device='cpu',compute_type='int8',download_root=os.environ['WHISPER_MODEL_DIR']);print('WHISPER_SMALL_READY')"
    $whisperResult = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',$whisperCode) -Label 'Download and validate Whisper Small (CPU INT8)'
    if ($whisperResult.ExitCode -ne 0 -or (($whisperResult.StdOut + $whisperResult.StdErr) -notmatch 'WHISPER_SMALL_READY')) { throw "Whisper Small could not be downloaded or loaded. $($whisperResult.StdErr)" }

    # Persistent per-install key. Never print or place the key in the ZIP.
    $secretPath = Join-Path $Platform 'webui_secret_key.txt'
    if (-not (Test-Path $secretPath)) {
        $bytes = New-Object byte[] 48
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes); $rng.Dispose()
        [System.IO.File]::WriteAllText($secretPath, ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant())
    }
    # Restrict the signing key to this Windows account and SYSTEM.
    $currentAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $icacls = Get-Command icacls.exe -ErrorAction Stop
    $aclResult = Invoke-NativeLogged -Executable $icacls.Source -Arguments @($secretPath,'/inheritance:r','/grant:r',"$($currentAccount):(F)",'SYSTEM:(F)') -Label 'Protect the Open WebUI signing key'
    if ($aclResult.ExitCode -ne 0) { throw 'Could not apply private permissions to the Open WebUI signing key. Check folder permissions.' }

    Copy-Item -Path (Join-Path $PSScriptRoot 'Filters\*.py') -Destination $FilterDir -Force
    Copy-Item (Join-Path $PSScriptRoot 'README-AR.md') (Join-Path $Platform 'README-AR-INTEGRATION.md') -Force
    Copy-Item (Join-Path $PSScriptRoot 'FILTER-IMPORT-GUIDE-AR.md') (Join-Path $Platform 'FILTER-IMPORT-GUIDE-AR.md') -Force
    Copy-Item (Join-Path $PSScriptRoot 'START-CHAT.bat') (Join-Path $Platform 'START-CHAT.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'START-CHAT.ps1') (Join-Path $Platform 'START-CHAT.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'CHECK-LOCALAI.bat') (Join-Path $Platform 'CHECK-LOCALAI.bat') -Force
    Copy-Item (Join-Path $PSScriptRoot 'CHECK-LOCALAI.ps1') (Join-Path $Platform 'CHECK-LOCALAI.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'TEST-FILTERS.py') (Join-Path $Platform 'TEST-FILTERS.py') -Force
    Copy-Item (Join-Path $PSScriptRoot 'IMPORT-FILTERS.ps1') (Join-Path $Platform 'IMPORT-FILTERS.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'IMPORT-FILTERS.bat') (Join-Path $Platform 'IMPORT-FILTERS.bat') -Force

    # Compile and behavior-test every filter using the exact Python environment that runs Open WebUI.
    $filterTest = Invoke-NativeLogged -Executable $venvPython -Arguments @((Join-Path $Platform 'TEST-FILTERS.py'),'--filters-dir',$FilterDir) -Label 'Run all Python filter syntax and behavior tests'
    if ($filterTest.ExitCode -ne 0) { throw "One or more Python filter tests failed. $($filterTest.StdErr)" }

    @"
STATUS: SUCCESS
Open WebUI version: $RequiredWebUI
Python: 3.12
FFmpeg: $($ffmpeg.Source)
Ollama URL: http://127.0.0.1:11434
Model alias: local-qwen35
Web URL: http://127.0.0.1:8080
Data: $Data
Whisper: small / multilingual / int8 / VAD enabled by launcher
Filters copied: 3; Python syntax and behavior tests passed
Web Search: DDGS Auto; confirmation required before external query
API Keys: enabled for the local administrator filter-import helper on first launch
Whisper model: small multilingual, downloaded and load-tested (CPU INT8)
Log: $LogFile
"@ | Set-Content -Path (Join-Path $Platform 'PLATFORM-STATUS.txt') -Encoding UTF8

    Write-Host "`nSUCCESS: Open WebUI $RequiredWebUI installed; FFmpeg found; Whisper Small cached and load-tested; 3 filter tests passed; API importer installed." -ForegroundColor Green
    Write-Host "Next: start D:\LocalAI\Platform\START-CHAT.bat, create the first admin account, then run D:\LocalAI\Platform\IMPORT-FILTERS.bat."
}
catch {
    Write-Host "PLATFORM INSTALL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally { Stop-Transcript | Out-Null }
