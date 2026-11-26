$ErrorActionPreference='Stop'
$runner=Join-Path $PSScriptRoot 'RUN-NATIVE-WITH-EXITCODE.ps1'
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw 'RUN-NATIVE-WITH-EXITCODE.ps1 is missing.'}
$temp=Join-Path $env:TEMP ('localai exitcode test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$failed=$false
try{
    foreach($expected in @(0,37)){
        $stdout=Join-Path $temp ("native-"+$expected+".stdout.txt")
        $stderr=Join-Path $temp ("native-"+$expected+".stderr.txt")
        $exitFile=Join-Path $temp ("native-"+$expected+".exitcode.txt")
        $argumentList=[string[]]@('/d','/c',('exit '+$expected))
        $json=ConvertTo-Json -InputObject ([pscustomobject]@{items=$argumentList}) -Compress
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        & $runner -Executable $env:ComSpec -ArgumentsBase64 $encoded -StdOutPath $stdout -StdErrPath $stderr -ExitCodePath $exitFile
        if(-not(Test-Path -LiteralPath $exitFile -PathType Leaf)){throw "Runner did not write exit result for expected code $expected."}
        $actual=([IO.File]::ReadAllText($exitFile)).Trim()
        if($actual -ne [string]$expected){throw "Expected native exit code $expected but runner recorded '$actual'."}
        Write-Host ("[PASS] Native exit code " + $expected + " captured correctly.") -ForegroundColor Green
    }
    $stdout=Join-Path $temp 'space path stdout.txt'
    $stderr=Join-Path $temp 'space path stderr.txt'
    $exitFile=Join-Path $temp 'space path exitcode.txt'
    $argumentList=[string[]]@('/d','/c','echo LocalAI native argument test')
    $json=ConvertTo-Json -InputObject ([pscustomobject]@{items=$argumentList}) -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    & $runner -Executable $env:ComSpec -ArgumentsBase64 $encoded -StdOutPath $stdout -StdErrPath $stderr -ExitCodePath $exitFile
    if(-not(Test-Path -LiteralPath $exitFile -PathType Leaf)){throw 'Runner did not write exit result for spaced output paths.'}
    if(([IO.File]::ReadAllText($exitFile)).Trim() -ne '0'){throw 'Runner returned a failure for the spaced-path echo test.'}
    if([IO.File]::ReadAllText($stdout) -notmatch 'LocalAI native argument test'){throw 'Runner lost native stdout for the spaced-path echo test.'}
    Write-Host '[PASS] Native stdout and file paths containing spaces are preserved.' -ForegroundColor Green

    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonExe=if($pythonCommand){if($pythonCommand.Source){$pythonCommand.Source}else{$pythonCommand.Path}}else{$null}
    if($pythonExe -and $pythonExe -notmatch '(?i)\\Microsoft\\WindowsApps\\python\.exe
}catch{
    $failed=$true
    Write-Host ("EXITCODE_RUNNER_TESTS: FAILED - " + $_.Exception.Message) -ForegroundColor Red
}finally{
    try{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}
if($failed){exit 1}
exit 0
){
        $pythonCode='import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")'
        $pythonStdout=Join-Path $temp 'python fstring stdout.txt'
        $pythonStderr=Join-Path $temp 'python fstring stderr.txt'
        $pythonExit=Join-Path $temp 'python fstring exitcode.txt'
        $pythonArgs=[string[]]@('-c',$pythonCode)
        $pythonJson=ConvertTo-Json -InputObject ([pscustomobject]@{items=$pythonArgs}) -Compress
        $pythonEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pythonJson))
        & $runner -Executable $pythonExe -ArgumentsBase64 $pythonEncoded -StdOutPath $pythonStdout -StdErrPath $pythonStderr -ExitCodePath $pythonExit
        if(-not(Test-Path -LiteralPath $pythonExit -PathType Leaf)){throw 'Python quoting test did not produce an exit code.'}
        if(([IO.File]::ReadAllText($pythonExit)).Trim() -ne '0'){throw ('Python -c quoting failed: '+[IO.File]::ReadAllText($pythonStderr))}
        if(([IO.File]::ReadAllText($pythonStdout)).Trim() -notmatch '^\d+\.\d+
}catch{
    $failed=$true
    Write-Host ("EXITCODE_RUNNER_TESTS: FAILED - " + $_.Exception.Message) -ForegroundColor Red
}finally{
    try{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}
if($failed){exit 1}
exit 0
){throw ('Python version output invalid: '+[IO.File]::ReadAllText($pythonStdout))}
        Write-Host '[PASS] Python -c f-string quoting is preserved.' -ForegroundColor Green
    }else{Write-Host '[SKIP] No installed Python executable; setup will install it when required.' -ForegroundColor Yellow}
    Write-Host 'EXITCODE_RUNNER_TESTS: SUCCESS' -ForegroundColor Green
}catch{
    $failed=$true
    Write-Host ("EXITCODE_RUNNER_TESTS: FAILED - " + $_.Exception.Message) -ForegroundColor Red
}finally{
    try{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}
if($failed){exit 1}
exit 0
