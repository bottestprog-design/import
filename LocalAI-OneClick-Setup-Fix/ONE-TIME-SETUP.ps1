$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Logs = Join-Path $Root 'Logs'
$Cache = Join-Path $Root 'Cache'
$Venv = Join-Path $Platform '.venv'
$Python = Join-Path $Venv 'Scripts\python.exe'
$OpenWebUI = Join-Path $Venv 'Scripts\open-webui.exe'
$FilterDir = Join-Path $Platform 'Filters'
New-Item -ItemType Directory -Force -Path $Root,$Platform,$Data,$Logs,$Cache,(Join-Path $Cache 'pip'),$FilterDir,(Join-Path $Platform 'Secrets'),(Join-Path $Data 'cache\whisper\models'),(Join-Path $Data 'cache\huggingface\hub') | Out-Null
$Log = Join-Path $Logs ('one-time-setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $Log -Force | Out-Null

function Fail([string]$Message) { throw $Message }
function Quote-Arg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value.Length -eq 0) { return '""' }
    # Arguments used here contain no embedded double quotes; quote whitespace safely.
    if ($Value -match '\s') { return '"' + $Value.Replace('"','\"') + '"' }
    return $Value
}
function Invoke-PythonProcess([string[]]$Arguments,[string]$Label,[int]$NoticeSeconds=30) {
    $id = [guid]::NewGuid().ToString('N')
    $out = Join-Path $Logs ($id + '.stdout.log')
    $err = Join-Path $Logs ($id + '.stderr.log')
    $argLine = (($Arguments | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
    Write-Host "`n>>> $Label" -ForegroundColor Cyan
    $proc = Start-Process -FilePath $Python -ArgumentList $argLine -PassThru -NoNewWindow `
        -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
    $lastNotice = Get-Date
    while ($true) {
        $proc.Refresh()
        if ($proc.HasExited) { break }
        Start-Sleep -Seconds 5
        $proc.Refresh()
        if (-not $proc.HasExited -and ((Get-Date)-$lastNotice).TotalSeconds -ge $NoticeSeconds) {
            Write-Host "$Label is still running (PID $($proc.Id)); output is being saved. Leave this window open." -ForegroundColor Yellow
            $lastNotice = Get-Date
        }
    }
    # Explicit WaitForExit is essential: HasExited alone did not reliably populate ExitCode
    # in the previous script's Process wrapper on this Windows PowerShell 5.1 installation.
    $proc.WaitForExit()
    $proc.Refresh()
    $exitCode = $null
    try {
        $rawExitCode = $proc.ExitCode
        if ($null -ne $rawExitCode) { $exitCode = [int]$rawExitCode }
    } catch { $exitCode = $null }
    $stdout = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out) } else { '' }
    $stderr = if (Test-Path -LiteralPath $err) { [IO.File]::ReadAllText($err) } else { '' }
    if ($null -eq $exitCode) {
        throw "$Label finished but Windows did not expose its exit code. Logs: $out ; $err"
    }
    foreach ($line in (($stdout -replace "`r", "`n") -split "`n" | Select-Object -Last 80)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line }
    }
    foreach ($line in (($stderr -replace "`r", "`n") -split "`n" | Select-Object -Last 80)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line -ForegroundColor DarkYellow }
    }
    return [pscustomobject]@{ ExitCode=$exitCode; StdOut=$stdout; StdErr=$stderr; StdOutPath=$out; StdErrPath=$err }
}
function Run-Python([string[]]$Arguments,[string]$Label) {
    $result = Invoke-PythonProcess -Arguments $Arguments -Label $Label
    if ($result.ExitCode -ne 0) {
        throw "$Label failed with exit code $($result.ExitCode). STDERR: $($result.StdErr) | STDOUT: $($result.StdOut) | Logs: $($result.StdOutPath) ; $($result.StdErrPath)"
    }
    return [string]$result.StdOut
}
function Get-InstalledPackageVersion([string]$Name) {
    $code = "import importlib.metadata as m; print(m.version('$Name'))"
    $result = Invoke-PythonProcess -Arguments @('-c',$code) -Label "Check installed package $Name" -NoticeSeconds 15
    if ($result.ExitCode -ne 0) { return $null }
    $value = (($result.StdOut -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    if ($value) { return $value.Trim() }
    return $null
}
function Find-Ffmpeg {
    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    if (($env:Path -split ';') -notcontains $links) { $env:Path = $links + ';' + $env:Path }
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $links 'ffmpeg.exe'),
        (Join-Path $env:ProgramFiles 'FFmpeg\bin\ffmpeg.exe'),
        'C:\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $packages) {
        $dirs = Get-ChildItem -LiteralPath $packages -Directory -Filter 'Gyan.FFmpeg*' -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            $found = Get-ChildItem -LiteralPath $dir.FullName -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return $null
}
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
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED: prevent idle sleep while pip/setup runs; display may turn off.
    $powerState = [LocalAI.PowerManagement]::SetThreadExecutionState([uint32]0x80000001)
    if ($powerState -ne 0) { $script:KeepAwakeEnabled = $true }
} catch { Write-Host "Temporary keep-awake request unavailable: $($_.Exception.Message)" -ForegroundColor Yellow }

function Set-Secret {
    $secretPath = Join-Path $Platform 'Secrets\webui_secret_key.txt'
    if (-not (Test-Path -LiteralPath $secretPath)) {
        $bytes = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $secret = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        [IO.File]::WriteAllText($secretPath,$secret,[Text.Encoding]::ASCII)
        $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Join-Path $env:WINDIR 'System32\icacls.exe'
        if (Test-Path -LiteralPath $acl) {
            $null = & $acl $secretPath '/inheritance:r' '/grant:r' ($account+':(F)') 'SYSTEM:(F)' 2>&1
        }
    }
}

try {
    Write-Host 'LOCALAI ONE-TIME SETUP / NO MODEL REINSTALL' -ForegroundColor Cyan
    Write-Host 'This package never installs/restarts Ollama and never downloads/deletes Qwen model blobs.'

    # Verify all expected package files before doing anything beyond the log folder.
    $manifestPath = Join-Path $PSScriptRoot 'MANIFEST-SHA256.txt'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Fail 'Package manifest missing. Apply the setup fix from the extracted package folder, then try again.' }
    $manifestLines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+(.+)$' })
    if ($manifestLines.Count -lt 10) { Fail 'Package manifest is incomplete. Re-extract the original ZIP and reapply the setup fix.' }
    foreach ($line in $manifestLines) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { continue }
        $expected = $matches[1].ToLowerInvariant()
        $relative = $matches[2].Trim().TrimStart('*')
        $path = Join-Path $PSScriptRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Package file is missing: $relative" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { Fail "Package integrity mismatch: $relative. Run APPLY-FIX.bat again or re-extract the package." }
    }
    Write-Host "[OK] Package integrity verified ($($manifestLines.Count) files)." -ForegroundColor Green

    # Refuse to collide with an active pip install.
    $busy = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match '(?i)(-m\s+pip|pip\.exe)' -and $_.CommandLine -match '(?i)open-webui|faster-whisper|av=='
    })
    if ($busy.Count -gt 0) {
        $ids = ($busy | ForEach-Object { $_.ProcessId }) -join ', '
        Fail "A Python package installation is still running (PID $ids). Wait for its window to finish before running setup again."
    }

    # Confirm the existing engine and model using only local Ollama APIs.
    try { $version = Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 8 }
    catch { Fail 'Ollama API is not responding on 127.0.0.1:11434. Open the Ollama app first; this setup will not restart it.' }
    $tags = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    $model = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' } | Select-Object -First 1
    if (-not $model) { $model = $tags.models | Where-Object { $_.name -like 'qwen3.5:9b-q4_K_M*' } | Select-Object -First 1 }
    if (-not $model) { Fail 'The existing Qwen tag is missing. This setup will not download or recreate a model.' }
    $ModelId = [string]$model.name
    Write-Host "[OK] Ollama $($version.version); model $ModelId ($([math]::Round($model.size/1GB,2)) GB)." -ForegroundColor Green

    # Reuse the exact virtual environment already created by the preceding installer.
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { Fail "Project Python is missing: $Python. Let the previous platform installer finish creating the environment first." }
    $pythonProbe = Run-Python @('-c','import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")') 'Check project Python'
    $pythonVersion = (($pythonProbe -split "`r?`n") | Where-Object { $_ -match '^3\.(11|12)\.' } | Select-Object -Last 1)
    if (-not $pythonVersion) { Fail "The project Python did not report version 3.11 or 3.12. Output: $pythonProbe" }
    Write-Host "[OK] Project Python $pythonVersion" -ForegroundColor Green

    $env:PIP_CACHE_DIR = Join-Path $Cache 'pip'
    $env:HF_HOME = Join-Path $Data 'cache\huggingface'
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
    $env:WHISPER_MODEL_DIR = Join-Path $Data 'cache\whisper\models'
    New-Item -ItemType Directory -Force -Path $env:PIP_CACHE_DIR,$env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE,$env:WHISPER_MODEL_DIR | Out-Null

    $openVersion = Get-InstalledPackageVersion 'open-webui'
    if (-not $openVersion) {
        $null = Run-Python @('-m','pip','install','--retries','5','--timeout','180','open-webui==0.13.4') 'Install Open WebUI 0.13.4'
        $openVersion = Get-InstalledPackageVersion 'open-webui'
    }
    if (-not $openVersion) { Fail 'Open WebUI remains missing after pip install. Inspect the newest .stderr.log and .stdout.log under D:\LocalAI\Logs.' }
    Write-Host "[OK] Open WebUI $openVersion" -ForegroundColor Green
    if (-not (Test-Path -LiteralPath $OpenWebUI -PathType Leaf)) { Fail "Open WebUI launcher missing: $OpenWebUI" }

    $avVersion = Get-InstalledPackageVersion 'av'
    $whisperVersion = Get-InstalledPackageVersion 'faster-whisper'
    if (-not $avVersion -or -not $whisperVersion) {
        $null = Run-Python @('-m','pip','install','--retries','5','--timeout','180','av==14.0.1','faster-whisper') 'Install missing audio dependencies'
    }
    $null = Run-Python @('-m','pip','check') 'Check Python dependency compatibility'
    $importProbe = Run-Python @('-c','import open_webui, av, faster_whisper; import importlib.metadata as m; print("OPEN_WEBUI="+m.version("open-webui")); print("AV="+av.__version__); print("FASTER_WHISPER="+m.version("faster-whisper"))') 'Verify platform and audio imports'
    if ($importProbe -notmatch 'OPEN_WEBUI=' -or $importProbe -notmatch 'AV=' -or $importProbe -notmatch 'FASTER_WHISPER=') { Fail 'The package import test did not report all three expected modules.' }

    $ffmpeg = Find-Ffmpeg
    if ($ffmpeg) {
        Set-Content -LiteralPath (Join-Path $Platform 'ffmpeg-path.txt') -Value $ffmpeg -Encoding UTF8
        Write-Host "[OK] FFmpeg: $ffmpeg" -ForegroundColor Green
    } else {
        Write-Warning 'FFmpeg was not found. Text chat will work; local audio transcription needs FFmpeg.'
    }

    Copy-Item -Path (Join-Path $PSScriptRoot 'Filters\*.py') -Destination $FilterDir -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TEST-FILTERS.py') -Destination (Join-Path $Platform 'TEST-FILTERS.py') -Force
    $filterOutput = Run-Python @((Join-Path $Platform 'TEST-FILTERS.py'),'--filters-dir',$FilterDir) 'Run filter syntax and behavior tests'
    if ($filterOutput -notmatch 'FILTER_TESTS: SUCCESS') { Fail 'Filter test script did not report FILTER_TESTS: SUCCESS.' }

    Set-Secret
    foreach ($name in @('START-LOCALAI.bat','START-LOCALAI.ps1','RUN-LOCALAI-SERVER.ps1','STOP-LOCALAI.bat','STOP-LOCALAI.ps1','CHECK-LOCALAI.bat','CHECK-LOCALAI.ps1','TEST-MODEL.bat','TEST-MODEL.ps1','IMPORT-FILTERS-GUIDE-AR.md')) {
        $source = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Fail "Setup package is missing required file: $name" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $Platform $name) -Force
    }

    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) { $desktop = $env:USERPROFILE }
    $shortcutPath = Join-Path $desktop 'LocalAI.lnk'
    $target = Join-Path $Platform 'START-LOCALAI.bat'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $Platform
    $shortcut.Description = 'Start the local Qwen chat platform'
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,12"
    $shortcut.Save()

    $status = @(
        'STATUS: READY_TO_START',
        "Ollama: $($version.version)",
        "Model: $ModelId",
        "Open WebUI: $openVersion",
        "Project Python: $pythonVersion",
        "FFmpeg: $ffmpeg",
        "Platform: $Platform",
        "Completed: $(Get-Date -Format o)",
        'Qwen model files were not downloaded or modified.'
    )
    Set-Content -LiteralPath (Join-Path $Platform 'PLATFORM-STATUS.txt') -Value $status -Encoding UTF8
    Write-Host "`nSETUP COMPLETE. Desktop shortcut: $shortcutPath" -ForegroundColor Green
    Write-Host 'From now on, double-click LocalAI on the Desktop.' -ForegroundColor Cyan
    Write-Host "Setup log: $Log" -ForegroundColor Gray
}
catch {
    $message = $_.Exception.Message
    Write-Host "`nSETUP FAILED: $message" -ForegroundColor Red
    Write-Host "Log: $Log" -ForegroundColor Yellow
    try { Set-Content -LiteralPath (Join-Path $Platform 'ONE-TIME-SETUP-FAILED.txt') -Value @("Error: $message","Log: $Log","Time: $(Get-Date -Format o)") -Encoding UTF8 } catch {}
    exit 1
}
finally {
    if ($script:KeepAwakeEnabled -and ('LocalAI.PowerManagement' -as [type])) {
        # Clear this installer's temporary power request; do not change Windows power-plan settings.
        [void][LocalAI.PowerManagement]::SetThreadExecutionState([uint32]0x80000000)
    }
    try { Stop-Transcript | Out-Null } catch {}
}
