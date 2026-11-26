param(
 [Parameter(Mandatory=$true)][string]$Executable,
 [Parameter(Mandatory=$true)][string]$ArgumentsBase64,
 [Parameter(Mandatory=$true)][string]$StdOutPath,
 [Parameter(Mandatory=$true)][string]$StdErrPath,
 [Parameter(Mandatory=$true)][string]$ExitCodePath
)
$ErrorActionPreference='Stop'
$nativeExitCode=9009
function Quote-NativeArgument([string]$Value) {
 if($null -eq $Value -or $Value.Length -eq 0){return '""'}
 if($Value -notmatch '[\s"]'){return $Value}
 $builder=New-Object System.Text.StringBuilder
 [void]$builder.Append('"')
 $slashes=0
 foreach($character in $Value.ToCharArray()){
  if([int]$character -eq 92){$slashes++;continue}
  if([int]$character -eq 34){[void]$builder.Append(('\' * (2*$slashes+1)));[void]$builder.Append('"');$slashes=0;continue}
  if($slashes -gt 0){[void]$builder.Append(('\' * $slashes));$slashes=0}
  [void]$builder.Append($character)
 }
 if($slashes -gt 0){[void]$builder.Append(('\' * (2*$slashes)))}
 [void]$builder.Append('"')
 return $builder.ToString()
}
try{
 $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgumentsBase64))
 $parsed=ConvertFrom-Json -InputObject $json
 if($null -eq $parsed -or $null -eq $parsed.items){throw 'Arguments JSON must contain an items array.'}
 $nativeArguments=@($parsed.items | ForEach-Object {[string]$_})
 if($nativeArguments.Count -lt 1){throw 'Native command argument array is empty.'}
 $argumentLine=(($nativeArguments | ForEach-Object {Quote-NativeArgument $_}) -join ' ')
 foreach($path in @($StdOutPath,$StdErrPath,$ExitCodePath)){
  $dir=Split-Path -Parent $path
  if($dir -and -not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Force -Path $dir | Out-Null}
 }
 $process=Start-Process -FilePath $Executable -ArgumentList $argumentLine -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -ErrorAction Stop
 $process.Refresh()
 $nativeExitCode=[int]$process.ExitCode
}catch{
 $nativeExitCode=9009
 try{[IO.File]::AppendAllText($StdErrPath,('Native runner failure: '+$_.Exception.Message+[Environment]::NewLine),[Text.Encoding]::UTF8)}catch{}
}
try{[IO.File]::WriteAllText($ExitCodePath,[string]$nativeExitCode,[Text.Encoding]::ASCII)}catch{exit 90}
exit 0
