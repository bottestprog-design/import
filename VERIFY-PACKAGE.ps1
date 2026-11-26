$ErrorActionPreference = 'Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$manifestPath=Join-Path $root 'MANIFEST-SHA256.txt'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
    Write-Host 'FAIL: MANIFEST-SHA256.txt is missing.' -ForegroundColor Red
    exit 2
}
$lines=@(Get-Content -LiteralPath $manifestPath -Encoding ASCII | Where-Object {-not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#')})
if($lines.Count -lt 20){Write-Host 'FAIL: Manifest is incomplete.' -ForegroundColor Red;exit 2}

$expected=@{}
$ok=0
$bad=0
foreach($line in $lines){
    if($line -notmatch '^([0-9A-Fa-f]{64})\s+(.+)$'){
        Write-Host "BAD MANIFEST LINE: $line" -ForegroundColor Red
        $bad++
        continue
    }
    $hash=$matches[1].ToLowerInvariant()
    $relative=$matches[2].Trim().Replace('\','/')
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or $relative -match '^\./'){
        Write-Host "UNSAFE MANIFEST PATH: $relative" -ForegroundColor Red
        $bad++
        continue
    }
    if($expected.ContainsKey($relative)){
        Write-Host "DUPLICATE MANIFEST PATH: $relative" -ForegroundColor Red
        $bad++
        continue
    }
    $expected[$relative]=$hash
    $path=Join-Path $root ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "MISSING: $relative" -ForegroundColor Red
        $bad++
        continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $hash){
        Write-Host "HASH MISMATCH: $relative" -ForegroundColor Red
        $bad++
    }else{
        Write-Host "OK: $relative" -ForegroundColor Green
        $ok++
    }
}

# Reject files that are not in the integrity manifest.
$actualFiles=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.FullName -ne $manifestPath})
foreach($file in $actualFiles){
    $relative=$file.FullName.Substring($root.Length).TrimStart('\').Replace('\','/')
    if(-not $expected.ContainsKey($relative)){
        Write-Host "UNLISTED PACKAGE FILE: $relative" -ForegroundColor Red
        $bad++
    }
}

# Parse every bundled PowerShell script using the Windows PowerShell 5.1 parser.
foreach($scriptFile in (Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse)){
    $tokens=$null
    $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if($parseErrors.Count -gt 0){
        foreach($parseError in $parseErrors){
            Write-Host ("POWERSHELL SYNTAX ERROR: {0}:{1}:{2} {3}" -f $scriptFile.Name,$parseError.Extent.StartLineNumber,$parseError.Extent.StartColumnNumber,$parseError.Message) -ForegroundColor Red
            $bad++
        }
    }else{
        Write-Host ("PS PARSE OK: " + $scriptFile.Name) -ForegroundColor Green
    }
}

$installerText=Get-Content -LiteralPath (Join-Path $root 'INSTALL-PLATFORM.ps1') -Raw
$repairText=Get-Content -LiteralPath (Join-Path $root 'REPAIR-AND-RESUME.ps1') -Raw
$runnerText=Get-Content -LiteralPath (Join-Path $root 'RUN-NATIVE-WITH-EXITCODE.ps1') -Raw
if($installerText -notmatch '(?m)^function\s+Invoke-NativeLogged\s*\{'){$bad++;Write-Host 'MISSING REQUIRED FUNCTION: Invoke-NativeLogged' -ForegroundColor Red}
if($repairText -notmatch '(?m)^function\s+Invoke-CapturedProcess(?:\s|\()'){$bad++;Write-Host 'MISSING REQUIRED FUNCTION: Invoke-CapturedProcess' -ForegroundColor Red}
if($runnerText -notmatch '\$LASTEXITCODE'){$bad++;Write-Host 'RUNNER DOES NOT CAPTURE LASTEXITCODE' -ForegroundColor Red}
foreach($name in @('DIAGNOSTICS.ps1','BACKUP-LOCALAI.ps1','TEST-EXITCODE-RUNNER.ps1')){
    if(-not(Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)){$bad++;Write-Host "MISSING REQUIRED TOOL: $name" -ForegroundColor Red}
}
Write-Host ""
Write-Host ("Package verification: HASH/SOURCE OK={0} BAD={1}" -f $ok,$bad)
if($bad -gt 0){Write-Host 'PACKAGE_INTEGRITY: FAILED' -ForegroundColor Red;exit 1}
Write-Host 'PACKAGE_INTEGRITY: SUCCESS' -ForegroundColor Green
exit 0
