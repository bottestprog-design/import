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
    function Invoke-CheckPython([string]$Code) {
        $scriptPath=Join-Path $TempRoot ('check-'+[guid]::NewGuid().ToString('N')+'.py')
        [IO.File]::WriteAllText($scriptPath,$Code,[System.Text.UTF8Encoding]::new($false))
        try { $output=@(& $Venv $scriptPath 2>&1); $codeExit=[int]$LASTEXITCODE; return [pscustomobject]@{ExitCode=$codeExit;Output=@($output)} }
        finally { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue }
    }
    $probeResult=Invoke-CheckPython 'import open_webui,av,faster_whisper;print("IMPORTS_OK")'
    Add-Check 'Python audio imports' ($probeResult.ExitCode -eq 0 -and ($probeResult.Output -join [Environment]::NewLine) -match 'IMPORTS_OK') ($probeResult.Output -join ' ')
    $fixResult=Invoke-CheckPython 'import importlib.util,pathlib; s=importlib.util.find_spec("open_webui"); p=pathlib.Path(s.origin).parent/"utils"/"machines"/"managed.py"; t=p.read_text(encoding="utf-8"); print("WINDOWS_TEMP_FIX=PASS" if "tempfile.gettempdir()" in t and "dir=str(_RUN_TMP_ROOT)" in t else "WINDOWS_TEMP_FIX=FAIL")'
    Add-Check 'Open WebUI Windows temp fix' ($fixResult.ExitCode -eq 0 -and ($fixResult.Output -join [Environment]::NewLine) -match 'WINDOWS_TEMP_FIX=PASS') ($fixResult.Output -join ' ')
    $mainResult=Invoke-CheckPython 'import open_webui.main; print("OPENWEBUI_MAIN_IMPORT_OK")'
    Add-Check 'Open WebUI main import' ($mainResult.ExitCode -eq 0 -and ($mainResult.Output -join [Environment]::NewLine) -match 'OPENWEBUI_MAIN_IMPORT_OK') ($mainResult.Output -join ' ')
}
Add-Check 'One-click launcher' (Test-Path (Join-Path $Platform 'LocalAI-Studio.bat')) (Join-Path $Platform 'LocalAI-Studio.bat')
foreach($f in @('01-Trusted-Content-Guard.py','02-Accuracy-Thinking.py','03-Selective-Self-Review.py')) { $path=Join-Path $Platform ('Filters\'+$f); Add-Check "Filter $f" (Test-Path $path) $path }
$modelStatusPath=Join-Path $Platform 'MODEL-STATUS.json'
if(Test-Path -LiteralPath $modelStatusPath -PathType Leaf){
    try{
        $modelStatus=Get-Content -LiteralPath $modelStatusPath -Raw -Encoding UTF8|ConvertFrom-Json
        Add-Check 'Qwen model manager' ($modelStatus.ollama.status -like 'ready*' -and -not [string]::IsNullOrWhiteSpace([string]$modelStatus.ollama.tag)) ([string]$modelStatus.ollama.tag)
        $whisperPath=[string]$modelStatus.whisper.path
        $whisperReady=($modelStatus.whisper.status -eq 'ready' -and (Test-Path -LiteralPath $whisperPath -PathType Container))
        Add-Check "Whisper $($modelStatus.whisper.model) model files" $whisperReady $(if($whisperReady){$whisperPath}else{[string]$modelStatus.whisper.status})
    }catch{Add-Check 'Model manager status' $false $_.Exception.Message}
}else{Add-Check 'Model manager status' $false 'MODEL-STATUS.json not found. Run LocalAI-Studio.bat to provision the models.'}
Write-Host ([Environment]::NewLine + "Report: $log") -ForegroundColor Cyan
$failed = @($results | Where-Object { $_.StartsWith('[FAIL] ', [StringComparison]::Ordinal) })
$log=Join-Path $Platform ('CHECK-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$results | Set-Content -LiteralPath $log -Encoding UTF8
Write-Host ([Environment]::NewLine + "Report: $log") -ForegroundColor Cyan
if ($failed.Count -gt 0) { exit 1 }
exit 0
