$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Join-Path $root 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'MANIFEST-SHA256.txt is missing. Extract the complete package first.' }
Write-Host 'LOCALAI STUDIO v2.3.1 - EXIT-CODE HOTFIX' -ForegroundColor Cyan

$oldLines = @(Get-Content -LiteralPath $manifest -Encoding ASCII | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+(.+)$' })
if ($oldLines.Count -lt 20) { throw 'Package manifest is incomplete.' }
foreach ($line in $oldLines) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "Invalid manifest line: $line" }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2].Trim().TrimStart('*')
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing package file: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Package integrity mismatch: $relative. Re-extract the complete v2.3.0 ZIP." }
}
Write-Host "[OK] Current package verified ($($oldLines.Count) files)." -ForegroundColor Green

$runnerSource = @'
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$ArgumentsBase64,
    [Parameter(Mandatory=$true)][string]$StdOutPath,
    [Parameter(Mandatory=$true)][string]$StdErrPath,
    [Parameter(Mandatory=$true)][string]$ExitCodePath
)
$ErrorActionPreference = 'Continue'
$nativeExitCode = 9009
try {
    $jsonBytes = [Convert]::FromBase64String($ArgumentsBase64)
    $json = [Text.Encoding]::UTF8.GetString($jsonBytes)
    $parsed = ConvertFrom-Json -InputObject $json
    $nativeArguments = @($parsed)
    & $Executable @nativeArguments 1> $StdOutPath 2> $StdErrPath
    $rawExitCode = $LASTEXITCODE
    if ($null -eq $rawExitCode) {
        $nativeExitCode = 9008
        [IO.File]::AppendAllText($StdErrPath, 'Native process did not set LASTEXITCODE.' + [Environment]::NewLine)
    } else {
        $nativeExitCode = [int]$rawExitCode
    }
} catch {
    $nativeExitCode = 9009
    try {
        [IO.File]::AppendAllText($StdErrPath, ('Runner failure: ' + $_.Exception.Message + [Environment]::NewLine), [Text.Encoding]::UTF8)
    } catch {}
}
try {
    [IO.File]::WriteAllText($ExitCodePath, [string]$nativeExitCode, [Text.Encoding]::ASCII)
} catch {
    exit 91
}
exit 0
'@
$runnerPath = Join-Path $root 'RUN-NATIVE-WITH-EXITCODE.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($runnerPath,$runnerSource,$utf8)

# Self-test both success and failure without relying on Process.ExitCode.
$testRoot = Join-Path $env:TEMP ('localai-exitcode-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($expected in @(0,37)) {
        $json = ConvertTo-Json -InputObject @('/c',('exit ' + $expected)) -Compress
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $out = Join-Path $testRoot ('test-' + $expected + '.out')
        $err = Join-Path $testRoot ('test-' + $expected + '.err')
        $result = Join-Path $testRoot ('test-' + $expected + '.exit')
        $runnerArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runnerPath,
            '-Executable',$env:ComSpec,'-ArgumentsBase64',$encoded,
            '-StdOutPath',$out,'-StdErrPath',$err,'-ExitCodePath',$result)
        $line = (($runnerArgs | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }) -join ' ')
        Start-Process -FilePath $powershell -ArgumentList $line -Wait -NoNewWindow -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $result -PathType Leaf)) { throw "Exit-code helper self-test $expected did not write a result file." }
        $actual = ([IO.File]::ReadAllText($result)).Trim()
        if ($actual -ne [string]$expected) { throw "Exit-code helper self-test expected $expected but received '$actual'." }
    }
} finally {
    try { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
Write-Host '[OK] Exit-code runner self-tests passed (0 and 37).' -ForegroundColor Green
Write-Host '[OK] Added isolated native-process exit-code runner.' -ForegroundColor Green

$installPath = Join-Path $root 'INSTALL-PLATFORM.ps1'
$installText = [IO.File]::ReadAllText($installPath)
$installStart = $installText.IndexOf('function Invoke-NativeLogged {',[StringComparison]::Ordinal)
if ($installStart -lt 0) { throw 'Could not locate Invoke-NativeLogged in INSTALL-PLATFORM.ps1.' }
$installEnd = $installText.IndexOf('function Refresh-UserPath {',$installStart,[StringComparison]::Ordinal)
if ($installEnd -lt 0) { throw 'Could not locate the end of Invoke-NativeLogged in INSTALL-PLATFORM.ps1.' }

$newInstallFunction = @'
function Invoke-NativeLogged {
    param([string]$Executable,[string[]]$Arguments,[string]$Label,[int]$NoticeSeconds=45)
    $id = [guid]::NewGuid().ToString('N')
    $outFile = Join-Path $script:Logs ($id + '.stdout.log')
    $errFile = Join-Path $script:Logs ($id + '.stderr.log')
    $exitFile = Join-Path $script:Logs ($id + '.exitcode.txt')
    $runnerOut = $outFile + '.runner.log'
    $runnerErr = $errFile + '.runner.log'
    $runnerScript = Join-Path $PSScriptRoot 'RUN-NATIVE-WITH-EXITCODE.ps1'
    if (-not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) { throw 'RUN-NATIVE-WITH-EXITCODE.ps1 is missing. Re-extract the complete fixed package.' }
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw 'Windows PowerShell executable was not found.' }
    $json = ConvertTo-Json -InputObject @($Arguments) -Compress -Depth 10
    $argumentsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $runnerArguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runnerScript,
        '-Executable',$Executable,'-ArgumentsBase64',$argumentsBase64,
        '-StdOutPath',$outFile,'-StdErrPath',$errFile,'-ExitCodePath',$exitFile)
    $argLine = (($runnerArguments | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
    Write-Host ''
    Write-Host (">>> " + $Label) -ForegroundColor Cyan
    Write-Host ("Live logs: " + $outFile + " | " + $errFile) -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $powershell -ArgumentList $argLine -PassThru -NoNewWindow -RedirectStandardOutput $runnerOut -RedirectStandardError $runnerErr -ErrorAction Stop
    $outOffset = [long]0
    $errOffset = [long]0
    $lastNotice = Get-Date
    $lastOutput = Get-Date
    while ($true) {
        $proc.Refresh()
        if ($proc.HasExited) { break }
        Start-Sleep -Seconds 2
        $proc.Refresh()
        $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
        $ed = Read-AppendedLogText -Path $errFile -Offset $errOffset
        $outOffset = $od.Offset
        $errOffset = $ed.Offset
        if ($od.Text) { Write-LogDelta -Text $od.Text -Color Gray; $lastOutput = Get-Date }
        if ($ed.Text) { Write-LogDelta -Text $ed.Text -Color DarkYellow; $lastOutput = Get-Date }
        if (-not $proc.HasExited -and ((Get-Date)-$lastNotice).TotalSeconds -ge $NoticeSeconds) {
            $ob = if (Test-Path $outFile) { (Get-Item $outFile).Length } else { 0 }
            $eb = if (Test-Path $errFile) { (Get-Item $errFile).Length } else { 0 }
            $quiet = [int]((Get-Date)-$lastOutput).TotalSeconds
            Write-Host ("$Label is still running (PID {0}); stdout {1:N0} KB, stderr {2:N0} KB; last output {3}s ago." -f $proc.Id,($ob/1KB),($eb/1KB),$quiet) -ForegroundColor Yellow
            Write-Host ("Logs: " + $outFile + " | " + $errFile) -ForegroundColor DarkGray
            $lastNotice = Get-Date
        }
    }
    $proc.WaitForExit()
    $proc.Refresh()
    $od = Read-AppendedLogText -Path $outFile -Offset $outOffset
    $ed = Read-AppendedLogText -Path $errFile -Offset $errOffset
    Write-LogDelta -Text $od.Text -Color Gray
    Write-LogDelta -Text $ed.Text -Color DarkYellow
    $stdout = if (Test-Path -LiteralPath $outFile) { [IO.File]::ReadAllText($outFile) } else { '' }
    $stderr = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    if (-not (Test-Path -LiteralPath $exitFile -PathType Leaf)) {
        $runnerFailure = if (Test-Path -LiteralPath $runnerErr) { [IO.File]::ReadAllText($runnerErr) } else { '' }
        throw "$Label runner ended without writing an exit-code result. Logs: $outFile | $errFile | $runnerFailure"
    }
    $exitText = ([IO.File]::ReadAllText($exitFile)).Trim()
    $exitCode = 0
    if (-not [int]::TryParse($exitText,[ref]$exitCode)) { throw "$Label produced an invalid exit-code result '$exitText'. Result: $exitFile" }
    if ($exitCode -eq 0) { Write-Host ("[OK] " + $Label + " completed successfully.") -ForegroundColor Green }
    else { Write-Host ("[FAIL] " + $Label + " exited with code " + $exitCode + ". See " + $outFile + " and " + $errFile) -ForegroundColor Red }
    return [pscustomobject]@{ ExitCode=$exitCode; StdOut=$stdout; StdErr=$stderr; StdOutPath=$outFile; StdErrPath=$errFile }
}
'@
$newInstallFunction = [regex]::Replace($newInstallFunction,"\r\n?","\n")
$updatedInstall = $installText.Substring(0,$installStart) + $newInstallFunction + [Environment]::NewLine + $installText.Substring($installEnd)
[IO.File]::WriteAllText($installPath,$updatedInstall,$utf8)
Write-Host '[OK] Replaced installer process handling.' -ForegroundColor Green

$repairPath = Join-Path $root 'REPAIR-AND-RESUME.ps1'
$repairText = [IO.File]::ReadAllText($repairPath)
$repairStart = $repairText.IndexOf('function Invoke-CapturedProcess {',[StringComparison]::Ordinal)
if ($repairStart -lt 0) { throw 'Could not locate Invoke-CapturedProcess in REPAIR-AND-RESUME.ps1.' }
$repairEnd = $repairText.IndexOf('function Get-OpenWebUIState {',$repairStart,[StringComparison]::Ordinal)
if ($repairEnd -lt 0) { throw 'Could not locate the end of Invoke-CapturedProcess in REPAIR-AND-RESUME.ps1.' }

$newRepairFunction = @'
function Invoke-CapturedProcess([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=45) {
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
        $json=ConvertTo-Json -InputObject @($Arguments) -Compress -Depth 10
        $argumentsBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $runnerArguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runnerScript,
            '-Executable',$Executable,'-ArgumentsBase64',$argumentsBase64,
            '-StdOutPath',$stdout,'-StdErrPath',$stderr,'-ExitCodePath',$exitFile)
        $line=(($runnerArguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
        $proc=Start-Process -FilePath $powershell -ArgumentList $line -PassThru -WindowStyle Hidden -RedirectStandardOutput $runnerOut -RedirectStandardError $runnerErr -ErrorAction Stop
        if (-not $proc.WaitForExit($TimeoutSeconds*1000)) {
            try { $proc.Kill() } catch {}
            return [pscustomobject]@{ExitCode=124;StdOut='';StdErr='Probe timed out';TimedOut=$true}
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
    } finally {
        try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
'@
$newRepairFunction = [regex]::Replace($newRepairFunction,"\r\n?","\n")
$updatedRepair = $repairText.Substring(0,$repairStart) + $newRepairFunction + [Environment]::NewLine + $repairText.Substring($repairEnd)
[IO.File]::WriteAllText($repairPath,$updatedRepair,$utf8)
Write-Host '[OK] Replaced repair/resume process handling.' -ForegroundColor Green

$runRepairPath = Join-Path $root 'RUN-REPAIR.bat'
if (Test-Path -LiteralPath $runRepairPath -PathType Leaf) {
    $runText = [IO.File]::ReadAllText($runRepairPath)
    $runText = $runText.Replace('LOCAL AI - PLATFORM CONTINUATION REPAIR v2.2','LOCALAI STUDIO - PLATFORM REPAIR v2.3.1')
    [IO.File]::WriteAllText($runRepairPath,$runText,$utf8)
}
$oneClickPath = Join-Path $root 'ONE-CLICK-SETUP.bat'
if (Test-Path -LiteralPath $oneClickPath -PathType Leaf) {
    $oneText = [IO.File]::ReadAllText($oneClickPath)
    $oneText = $oneText.Replace('APPLY-V2.3.0.ps1','FIX-EXITCODE-V2.3.1.ps1')
    [IO.File]::WriteAllText($oneClickPath,$oneText,$utf8)
}
$versionContent = @'
LocalAI Studio Complete v2.3.1
Open WebUI target: 0.13.5
Native exit codes captured by a separate PowerShell runner result file.
Reuse existing Ollama/Qwen installation only; never reinstall or pull model blobs.
'@
[IO.File]::WriteAllText((Join-Path $root 'VERSION.txt'),$versionContent,$utf8)

$additional = @(
    'APPLY-V2.3.0.ps1','ONE-CLICK-SETUP.bat',
    'DIAGNOSTICS.ps1','DIAGNOSTICS.bat',
    'BACKUP-LOCALAI.ps1','BACKUP-LOCALAI.bat',
    'README-AR-V2.3.0.md','CHANGELOG-AR-V2.3.0.md',
    'FIX-EXITCODE-V2.3.1.ps1','RUN-NATIVE-WITH-EXITCODE.ps1',
    'README-AR-V2.3.1.md','CHANGELOG-AR-V2.3.1.md'
)
$paths = New-Object System.Collections.Generic.List[string]
foreach ($line in $oldLines) {
    if ($line -match '^[0-9a-fA-F]{64}\s+(.+)$') {
        $relative = $matches[1].Trim().TrimStart('*')
        if (-not $paths.Contains($relative)) { $null = $paths.Add($relative) }
    }
}
foreach ($relative in $additional) {
    if (-not $paths.Contains($relative)) { $null = $paths.Add($relative) }
}
$newManifest = New-Object System.Collections.Generic.List[string]
foreach ($relative in $paths) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Cannot sign missing package file: $relative" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $null = $newManifest.Add("$hash  $relative")
}
Set-Content -LiteralPath $manifest -Value $newManifest -Encoding ASCII
foreach ($line in Get-Content -LiteralPath $manifest -Encoding ASCII) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "Invalid generated manifest line: $line" }
    $expected = $matches[1].ToLowerInvariant()
    $relative = $matches[2].Trim()
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing signed file: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Generated manifest verification failed: $relative" }
}
Write-Host "HOTFIX_APPLIED: SUCCESS ($($newManifest.Count) manifest entries)" -ForegroundColor Green
Write-Host 'Next run ONE-CLICK-SETUP.bat or RUN-REPAIR.bat. The package will reuse the current virtual environment.' -ForegroundColor Cyan
exit 0
