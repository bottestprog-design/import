$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Logs = Join-Path $Root 'Logs'
$Data = Join-Path $Platform 'Data'
$TempRoot = Join-Path $Data 'Temp'
$VenvPython = Join-Path $Platform '.venv\Scripts\python.exe'
$OpenWebUIExe = Join-Path $Platform '.venv\Scripts\open-webui.exe'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
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

Write-Host 'LOCALAI PLATFORM REPAIR / RESUME v3.2' -ForegroundColor Cyan
Write-Host 'Windows-safe package check; existing Open WebUI, Ollama, Qwen and user data are reused.'
if (-not (Test-Path -LiteralPath $InstallerScript -PathType Leaf)) { throw 'INSTALL-PLATFORM.ps1 is missing from this extracted package.' }
New-Item -ItemType Directory -Force -Path $Logs,$TempRoot | Out-Null
$env:TEMP = $TempRoot
$env:TMP = $TempRoot
$env:TMPDIR = $TempRoot
$active=@(Get-ActiveInstallProcesses)
if ($active.Count -gt 0) { Watch-Installer }
$state=Get-OpenWebUIState
Write-Host ('Open WebUI package state: Version={0}; CoreReady={1}; AudioReady={2}' -f $state.Version,$state.Installed,$state.AudioReady) -ForegroundColor Cyan
if ($state.Installed -and $state.AudioReady) {
    Write-Host 'Open WebUI 0.13.5 and audio imports are already installed. No package reinstall is needed.' -ForegroundColor Green
    New-Item -ItemType Directory -Force -Path $Platform | Out-Null
    $obsoleteFiles = @('ADD-FAST-MODEL.bat','ADD-FAST-MODEL.ps1','CHECK-LOCALAI.bat','DASHBOARD-SERVER.py',
        'FILTER-IMPORT-GUIDE-AR.md','IMPORT-FILTERS.bat','INSTALL-PLATFORM.bat','MODEL-PROFILES-AR.md',
        'PLATFORM-FILES.txt','RESTORE-OPENWEBUI-STYLE.bat','RUN-REPAIR.bat','START-CHAT.bat',
        'START-DASHBOARD.bat','START-HERE-AR.md','START-LOCALAI.bat','STOP-CHAT.bat',
        'TEST-DASHBOARD.py','V2.3-ADDENDUM-AR.md','VERIFY-MODEL.bat','VERIFY-PACKAGE.bat',
        'VERSION.txt','WATCH-CURRENT-INSTALL.bat')
    foreach ($obsoleteName in $obsoleteFiles) {
        $obsoletePath = Join-Path $Platform $obsoleteName
        if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) { Remove-Item -LiteralPath $obsoletePath -Force }
    }
    $runtimeFiles = @('LocalAI-Studio.bat','START-CHAT.ps1','STOP-CHAT.ps1','REPAIR-AND-RESUME.ps1',
        'INSTALL-PLATFORM.ps1','CHECK-LOCALAI.ps1','VERIFY-MODEL.ps1','VERIFY-PACKAGE.ps1',
        'IMPORT-FILTERS.ps1','RESTORE-OPENWEBUI-STYLE.ps1','LOCALAI-STUDIO-THEME.css',
        'TEST-FILTERS.py','README-AR.md','MANIFEST-SHA256.txt','ENSURE-MODELS.ps1','MODELS.json','WHISPER-MODEL-MANAGER.py','TEST-MODEL-MANAGER.py','TEST-WINDOWS-PROCESS-LAUNCH.ps1')
    foreach ($fileName in $runtimeFiles) {
        $sourceFile = Join-Path $PSScriptRoot $fileName
        $targetFile = Join-Path $Platform $fileName
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Required project file is missing: $fileName" }
        if ([IO.Path]::GetFullPath($sourceFile) -ne [IO.Path]::GetFullPath($targetFile)) {
            Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        }
    }
    $sourceFilters = Join-Path $PSScriptRoot 'Filters'
    $targetFilters = Join-Path $Platform 'Filters'
    if ([IO.Path]::GetFullPath($sourceFilters) -ne [IO.Path]::GetFullPath($targetFilters)) {
        New-Item -ItemType Directory -Force -Path $targetFilters | Out-Null
        Copy-Item -Path (Join-Path $sourceFilters '*.py') -Destination $targetFilters -Force
    }
    # unittest writes its progress to native stderr. Do not merge that stream into a
    # PowerShell pipeline while ErrorActionPreference is Stop: PS 5.1 promotes it
    # to NativeCommandError and aborts even when Python exits successfully.
    $modelUnitTest = Invoke-CapturedProcess -Executable $VenvPython -Arguments @((Join-Path $Platform 'TEST-MODEL-MANAGER.py')) -TimeoutSeconds 180
    if (-not [string]::IsNullOrWhiteSpace($modelUnitTest.StdOut)) {
        Write-Host $modelUnitTest.StdOut.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($modelUnitTest.StdErr)) {
        Write-Host $modelUnitTest.StdErr.TrimEnd()
    }
    if ($modelUnitTest.ExitCode -ne 0) {
        $testDetails = (($modelUnitTest.StdOut + "`r`n" + $modelUnitTest.StdErr).Trim())
        throw "Whisper model-manager tests failed with exit code $($modelUnitTest.ExitCode). $testDetails"
    }
    & $PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Platform 'TEST-WINDOWS-PROCESS-LAUNCH.ps1')
    $launchTestExit = [int]$LASTEXITCODE
    if ($launchTestExit -ne 0) { throw "Windows process path regression test failed with exit code $launchTestExit." }
    $modelManager = Join-Path $PSScriptRoot 'ENSURE-MODELS.ps1'
    if (-not (Test-Path -LiteralPath $modelManager -PathType Leaf)) { throw 'ENSURE-MODELS.ps1 is missing from the package.' }
    Write-Host 'Checking Qwen and provisioning the Whisper cache with Windows PowerShell 5.1...' -ForegroundColor Cyan
    & $PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $modelManager
    $modelExitCode = [int]$LASTEXITCODE
    if ($modelExitCode -ne 0) { throw "Qwen/Whisper model verification failed (exit $modelExitCode). See D:\LocalAI\Platform\MODEL-STATUS.txt." }
    $modelStatus = Get-Content -LiteralPath (Join-Path $Platform 'MODEL-STATUS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($modelStatus.whisper.status -ne 'ready') { Write-Host "Qwen is ready; Whisper $($modelStatus.whisper.model) needs a network retry. See MODEL-STATUS.txt." -ForegroundColor Yellow }
    Write-Host 'Updated LocalAI Studio files and checked the configured models. Existing Ollama and WebUI data were reused.' -ForegroundColor Green
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
