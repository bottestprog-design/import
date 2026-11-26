$ErrorActionPreference = 'Continue'
$Root='D:\LocalAI'; $Platform=Join-Path $Root 'Platform'; $Venv=Join-Path $Platform '.venv\Scripts\python.exe'; $TempRoot=Join-Path $Platform 'Data\Temp'
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$env:TEMP=$TempRoot; $env:TMP=$TempRoot; $env:TMPDIR=$TempRoot
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
    $probe='import open_webui,av,faster_whisper;print("IMPORTS_OK")'
    $out=@(& $Venv -c $probe 2>&1)
    $rc=$LASTEXITCODE
    Add-Check 'Python audio imports' ($rc -eq 0 -and ($out -join [Environment]::NewLine) -match 'IMPORTS_OK') ($out -join ' ')
    $fixProbe='import importlib.util,pathlib; s=importlib.util.find_spec("open_webui"); p=pathlib.Path(s.origin).parent/"utils"/"machines"/"managed.py"; t=p.read_text(encoding="utf-8"); print("WINDOWS_TEMP_FIX=PASS" if "tempfile.gettempdir()" in t and "dir=str(_RUN_TMP_ROOT)" in t else "WINDOWS_TEMP_FIX=FAIL")'
    $fixOut=@(& $Venv -c $fixProbe 2>&1)
    Add-Check 'Open WebUI Windows temp fix' (($LASTEXITCODE -eq 0) -and (($fixOut -join [Environment]::NewLine) -match 'WINDOWS_TEMP_FIX=PASS')) ($fixOut -join ' ')
}
Add-Check 'One-click launcher' (Test-Path (Join-Path $Platform 'START-LOCALAI.bat')) (Join-Path $Platform 'START-LOCALAI.bat')
foreach($f in @('01-Trusted-Content-Guard.py','02-Accuracy-Thinking.py','03-Selective-Self-Review.py')) { $path=Join-Path $Platform ('Filters\'+$f); Add-Check "Filter $f" (Test-Path $path) $path }
$log=Join-Path $Platform ('CHECK-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'); $results | Set-Content $log -Encoding UTF8
Write-Host "`nReport: $log" -ForegroundColor Cyan
