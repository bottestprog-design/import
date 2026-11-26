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
    if ($null -eq $parsed -or $null -eq $parsed.items) { throw 'Arguments JSON must contain an items array.' }
    $nativeArguments = @($parsed.items)
    if ($nativeArguments.Count -lt 1) { throw 'Native command argument array is empty.' }
    & $Executable @nativeArguments 1> $StdOutPath 2> $StdErrPath
    $rawExitCode = $LASTEXITCODE
    if ($null -eq $rawExitCode) {
        $nativeExitCode = 9008
        [IO.File]::AppendAllText($StdErrPath, 'Native process did not set LASTEXITCODE.' + [Environment]::NewLine, [Text.Encoding]::UTF8)
    } else {
        $nativeExitCode = [int]$rawExitCode
    }
} catch {
    $nativeExitCode = 9009
    try {
        [IO.File]::AppendAllText($StdErrPath, ('Native runner failure: ' + $_.Exception.Message + [Environment]::NewLine), [Text.Encoding]::UTF8)
    } catch {}
}
try {
    [IO.File]::WriteAllText($ExitCodePath, [string]$nativeExitCode, [Text.Encoding]::ASCII)
} catch {
    return
}
return
