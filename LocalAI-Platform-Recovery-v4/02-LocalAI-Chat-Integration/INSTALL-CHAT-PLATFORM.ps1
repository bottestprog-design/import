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
function Find-PythonCompatible {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        foreach ($version in @('3.12','3.11')) {
            try {
                $probe = Invoke-NativeLogged -Executable $launcher.Source -Arguments @("-$version",'--version') -Label "Check Python $version launcher"
                if ($probe.ExitCode -eq 0 -and (($probe.StdOut + $probe.StdErr) -match ("Python\s+" + [regex]::Escape($version)))) {
                    return @{ Launcher=$launcher.Source; Prefix=@("-$version"); Version=$version }
                }
            } catch {}
        }
    }
    $candidates = @(
        @{Path=(Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe');Version='3.12'},
        @{Path=(Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe');Version='3.11'},
        @{Path=(Join-Path $env:ProgramFiles 'Python312\python.exe');Version='3.12'},
        @{Path=(Join-Path $env:ProgramFiles 'Python311\python.exe');Version='3.11'},
        @{Path='C:\Python312\python.exe';Version='3.12'},
        @{Path='C:\Python311\python.exe';Version='3.11'}
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate.Path -PathType Leaf) {
            try {
                $probe = Invoke-NativeLogged -Executable $candidate.Path -Arguments @('--version') -Label 'Check installed Python'
                if ($probe.ExitCode -eq 0 -and (($probe.StdOut + $probe.StdErr) -match ("Python\s+" + [regex]::Escape($candidate.Version)))) {
                    return @{ Launcher=$candidate.Path; Prefix=@(); Version=$candidate.Version }
                }
            } catch {}
        }
    }
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
    if (Test-Path $StatusFile) { Copy-Item -LiteralPath $StatusFile -Destination ($StatusFile + '.before-recovery-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force }
    Write-Host 'LOCAL AI CHAT PLATFORM INSTALLER - Open WebUI 0.13.4' -ForegroundColor Cyan
    # Verify the already-installed engine directly. Never pull/reinstall Ollama or touch model blobs here.
    try { $ollamaVersion = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 8 } catch { throw 'Ollama API is not responding at 127.0.0.1:11434. This repair deliberately does not restart or reinstall the engine.' }
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    $modelTag = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -eq 'local-qwen35' } | Select-Object -First 1
    if (-not $modelTag) { throw 'The existing Ollama API does not list local-qwen35. This repair will not download a replacement model.' }
    $dataDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
    if (-not $dataDrive -or ($dataDrive.FreeSpace / 1GB) -lt 15) { throw 'At least 15 GB free on D: is required for the isolated Python environment, Open WebUI, and audio model cache.' }
    $cacheRoot = Join-Path $Root 'Cache'
    $pipCache = Join-Path $cacheRoot 'pip'
    $hfCache = Join-Path $Data 'cache\huggingface'
    New-Item -ItemType Directory -Force -Path $cacheRoot, $pipCache, $hfCache | Out-Null
    $env:PIP_CACHE_DIR = $pipCache
    $env:HF_HOME = $hfCache
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $hfCache 'hub'

    $pythonInfo = Find-PythonCompatible
    if (-not $pythonInfo) {
        Write-Host 'Installing Python 3.12 (no compatible 3.11/3.12 interpreter was found)...' -ForegroundColor Yellow
        $winget = Get-Command winget.exe -ErrorAction Stop
        $wingetResult = Invoke-NativeLogged -Executable $winget.Source -Arguments @('install','--exact','--id','Python.Python.3.12','--source','winget','--scope','user','--accept-package-agreements','--accept-source-agreements','--silent') -Label 'Install Python 3.12 with WinGet'
        if ($wingetResult.ExitCode -ne 0) { throw "Python 3.12 installation failed (winget exit code $($wingetResult.ExitCode)). $($wingetResult.StdErr)" }
        Refresh-Path
        $pythonInfo = Find-PythonCompatible
    }
    if (-not $pythonInfo) { throw 'Python 3.11 or 3.12 was not detected after installation. Restart Windows, then rerun this package.' }

    $ffmpeg = $null
    $audioWarnings = @()
    try {
        # FFmpeg is required for audio preprocessing; keep text chat installable if optional audio setup fails.
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

    } catch {
        $audioWarnings += ('FFmpeg: ' + $_.Exception.Message)
        Write-Host ('AUDIO WARNING: FFmpeg is not ready; text chat can still run. ' + $_.Exception.Message) -ForegroundColor Yellow
    }

    $venv = Join-Path $Platform '.venv'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    $venvIsSupported = $false
    if (Test-Path $venvPython) {
        try {
            $versionProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import sys;print(str(sys.version_info.major)+'.'+str(sys.version_info.minor))") -Label 'Check existing virtual environment version'
            $venvVersion = ($versionProbe.StdOut + $versionProbe.StdErr).Trim()
            $venvIsSupported = ($versionProbe.ExitCode -eq 0 -and $venvVersion -in @('3.11','3.12'))
        } catch { $venvIsSupported = $false }
    }
    if ((Test-Path $venvPython) -and -not $venvIsSupported) {
        $backupVenv = Join-Path $Platform ('.venv-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Host "Existing virtual environment is not Python 3.11/3.12; moving it to $backupVenv" -ForegroundColor Yellow
        Move-Item -Path $venv -Destination $backupVenv
    }
    if (-not (Test-Path $venvPython)) {
        Write-Host "Creating the isolated Python $($pythonInfo.Version) environment..." -ForegroundColor Yellow
        Invoke-Python $pythonInfo.Launcher $pythonInfo.Prefix @('-m','venv',$venv)
    }
    if (-not (Test-Path $venvPython)) { throw 'The Python virtual environment was not created.' }
    $actualVenvProbe = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',"import sys;print(str(sys.version_info.major)+'.'+str(sys.version_info.minor))") -Label 'Validate virtual environment Python'
    if ($actualVenvProbe.ExitCode -ne 0) { throw 'Could not query Python version inside the virtual environment.' }
    $actualVenvVersion = ($actualVenvProbe.StdOut + $actualVenvProbe.StdErr).Trim()
    if ($actualVenvVersion -notin @('3.11','3.12')) { throw "The virtual environment uses unsupported Python $actualVenvVersion; expected 3.11 or 3.12." }

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
    $whisperReady = $false
    try {
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

        # Download and validate Whisper Base INT8 now; this is lighter for a 16 GB host.
        $whisperModelDir = Join-Path $Data 'cache\whisper\models'
        New-Item -ItemType Directory -Force -Path $whisperModelDir | Out-Null
        $env:WHISPER_MODEL_DIR = $whisperModelDir
        $env:OMP_NUM_THREADS = '4'
        Write-Host 'Downloading and validating multilingual Whisper Base (CPU INT8) for the 16 GB host...' -ForegroundColor Yellow
        $whisperCode = "import os;from faster_whisper import WhisperModel;m=WhisperModel('base',device='cpu',compute_type='int8',download_root=os.environ['WHISPER_MODEL_DIR']);print('WHISPER_BASE_READY')"
        $whisperResult = Invoke-NativeLogged -Executable $venvPython -Arguments @('-c',$whisperCode) -Label 'Download and validate Whisper Base (CPU INT8)'
        if ($whisperResult.ExitCode -ne 0 -or (($whisperResult.StdOut + $whisperResult.StdErr) -notmatch 'WHISPER_BASE_READY')) { throw "Whisper Base could not be downloaded or loaded. $($whisperResult.StdErr)" }

        $whisperReady = $true
    } catch {
        $audioWarnings += ('Whisper: ' + $_.Exception.Message)
        Write-Host ('AUDIO WARNING: local Whisper is not ready; chat remains installed. ' + $_.Exception.Message) -ForegroundColor Yellow
    }

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

    $filterBackupDir = Join-Path $Platform ('Backups\Filters-before-recovery-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($filterName in @('01-Trusted-Content-Guard.py','02-Accuracy-Thinking.py','03-Selective-Self-Review.py')) {
        $existingFilter = Join-Path $FilterDir $filterName
        if (Test-Path -LiteralPath $existingFilter -PathType Leaf) {
            New-Item -ItemType Directory -Force -Path $filterBackupDir | Out-Null
            Copy-Item -LiteralPath $existingFilter -Destination $filterBackupDir -Force
        }
    }
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
Python: $actualVenvVersion
FFmpeg: $($ffmpeg.Source)
Ollama URL: http://127.0.0.1:11434
Model alias: local-qwen35
Web URL: http://127.0.0.1:8080
Data: $Data
Whisper: base / multilingual / int8 / VAD enabled by launcher
Audio status: $(if ($audioWarnings.Count -eq 0 -and $whisperReady -and $ffmpeg) { 'READY' } else { 'PARTIAL - TEXT CHAT IS READY' })
Audio warnings: $($audioWarnings -join ' | ')
Filters copied: 3; Python syntax and behavior tests passed
Web Search: DDGS Auto; confirmation required before external query
API Keys: enabled for the local administrator filter-import helper on first launch
Whisper model: $(if ($whisperReady) { 'base multilingual downloaded and load-tested (CPU INT8)' } else { 'not verified; see audio warnings' })
Log: $LogFile
"@ | Set-Content -Path (Join-Path $Platform 'PLATFORM-STATUS.txt') -Encoding UTF8

    Write-Host "`nSUCCESS: Open WebUI $RequiredWebUI installed; 3 filter tests passed; API importer installed." -ForegroundColor Green
    if ($audioWarnings.Count -eq 0 -and $whisperReady -and $ffmpeg) { Write-Host 'Audio: FFmpeg + Whisper Base are ready.' -ForegroundColor Green } else { Write-Host ('Audio is partial; text chat is ready. ' + ($audioWarnings -join ' | ')) -ForegroundColor Yellow }
    Write-Host "Next: start D:\LocalAI\Platform\START-CHAT.bat, create the first admin account, then run D:\LocalAI\Platform\IMPORT-FILTERS.bat."
}
catch {
    Write-Host "PLATFORM INSTALL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally { Stop-Transcript | Out-Null }
