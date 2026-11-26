$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Logs = Join-Path $Root 'Logs'
$VenvPython = Join-Path $Platform '.venv\Scripts\python.exe'
$OpenWebUIExe = Join-Path $Platform '.venv\Scripts\open-webui.exe'
$InstallerScript = Join-Path $PSScriptRoot 'INSTALL-PLATFORM.ps1'
$script:LogState = @{}

function Quote-ProcessArgument([string]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"','\"') + '"'
}
function Invoke-CapturedProcess([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=45) {
    $id=[guid]::NewGuid().ToString('N')
    $temp=Join-Path $env:TEMP ('localai-probe-'+$id)
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $stdout=Join-Path $temp 'stdout.txt'; $stderr=Join-Path $temp 'stderr.txt'
    $line=(($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
    $proc=$null
    try {
        $proc=Start-Process -FilePath $Executable -ArgumentList $line -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        if (-not $proc.WaitForExit($TimeoutSeconds*1000)) {
            try { $proc.Kill() } catch {}
            return [pscustomobject]@{ExitCode=124;StdOut='';StdErr='Probe timed out';TimedOut=$true}
        }
        $proc.Refresh()
        $out=if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
        $err=if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''}
        return [pscustomobject]@{ExitCode=[int]$proc.ExitCode;StdOut=$out;StdErr=$err;TimedOut=$false}
    } finally {
        # Delete only our tiny temporary probe files, not project data or pip cache.
        try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
function Get-OpenWebUIState {
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;Detail='project Python not present'}
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
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;Detail=('Python probe failed: '+$result.StdErr+' '+$result.StdOut)}
    }
    try { $info=$result.StdOut | ConvertFrom-Json } catch {
        return [pscustomobject]@{Installed=$false;Version=$null;AudioReady=$false;Detail=('Could not parse package probe: '+$result.StdOut+' '+$result.StdErr)}
    }
    $core = ($info.version -eq '0.13.5' -and $info.core_import -eq $true -and (Test-Path -LiteralPath $OpenWebUIExe -PathType Leaf))
    return [pscustomobject]@{Installed=$core;Version=$info.version;AudioReady=($info.audio -eq $true -and $info.av_version -eq '14.0.1');Detail=($info | ConvertTo-Json -Compress)}
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
        if (-not $script:LastWaitNotice -or ((Get-Date)-$script:LastWaitNotice).TotalSeconds -ge 180) {
            Write-Host "Installer-related processes still active: PID $pids. Waiting; nothing will be terminated." -ForegroundColor Yellow
            $script:LastWaitNotice = Get-Date
        }
        Start-Sleep -Seconds 30
    }
    Write-Host 'Existing install process has exited. Verifying installed files before deciding whether to resume.' -ForegroundColor Green
}

Write-Host 'LOCALAI PLATFORM REPAIR / RESUME v2.3' -ForegroundColor Cyan
Write-Host 'PowerShell 5.1-safe package probing; no pip stderr is treated as a terminating error.'
if (-not (Test-Path -LiteralPath $InstallerScript -PathType Leaf)) { throw 'INSTALL-PLATFORM.ps1 is missing from this extracted package.' }
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$active=@(Get-ActiveInstallProcesses)
if ($active.Count -gt 0) { Watch-Installer }
$state=Get-OpenWebUIState
Write-Host ('Open WebUI package state: Version={0}; CoreReady={1}; AudioReady={2}' -f $state.Version,$state.Installed,$state.AudioReady) -ForegroundColor Cyan
if ($state.Installed -and $state.AudioReady) {
    Write-Host 'Open WebUI 0.13.5 and audio imports are already installed. No package reinstall is needed.' -ForegroundColor Green
    New-Item -ItemType Directory -Force -Path $Platform | Out-Null
    foreach ($extraName in @('DASHBOARD-SERVER.py','TEST-DASHBOARD.py','START-DASHBOARD.bat','ADD-FAST-MODEL.ps1','ADD-FAST-MODEL.bat','MODEL-PROFILES-AR.md','V2.3-ADDENDUM-AR.md')) {
        $extraSource = Join-Path $PSScriptRoot $extraName
        if (Test-Path -LiteralPath $extraSource -PathType Leaf) { Copy-Item -LiteralPath $extraSource -Destination $Platform -Force }
    }
    $sourceStart=Join-Path $PSScriptRoot 'START-CHAT.ps1'
    $targetStart=Join-Path $Platform 'START-CHAT.ps1'
    if (Test-Path $sourceStart) { Copy-Item -LiteralPath $sourceStart -Destination $targetStart -Force }
    Write-Host 'Updated the installed chat launcher with the corrected Windows power-state flag.' -ForegroundColor Green
    exit 0
}
if ($state.Installed -and -not $state.AudioReady) {
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
