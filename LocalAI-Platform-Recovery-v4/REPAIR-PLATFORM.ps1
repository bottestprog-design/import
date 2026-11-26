$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = 'D:\LocalAI'
$LogDir = Join-Path $Root 'Logs'
New-Item -ItemType Directory -Force -Path $Root,$LogDir | Out-Null
$LogFile = Join-Path $LogDir ('platform-recovery-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -LiteralPath $LogFile -Force | Out-Null
function Step([string]$Text) { Write-Host ("`n==> " + $Text) -ForegroundColor Cyan }
function Fail([string]$Text) { Write-Host ("ERROR: " + $Text) -ForegroundColor Red; throw $Text }
try {
    Step 'Validate recovery package contents'
    $chatDir = Join-Path $PSScriptRoot '02-LocalAI-Chat-Integration'
    $engineDir = Join-Path $PSScriptRoot '01-LocalAI-Engine'
    foreach ($p in @(
        (Join-Path $chatDir 'INSTALL-CHAT-PLATFORM.ps1'),
        (Join-Path $chatDir 'START-CHAT.ps1'),
        (Join-Path $chatDir 'Filters\01-Trusted-Content-Guard.py'),
        (Join-Path $chatDir 'Filters\02-Accuracy-Thinking.py'),
        (Join-Path $chatDir 'Filters\03-Selective-Self-Review.py'),
        (Join-Path $chatDir 'IMPORT-FILTERS.ps1'),
        (Join-Path $engineDir 'START-ENGINE.ps1'),
        (Join-Path $engineDir 'START-ENGINE.bat')
    )) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Fail "Required package file missing: $p" } }

    Step 'Verify the already-installed Ollama engine without restarting it'
    $ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if (-not $ollama) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
        if (Test-Path $candidate) { $ollamaPath = $candidate } else { Fail 'Ollama executable not found. This repair will not reinstall it.' }
    } else { $ollamaPath = $ollama.Source }
    try { $version = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 8 }
    catch { Fail 'Ollama API did not respond at 127.0.0.1:11434. The repair will not restart or reinstall Ollama automatically.' }
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 15
    $model = $tags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -eq 'local-qwen35' } | Select-Object -First 1
    if (-not $model) { Fail 'Ollama is responding, but local-qwen35 is not listed. No model pull will be started.' }
    Write-Host ("Ollama version: {0}; verified model: {1}; size: {2}" -f $version.version,$model.name,$model.size) -ForegroundColor Green

    Step 'Preserve and register the existing model store'
    $userStore = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','User')
    $knownStore = if ($userStore) { $userStore } else { Join-Path $Root 'Models' }
    if (-not (Test-Path -LiteralPath $knownStore -PathType Container)) { Fail "The reported model store does not exist: $knownStore. No model files will be moved." }
    $storeFile = Join-Path $Root 'MODEL-STORE-PATH.txt'
    if (Test-Path -LiteralPath $storeFile) {
        $oldStore = (Get-Content -LiteralPath $storeFile -Raw).Trim()
        if ($oldStore -and (Test-Path -LiteralPath $oldStore -PathType Container)) { $knownStore = $oldStore }
    } else {
        Set-Content -LiteralPath $storeFile -Value $knownStore -Encoding UTF8
    }
    # This marker records API/tag verification only. It explicitly does not claim a new inference test.
    $engineStatus = @"
STATUS: SUCCESS
DATE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
OLLAMA VERSION: $($version.version)
MODEL ALIAS: $($model.name)
MODEL DIRECTORY: $knownStore
API: http://127.0.0.1:11434
VERIFICATION: /api/version and /api/tags succeeded; installed model tag exists.
INFERENCE TEST: NOT RUN BY THIS PLATFORM-ONLY RECOVERY.
MODEL DOWNLOAD: SKIPPED; existing model retained.
"@
    Set-Content -LiteralPath (Join-Path $Root 'ENGINE-STATUS.txt') -Value $engineStatus -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $engineDir 'START-ENGINE.ps1') -Destination (Join-Path $Root 'START-ENGINE.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $engineDir 'START-ENGINE.bat') -Destination (Join-Path $Root 'START-ENGINE.bat') -Force

    Step 'Install only the missing chat platform, filters, and audio dependencies'
    $installer = Join-Path $chatDir 'INSTALL-CHAT-PLATFORM.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
    if ($LASTEXITCODE -ne 0) { Fail "Chat platform installer failed with exit code $LASTEXITCODE. Read the newest platform-install log in $LogDir." }

    Step 'Verify installed files and filter tests'
    $platform = Join-Path $Root 'Platform'
    $required = @(
        '.venv\Scripts\python.exe','.venv\Scripts\open-webui.exe','webui_secret_key.txt',
        'START-CHAT.bat','START-CHAT.ps1','IMPORT-FILTERS.bat','IMPORT-FILTERS.ps1',
        'CHECK-LOCALAI.bat','CHECK-LOCALAI.ps1','Filters\01-Trusted-Content-Guard.py',
        'Filters\02-Accuracy-Thinking.py','Filters\03-Selective-Self-Review.py','TEST-FILTERS.py',
        'FILTER-IMPORT-GUIDE-AR.md','PLATFORM-STATUS.txt'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $platform $_)) })
    if ($missing.Count -gt 0) { Fail ("Platform install incomplete; missing: " + ($missing -join ', ')) }
    $py = Join-Path $platform '.venv\Scripts\python.exe'
    $test = & $py (Join-Path $platform 'TEST-FILTERS.py') '--filters-dir' (Join-Path $platform 'Filters') 2>&1
    $testExit = $LASTEXITCODE
    $test | ForEach-Object { Write-Host $_ }
    if ($testExit -ne 0) { Fail 'The installed filter sources failed their syntax/behavior tests.' }

    Step 'Write full installation status and create shortcuts'
    @"
STATUS: SUCCESS
DATE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
ENGINE: VERIFIED EXISTING OLLAMA API + local-qwen35 model tag; no pull/reinstall.
PLATFORM: Open WebUI 0.13.4 installed in D:\LocalAI\Platform\.venv
FILTERS: 3 original filter files copied and behavioral tests passed.
AUDIO: See PLATFORM-STATUS.txt for FFmpeg/Whisper status.
CHAT URL: http://127.0.0.1:8080
NEXT: Create the first admin account, then run D:\LocalAI\Platform\IMPORT-FILTERS.bat with the admin API key.
"@ | Set-Content -LiteralPath (Join-Path $Root 'FULL-STATUS.txt') -Encoding UTF8
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Local AI Chat.lnk'))
        $shortcut.TargetPath = Join-Path $platform 'START-CHAT.bat'
        $shortcut.WorkingDirectory = $platform
        $shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll') + ',15'
        $shortcut.Save()
    } catch { Write-Host "Shortcut could not be created: $($_.Exception.Message)" -ForegroundColor Yellow }

    Step 'Start Open WebUI and wait for actual HTTP readiness'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $platform 'START-CHAT.ps1')
    if ($LASTEXITCODE -ne 0) { Fail "Open WebUI did not start successfully. Check the newest open-webui stdout/stderr logs in $platform\Data." }

    Write-Host "`nRECOVERY COMPLETED. Existing Ollama and Qwen model were retained; chat platform installed." -ForegroundColor Green
    Write-Host "Chat URL: http://127.0.0.1:8080" -ForegroundColor Green
    Write-Host "Log: $LogFile" -ForegroundColor DarkGray
}
catch {
    try {
        $failure = @"
STATUS: PARTIAL_OR_FAILED
DATE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
ERROR: $($_.Exception.Message)
REPAIR LOG: $LogFile
NOTE: Existing Ollama, model blobs, and user data were not deleted by this recovery script.
"@
        Set-Content -LiteralPath (Join-Path $Root 'PLATFORM-RECOVERY-STATUS.txt') -Value $failure -Encoding UTF8
    } catch {}
    Write-Host "`nPLATFORM RECOVERY FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Read the full transcript: $LogFile" -ForegroundColor Yellow
    exit 1
}
finally { Stop-Transcript | Out-Null }
