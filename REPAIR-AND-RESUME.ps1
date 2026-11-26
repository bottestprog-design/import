$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Logs = Join-Path $Root 'Logs'
$VenvPython = Join-Path $Platform '.venv\Scripts\python.exe'
$OpenWebUIExe = Join-Path $Platform '.venv\Scripts\open-webui.exe'
$InstallerScript = Join-Path $PSScriptRoot 'INSTALL-PLATFORM.ps1'
$script:LogState = @{}

function Quote-ProcessArgument([string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ([int]$character -eq 92) { $slashes++; continue }
        if ([int]$character -eq 34) {
            [void]$builder.Append(('\' * (2 * $slashes + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}
function Invoke-CapturedProcess([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=60) {
    $id=[guid]::NewGuid().ToString('N')
    $temp=Join-Path $env:TEMP ('localai-probe-'+$id)
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $stdout=Join-Path $temp 'stdout.txt'
    $stderr=Join-Path $temp 'stderr.txt'
    $exitFile=Join-Path $temp 'exitcode.txt'
    $runnerOut=Join-Path $temp 'runner.stdout.txt'
    $runnerErr=Join-Path $temp 'runner.stderr.txt'
    $runnerScript=Join-Path $PSScriptRoot 'RUN-NATIVE-WITH-EXITCODE.ps1'
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $proc=$null
    try {
        if (-not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) {
            return [pscustomobject]@{ExitCode=9009;StdOut='';StdErr='RUN-NATIVE-WITH-EXITCODE.ps1 is missing';TimedOut=$false}
        }
        $json=ConvertTo-Json -InputObject ([pscustomobject]@{ items = [string[]]$Arguments }) -Compress -Depth 10
        $argumentsBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $runnerArguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runnerScript,
            '-Executable',$Executable,'-ArgumentsBase64',$argumentsBase64,
            '-StdOutPath',$stdout,'-StdErrPath',$stderr,'-ExitCodePath',$exitFile)
        $line=(($runnerArguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
        $proc=Start-Process -FilePath $powershell -ArgumentList $line -PassThru -WindowStyle Hidden -RedirectStandardOutput $runnerOut -RedirectStandardError $runnerErr -ErrorAction Stop
        if (-not $proc.WaitForExit($TimeoutSeconds*1000)) {
            $taskkill=Join-Path $env:WINDIR 'System32\taskkill.exe'
            if (Test-Path -LiteralPath $taskkill) { & $taskkill /PID $proc.Id /T /F 2>$null | Out-Null }
            return [pscustomobject]@{ExitCode=124;StdOut='';StdErr='Probe timed out; runner process tree was terminated.';TimedOut=$true}
        }
        $proc.WaitForExit()
        $proc.Refresh()
        $out=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout)}else{''}
        $err=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr)}else{''}
        if (-not (Test-Path -LiteralPath $exitFile -PathType Leaf)) {
            $runnerError=if(Test-Path -LiteralPath $runnerErr){[IO.File]::ReadAllText($runnerErr)}else{''}
            return [pscustomobject]@{ExitCode=9009;StdOut=$out;StdErr=($err+' '+$runnerError+' Runner did not write exit result.');TimedOut=$false}
        }
        $exitText=([IO.File]::ReadAllText($exitFile)).Trim()
        $exitCode=0
        if (-not [int]::TryParse($exitText,[ref]$exitCode)) {
            return [pscustomobject]@{ExitCode=9008;StdOut=$out;StdErr=($err+' Invalid exit-code result: '+$exitText);TimedOut=$false}
        }
        return [pscustomobject]@{ExitCode=$exitCode;StdOut=$out;StdErr=$err;TimedOut=$false}
    } catch {
        return [pscustomobject]@{ExitCode=9009;StdOut='';StdErr=$_.Exception.Message;TimedOut=$false}
    } finally {
        try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
function Get-OpenWebUIState {
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;WhisperReady=$false;Detail='project Python not present'}
    }
    $code=@'
import importlib.metadata as md, json
try:
    version=md.version("open-webui")
except md.PackageNotFoundError:
    version=None
try:
    import open_webui
    core_import=True
except Exception as e:
    core_import=False
    core_error=type(e).__name__+": "+str(e)[:300]
try:
    import av, faster_whisper
    audio=True
    av_version=getattr(av,"__version__",None)
except Exception as e:
    audio=False
    audio_error=type(e).__name__+": "+str(e)[:300]
print(json.dumps({"version":version,"core_import":core_import,"core_error":locals().get("core_error"),"audio":audio,"av_version":locals().get("av_version"),"audio_error":locals().get("audio_error")}))
'@
    $result=Invoke-CapturedProcess -Executable $VenvPython -Arguments @('-c',$code) -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;WhisperReady=$false;Detail=('Python probe failed: '+$result.StdErr+' '+$result.StdOut)}
    }
    try { $info=$result.StdOut | ConvertFrom-Json } catch {
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;WhisperReady=$false;Detail=('Could not parse package probe: '+$result.StdOut+' '+$result.StdErr)}
    }
    $core = ($info.version -eq '0.13.5' -and $info.core_import -eq $true -and (Test-Path -LiteralPath $OpenWebUIExe -PathType Leaf))
    $whisperRoot=Join-Path $Platform 'Data\cache\whisper\models'
    $whisperFile=$null
    if(Test-Path -LiteralPath $whisperRoot -PathType Container){
        $whisperFile=Get-ChildItem -LiteralPath $whisperRoot -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $whisperReady=($null -ne $whisperFile)
    return [pscustomobject]@{Installed=$core;Version=$info.version;AudioReady=($info.audio -eq $true -and $info.av_version -eq '14.0.1');WhisperReady=$whisperReady;Detail=($info | ConvertTo-Json -Compress)}
}
function Get-ActiveInstallProcesses {
    $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $found=@()
    foreach($p in $all) {
        $cmd=[string]$p.CommandLine
        $exe=[string]$p.ExecutablePath
        if ($p.Name -match '^(powershell|pwsh)\.exe$' -and $cmd -match '(?i)INSTALL-PLATFORM\.ps1') {
            $found += $p; continue
        }
        if ($p.Name -match '^python(w)?\.exe$' -and $exe -match '(?i)\\LocalAI\\Platform\\\.venv\\Scripts\\python(w)?\.exe$' -and $cmd -match '(?i)(-m\s+pip\s+install|pip\.exe\s+install)' -and $cmd -match '(?i)open-webui') {
            $found += $p; continue
        }
        # Also catch a child process using the platform venv whose command has package target split differently.
        if ($p.Name -match '^python(w)?\.exe$' -and $exe -match '(?i)\\LocalAI\\Platform\\\.venv\\Scripts\\python(w)?\.exe$' -and $cmd -match '(?i)pip' -and $cmd -match '(?i)0\.13\.5') {
            $found += $p
        }
    }
    return @($found | Sort-Object ProcessId -Unique)
}
function Show-ChangedLog([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $item=Get-Item -LiteralPath $Path
    $key=$Path.ToLowerInvariant(); $state="$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    if ($script:LogState.ContainsKey($key) -and $script:LogState[$key] -eq $state) { return }
    $script:LogState[$key]=$state
    Write-Host "`n--- $($item.Name) | $($item.Length) bytes | $($item.LastWriteTime) ---" -ForegroundColor Cyan
    Get-Content -LiteralPath $Path -Tail 14 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}
function Watch-Installer {
    Write-Host 'An existing platform installer or Open WebUI pip installation is active. Monitoring; no second installer will be started.' -ForegroundColor Yellow
    while ($true) {
        $active=@(Get-ActiveInstallProcesses)
        $recent=@(Get-ChildItem -LiteralPath $Logs -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(stdout|stderr)\.log$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 4)
        foreach($f in $recent){ Show-ChangedLog -Path $f.FullName }
        if ($active.Count -eq 0) { break }
        $pids=($active | ForEach-Object { $_.ProcessId }) -join ', '
        Write-Host "Installer-related processes still active: PID $pids. Waiting; nothing will be terminated." -ForegroundColor Yellow
        Start-Sleep -Seconds 8
    }
    Write-Host 'Existing install process has exited. Verifying installed files before deciding whether to resume.' -ForegroundColor Green
}

Write-Host 'LOCALAI STUDIO PLATFORM REPAIR / RESUME v2.4.0' -ForegroundColor Cyan
Write-Host 'PowerShell 5.1-safe package probing; no pip stderr is treated as a terminating error.'
if (-not (Test-Path -LiteralPath $InstallerScript -PathType Leaf)) { throw 'INSTALL-PLATFORM.ps1 is missing from this extracted package.' }
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

# Exclusive OS file handle: concurrent launchers cannot pass this point together.
$lockPath=Join-Path $Logs 'platform-continuation.install.lock'
try {
    $script:InstallLockStream=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
} catch {
    Write-Host 'Another LocalAI installer/recovery process already owns the installation lock. No second installer was started.' -ForegroundColor Yellow
    exit 0
}
foreach ($maintenanceFile in @('DIAGNOSTICS.ps1','DIAGNOSTICS.bat','BACKUP-LOCALAI.ps1','BACKUP-LOCALAI.bat')) {
    $source = Join-Path $PSScriptRoot $maintenanceFile
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Maintenance file missing from package: $maintenanceFile" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $Platform $maintenanceFile) -Force
}
$active=@(Get-ActiveInstallProcesses)
if ($active.Count -gt 0) { Watch-Installer }
$state=Get-OpenWebUIState
Write-Host ('Open WebUI package state: Version={0}; CoreReady={1}; AudioReady={2}; WhisperCacheReady={3}' -f $state.Version,$state.Installed,$state.AudioReady,$state.WhisperReady) -ForegroundColor Cyan
if ($state.Installed -and $state.AudioReady -and $state.WhisperReady) {
    Write-Host 'Open WebUI, audio imports and Whisper cache are ready. No package reinstall is needed.' -ForegroundColor Green
    $sourceStart=Join-Path $PSScriptRoot 'START-CHAT.ps1'
    $targetStart=Join-Path $Platform 'START-CHAT.ps1'
    if (Test-Path $sourceStart) { Copy-Item -LiteralPath $sourceStart -Destination $targetStart -Force }
    Write-Host 'Updated the installed chat launcher with the corrected Windows power-state flag.' -ForegroundColor Green
    exit 0
}
if ($state.Installed -and $state.AudioReady -and -not $state.WhisperReady) {
    Write-Host 'Open WebUI/audio packages are present; Whisper cache is missing or incomplete. The installer will retry the separate Whisper download.' -ForegroundColor Yellow
} elseif ($state.Installed -and -not $state.AudioReady) {
    Write-Host 'Open WebUI core is present, but audio dependencies are incomplete. The installer will verify/repair missing audio packages.' -ForegroundColor Yellow
} else {
    Write-Host 'Open WebUI 0.13.5 is not yet fully installed. Starting the installer using the existing venv and pip cache.' -ForegroundColor Yellow
}
& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $InstallerScript
$rc=$LASTEXITCODE
if ($rc -ne 0) { throw "Platform installer failed with exit code $rc. Inspect the latest platform-continuation stdout/stderr logs in D:\LocalAI\Logs." }
$final=Get-OpenWebUIState
if (-not $final.Installed) { throw ('Installer exited successfully but Open WebUI core is not complete: '+$final.Detail) }
if (-not $final.AudioReady) { Write-Host 'Open WebUI is installed. Audio imports are incomplete; see warnings in PLATFORM-STATUS.txt.' -ForegroundColor Yellow }
Write-Host 'Platform recovery completed. Existing Ollama/Qwen data was not reinstalled or downloaded.' -ForegroundColor Green
