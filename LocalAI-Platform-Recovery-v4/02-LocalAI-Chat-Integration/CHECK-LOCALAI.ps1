$ErrorActionPreference = 'Continue'
$Root='D:\LocalAI'; $Platform=Join-Path $Root 'Platform'
Write-Host 'LOCALAI PLATFORM HEALTH CHECK' -ForegroundColor Cyan
foreach($p in @('ENGINE-STATUS.txt','MODEL-STORE-PATH.txt','FULL-STATUS.txt')){
 $f=Join-Path $Root $p; Write-Host ("{0}: {1}" -f $p,(Test-Path $f))
}
foreach($p in @('.venv\Scripts\python.exe','.venv\Scripts\open-webui.exe','PLATFORM-STATUS.txt','webui_secret_key.txt','Filters\01-Trusted-Content-Guard.py','Filters\02-Accuracy-Thinking.py','Filters\03-Selective-Self-Review.py')){
 $f=Join-Path $Platform $p; Write-Host ("{0}: {1}" -f $p,(Test-Path $f))
}
try { $v=Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 5; Write-Host "Ollama: OK $($v.version)" -ForegroundColor Green } catch { Write-Host 'Ollama: OFFLINE' -ForegroundColor Red }
try { $t=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10; $m=$t.models|Where-Object{$_.name -like 'local-qwen35*'}|Select-Object -First 1; if($m){Write-Host "Model: OK $($m.name)" -ForegroundColor Green}else{Write-Host 'Model local-qwen35: MISSING' -ForegroundColor Red} } catch {}
try { $r=Invoke-WebRequest 'http://127.0.0.1:8080/ready' -UseBasicParsing -TimeoutSec 4; Write-Host "Open WebUI: HTTP $($r.StatusCode)" -ForegroundColor Green } catch { Write-Host 'Open WebUI: NOT READY' -ForegroundColor Red }
try { $ff=Get-Command ffmpeg.exe -ErrorAction Stop; Write-Host "FFmpeg: $($ff.Source)" -ForegroundColor Green } catch { Write-Host 'FFmpeg: MISSING' -ForegroundColor Yellow }
try { & (Join-Path $Platform '.venv\Scripts\python.exe') -c "import faster_whisper,av;print('Whisper/PyAV: OK')" } catch { Write-Host 'Whisper/PyAV: NOT READY' -ForegroundColor Yellow }
