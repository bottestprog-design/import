# LocalAI Studio backup. Does not copy or modify Ollama/Qwen model files.
$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Python = Join-Path $Platform '.venv\Scripts\python.exe'
$BackupRoot = Join-Path $Root 'Backups'
$Destination = Join-Path $BackupRoot ('LocalAI-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$Included = New-Object System.Collections.Generic.List[string]

try {
    $db = Join-Path $Data 'webui.db'
    if (Test-Path -LiteralPath $db -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
            throw 'The WebUI database exists but project Python is missing; cannot safely create a SQLite online backup.'
        }
        $dbTarget = Join-Path $Destination 'webui.db'
        $backupCode = @'
import sqlite3, sys
source_path, target_path = sys.argv[1], sys.argv[2]
source_uri = "file:" + source_path.replace("\\", "/") + "?mode=ro"
source = sqlite3.connect(source_uri, uri=True, timeout=45)
target = sqlite3.connect(target_path, timeout=45)
try:
    source.backup(target)
    result = target.execute("PRAGMA integrity_check").fetchone()[0]
    if result != "ok":
        raise RuntimeError("SQLite integrity check failed: " + str(result))
    print("SQLITE_BACKUP_OK")
finally:
    target.close()
    source.close()
'@
        & $Python -c $backupCode $db $dbTarget
        $rc = $LASTEXITCODE
        if ($rc -ne 0 -or -not (Test-Path -LiteralPath $dbTarget -PathType Leaf)) {
            throw "SQLite online backup failed (exit $rc)."
        }
        $null = $Included.Add('webui.db (SQLite online backup)')
    } else {
        Write-Host 'No webui.db exists yet; start Open WebUI once to create it.' -ForegroundColor Yellow
    }

    $secret = Join-Path $Platform 'Secrets\webui_secret_key.txt'
    if (Test-Path -LiteralPath $secret -PathType Leaf) {
        Copy-Item -LiteralPath $secret -Destination (Join-Path $Destination 'webui_secret_key.txt') -Force
        $null = $Included.Add('webui_secret_key.txt (sensitive)')
    }
    $filters = Join-Path $Platform 'Filters'
    if (Test-Path -LiteralPath $filters -PathType Container) {
        Copy-Item -LiteralPath $filters -Destination (Join-Path $Destination 'Filters') -Recurse -Force
        $null = $Included.Add('Filters/')
    }
    foreach ($name in @('PLATFORM-STATUS.txt','ffmpeg-path.txt','README-AR-INTEGRATION.md')) {
        $sourcePath = Join-Path $Platform $name
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            Copy-Item -LiteralPath $sourcePath -Destination $Destination -Force
            $null = $Included.Add($name)
        }
    }

    @(
        'LocalAI Studio local backup',
        "Created: $(Get-Date -Format o)",
        "Source: $Platform",
        '',
        'Included:',
        ($Included | ForEach-Object { '- ' + $_ }),
        '',
        'Excluded: Ollama and Qwen model blobs, Python virtual environment, pip cache, Whisper cache and logs.',
        'WARNING: This backup may contain chat history and the WebUI signing key. Keep it private.'
    ) | Set-Content -LiteralPath (Join-Path $Destination 'BACKUP-INFO.txt') -Encoding UTF8

    $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $icacls = Join-Path $env:WINDIR 'System32\icacls.exe'
    if (Test-Path -LiteralPath $icacls) {
        & $icacls $Destination '/inheritance:r' '/grant:r' ($account + ':(OI)(CI)F') 'SYSTEM:(OI)(CI)F' '/T' '/C' | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Host 'Warning: review Windows ACLs on the backup folder.' -ForegroundColor Yellow }
    }
    Write-Host "BACKUP COMPLETE: $Destination" -ForegroundColor Green
    Write-Host "Items included: $($Included.Count)"
    Write-Host 'No Ollama or Qwen model files were copied, deleted or modified.'
} catch {
    Write-Host "BACKUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Partial backup folder, if any: $Destination" -ForegroundColor Yellow
    exit 1
}
