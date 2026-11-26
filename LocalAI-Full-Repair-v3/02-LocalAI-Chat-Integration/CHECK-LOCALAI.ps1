$ErrorActionPreference = 'Continue'
$Root = 'D:\LocalAI'
Write-Host 'LOCAL AI DIAGNOSTICS' -ForegroundColor Cyan
$ok = $true
try { $v = Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 4; Write-Host "Ollama: OK ($($v.version))" -ForegroundColor Green } catch { Write-Host 'Ollama: NOT RUNNING' -ForegroundColor Red; $ok = $false }
try {
    $tags = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 8
    $found = $tags.models | Where-Object { $_.name -like 'local-qwen35*' }
    if ($found) { Write-Host "Model: OK ($($found[0].name))" -ForegroundColor Green } else { Write-Host 'Model local-qwen35: NOT FOUND' -ForegroundColor Red; $ok = $false }
} catch { Write-Host 'Model list: FAILED' -ForegroundColor Red; $ok = $false }
try { $h = Invoke-RestMethod 'http://127.0.0.1:8080/ready' -TimeoutSec 4; Write-Host 'Open WebUI: READY (http://127.0.0.1:8080)' -ForegroundColor Green } catch { Write-Host 'Open WebUI: NOT READY (start START-CHAT.bat and wait for startup)' -ForegroundColor Yellow; $ok = $false }
$ff = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
if ($ff) { & $ff.Source -version *> $null; if ($LASTEXITCODE -eq 0) { Write-Host "FFmpeg: OK ($($ff.Source))" -ForegroundColor Green } else { Write-Host 'FFmpeg: FOUND BUT CANNOT RUN' -ForegroundColor Red; $ok = $false } } else { Write-Host 'FFmpeg: NOT ON PATH' -ForegroundColor Red; $ok = $false }
$importer = Join-Path $Root 'Platform\IMPORT-FILTERS.bat'
if (Test-Path $importer) { Write-Host 'Filter auto-import helper: OK' -ForegroundColor Green } else { Write-Host 'Filter auto-import helper: MISSING' -ForegroundColor Red; $ok = $false }
$filters = Join-Path $Root 'Platform\Filters'
if (Test-Path $filters) {
    $count = (Get-ChildItem $filters -Filter '*.py' -File | Measure-Object).Count
    Write-Host "Filter files: $count"
    $venvPython = Join-Path $Root 'Platform\.venv\Scripts\python.exe'
    $testScript = Join-Path $Root 'Platform\TEST-FILTERS.py'
    if ($count -eq 3 -and (Test-Path $venvPython) -and (Test-Path $testScript)) {
        & $venvPython $testScript --filters-dir $filters
        if ($LASTEXITCODE -ne 0) { Write-Host 'Filter behavior tests FAILED' -ForegroundColor Red; $ok = $false }
    } else { Write-Host 'Filter test prerequisites missing or wrong filter count' -ForegroundColor Red; $ok = $false }
} else { Write-Host 'Filters folder missing' -ForegroundColor Red; $ok = $false }
$whisperDir = Join-Path $Root 'Platform\Data\cache\whisper\models'
if (Test-Path $whisperDir) {
    $whisperWeights = Get-ChildItem $whisperDir -Filter 'model.bin' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($whisperWeights) { Write-Host "Whisper Small weights: OK ($($whisperWeights.FullName))" -ForegroundColor Green } else { Write-Host 'Whisper model directory exists but model.bin is missing' -ForegroundColor Red; $ok = $false }
} else { Write-Host 'Whisper model directory missing' -ForegroundColor Red; $ok = $false }
$engineStatusPath = Join-Path $Root 'ENGINE-STATUS.txt'
$platformStatusPath = Join-Path $Root 'Platform\PLATFORM-STATUS.txt'
$engineStatusGood = (Test-Path $engineStatusPath) -and ((Get-Content $engineStatusPath -Raw -ErrorAction SilentlyContinue) -match 'STATUS:\s*SUCCESS')
$platformStatusGood = (Test-Path $platformStatusPath) -and ((Get-Content $platformStatusPath -Raw -ErrorAction SilentlyContinue) -match 'STATUS:\s*SUCCESS')
Write-Host "`nEngine status: $engineStatusGood | Platform status: $platformStatusGood"
if (-not $engineStatusGood -or -not $platformStatusGood) { Write-Host 'One or more installation status files are missing or unsuccessful.' -ForegroundColor Red; $ok = $false }
if (-not $ok) { Write-Host 'Some checks failed. See the messages above.' -ForegroundColor Red; exit 1 }
Write-Host 'Core checks passed.' -ForegroundColor Green
