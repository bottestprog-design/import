$ErrorActionPreference = 'Stop'
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShellExe -PathType Leaf)) {
    throw "Windows PowerShell 5.1 was not found: $powerShellExe"
}

$root = Join-Path $env:TEMP ('LocalAI process launch test with spaces ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$childScript = Join-Path $root 'child script path with spaces.ps1'
$expectedPath = Join-Path $root 'argument path with spaces.txt'
$markerPath = Join-Path $root 'launch result marker.txt'

$child = @'
param(
    [Parameter(Mandatory=$true)][string]$ExpectedPath,
    [Parameter(Mandatory=$true)][string]$MarkerPath
)
if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
    throw "Child received a corrupted path: $ExpectedPath"
}
[IO.File]::WriteAllText($MarkerPath, [IO.Path]::GetFullPath($ExpectedPath))
Write-Output 'PROCESS_PATH_ARGUMENTS_OK'
exit 0
'@
[IO.File]::WriteAllText($childScript, $child, [System.Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($expectedPath, 'argument sentinel', [System.Text.UTF8Encoding]::new($false))

try {
    # This matches the corrected REPAIR-AND-RESUME.ps1 call pattern:
    # invoke powershell.exe directly so the script path remains one argument.
    & $powerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $childScript $expectedPath $markerPath
    $exitCode = [int]$LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "PowerShell child exited with code $exitCode when paths contained spaces."
    }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw 'The child process did not create its marker; an argument was lost.'
    }
    $actual = [IO.File]::ReadAllText($markerPath)
    if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($expectedPath)) {
        throw "Path argument mismatch. Expected '$expectedPath'; received '$actual'."
    }

    $repairSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'REPAIR-AND-RESUME.ps1'))
    if ($repairSource -match '(?is)Start-Process\s+-FilePath.*?powershell\.exe.*?-File\s*,?\s*\$modelManager') {
        throw 'The repair script still starts the model manager with an unquoted Start-Process argument array.'
    }
    if ($repairSource -notmatch '(?m)^\s*&\s*\$PowerShellExe\s+-NoLogo.*-File\s+\$modelManager') {
        throw 'The repair script is missing the validated direct PowerShell invocation.'
    }

    Write-Host '[PASS] Windows PowerShell 5.1 preserved .ps1 and argument paths containing spaces.' -ForegroundColor Green
    Write-Host '[PASS] REPAIR-AND-RESUME.ps1 uses the tested invocation pattern.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
