$ErrorActionPreference = 'Continue'
$Root='D:\LocalAI'; $Platform=Join-Path $Root 'Platform'; $Venv=Join-Path $Platform '.venv\Scripts\python.exe'
$results = New-Object System.Collections.Generic.List[string]
function Add-Check([string]$Name,[bool]$Ok,[string]$Detail) { $state=if($Ok){'PASS'}else{'FAIL'}; $line="[$state] $Name — $Detail"; $null = $results.Add($line); if($Ok){Write-Host $line -ForegroundColor Green}else{Write-Host $line -ForegroundColor Red} }
Write-Host 'LOCAL AI - PLATFORM CHECK' -ForegroundColor Cyan
try { $v=Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 5; Add-Check 'Ollama API' $true $v.version } catch { Add-Check 'Ollama API' $false $_.Exception.Message }
try { $t=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10; $m=$t.models | Where-Object {$_.name -like 'local-qwen35*' -or $_.name -like 'qwen3.5:9b-q4_K_M*'} | Select-Object -First 1; Add-Check 'Qwen model tag' ([bool]$m) $(if($m){$m.name}else{'not found'}) } catch { Add-Check 'Qwen model tag' $false $_.Exception.Message }
Add-Check 'Project venv' (Test-Path $Venv) $Venv
$open=Join-Path $Platform '.venv\Scripts\open-webui.exe'; Add-Check 'Open WebUI executable' (Test-Path $open) $open
try { $r=Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 4; Add-Check 'Open WebUI ready' $true '127.0.0.1:8080/ready' } catch { Add-Check 'Open WebUI ready' $false $_.Exception.Message }
$ff=Get-Command ffmpeg.exe -ErrorAction SilentlyContinue; if(-not $ff){$fp=Join-Path $Platform 'ffmpeg-path.txt'; if(Test-Path $fp){$saved=(Get-Content $fp -Raw).Trim(); if(Test-Path -LiteralPath $saved -PathType Leaf){$ff=[pscustomobject]@{Source=$saved}}}}; Add-Check 'FFmpeg' ([bool]$ff) $(if($ff){$ff.Source}else{'not on PATH or ffmpeg-path.txt'})
if (Test-Path $Venv) {
    $probe='import open_webui,av,faster_whisper;print(1)'
    $p=Start-Process -FilePath $Venv -ArgumentList ('-c "'+$probe+'"') -PassThru -Wait -NoNewWindow -RedirectStandardOutput (Join-Path $env:TEMP 'localai-check.stdout') -RedirectStandardError (Join-Path $env:TEMP 'localai-check.stderr')
    $out=Get-Content (Join-Path $env:TEMP 'localai-check.stdout') -Raw -ErrorAction SilentlyContinue
    Add-Check 'Python audio imports' ($p.ExitCode -eq 0) $out
}
foreach($f in @('01-Trusted-Content-Guard.py','02-Accuracy-Thinking.py','03-Selective-Self-Review.py')) { $path=Join-Path $Platform ('Filters\'+$f); Add-Check "Filter $f" (Test-Path $path) $path }
$log=Join-Path $Platform ('CHECK-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'); $results | Set-Content $log -Encoding UTF8
Write-Host "`nReport: $log" -ForegroundColor Cyan
