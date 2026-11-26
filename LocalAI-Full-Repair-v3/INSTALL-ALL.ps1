$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$engine = Join-Path $PSScriptRoot '01-LocalAI-Engine\INSTALL-ENGINE.ps1'
$chat = Join-Path $PSScriptRoot '02-LocalAI-Chat-Integration\INSTALL-CHAT-PLATFORM.ps1'
$tempLog = Join-Path $env:TEMP ('LocalAI-full-install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
# Do NOT start a parent transcript: each child installer owns its own Start-Transcript.
function Write-SetupLog([string]$Message, [string]$Color = 'Gray') {
    Write-Host $Message -ForegroundColor $Color
    try { Add-Content -LiteralPath $tempLog -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) -Encoding UTF8 } catch {}
}
try {
    New-Item -ItemType File -Path $tempLog -Force | Out-Null
    Write-SetupLog 'LOCAL AI INSTALLER' 'Cyan'
    Write-SetupLog "PowerShell: $($PSVersionTable.PSVersion)"
    Write-SetupLog "Package directory: $PSScriptRoot"
    Write-SetupLog "Coordinator log: $tempLog"
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Missing engine installer: $engine. Extract the FULL ZIP before running this file." }
    if (-not (Test-Path -LiteralPath $chat -PathType Leaf)) { throw "Missing chat installer: $chat. Extract the FULL ZIP before running this file." }

    $rootStatus = 'D:\LocalAI'
    $engineStatusPath = Join-Path $rootStatus 'ENGINE-STATUS.txt'
    $platformStatusPath = Join-Path $rootStatus 'Platform\PLATFORM-STATUS.txt'
    $fullStatusPath = Join-Path $rootStatus 'FULL-STATUS.txt'
    foreach ($stale in @($platformStatusPath, $fullStatusPath)) {
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
    }

    $engineReady = $false
    if (Test-Path -LiteralPath $engineStatusPath) {
        $priorEngineStatus = Get-Content -LiteralPath $engineStatusPath -Raw -ErrorAction SilentlyContinue
        if ($priorEngineStatus -match 'STATUS:\s*SUCCESS') {
            try {
                $currentTags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 8
                $engineReady = [bool]($currentTags.models | Where-Object { $_.name -eq 'local-qwen35:latest' -or $_.name -eq 'local-qwen35' } | Select-Object -First 1)
            } catch { $engineReady = $false }
        }
    }
    if ($engineReady) {
        Write-SetupLog 'A verified engine status and local-qwen35 tag already exist. Skipping the engine stage to avoid another model download.' 'Green'
        $engineStatus = $priorEngineStatus
    } else {
        if (Test-Path -LiteralPath $engineStatusPath) { Remove-Item -LiteralPath $engineStatusPath -Force }
        Write-SetupLog "`n=== STEP 1/2: ENGINE AND MODEL ===" 'Cyan'
        & $engine
        if (-not (Test-Path -LiteralPath $engineStatusPath)) { throw 'Engine installer ended without creating ENGINE-STATUS.txt. Read the engine log.' }
        $engineStatus = Get-Content -LiteralPath $engineStatusPath -Raw -ErrorAction Stop
        if ($engineStatus -notmatch 'STATUS:\s*SUCCESS') { throw 'Engine installer did not report STATUS: SUCCESS.' }
        Write-SetupLog 'Engine status verified: SUCCESS.' 'Green'
    }

    Write-SetupLog "`n=== STEP 2/2: CHAT, VOICE AND FILTER FILES ===" 'Cyan'
    & $chat
    if (-not (Test-Path -LiteralPath $platformStatusPath)) { throw 'Platform installer ended without creating PLATFORM-STATUS.txt. Read the platform log.' }
    $platformStatus = Get-Content -LiteralPath $platformStatusPath -Raw -ErrorAction Stop
    if ($platformStatus -notmatch 'STATUS:\s*SUCCESS') { throw 'Platform installer did not report STATUS: SUCCESS.' }
    Write-SetupLog 'Platform status verified: SUCCESS.' 'Green'

    @"
STATUS: SUCCESS
DATE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
ENGINE STATUS: $engineStatusPath
PLATFORM STATUS: $platformStatusPath
NEXT: D:\LocalAI\Platform\START-CHAT.bat
"@ | Set-Content -LiteralPath $fullStatusPath -Encoding UTF8
    Write-SetupLog "`nINSTALLATION COMPLETED SUCCESSFULLY." 'Green'
    Write-SetupLog 'Next: D:\LocalAI\Platform\START-CHAT.bat' 'Cyan'
    Write-SetupLog 'After creating the first admin account, run D:\LocalAI\Platform\IMPORT-FILTERS.bat.' 'Cyan'
    Write-SetupLog "Coordinator log: $tempLog"
}
catch {
    $message = $_.Exception.Message
    Write-SetupLog "INSTALLATION FAILED: $message" 'Red'
    Write-SetupLog "Coordinator log: $tempLog" 'Yellow'
    Write-SetupLog 'Read the actual native-process output and the newest child log in D:\LocalAI\Logs before retrying.' 'Yellow'
    Write-SetupLog 'For an interrupted model pull, run RECOVER-MODEL.bat from this package; do not rerun the full installer first.' 'Yellow'
    try { Add-Content -LiteralPath $tempLog -Value (($_ | Out-String)) -Encoding UTF8 } catch {}
    exit 1
}
