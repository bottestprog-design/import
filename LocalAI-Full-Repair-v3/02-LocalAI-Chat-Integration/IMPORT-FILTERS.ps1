$ErrorActionPreference = 'Stop'
$BaseUrl = 'http://127.0.0.1:8080'
$FilterDir = Join-Path $PSScriptRoot 'Filters'
$BackupDir = 'D:\LocalAI\Platform\Backups\Functions'
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

function Invoke-OpenWebUIApi {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        [object]$Body = $null
    )
    $params = @{
        Uri = ($BaseUrl + $Path)
        Method = $Method
        Headers = $script:ApiHeaders
        TimeoutSec = 45
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    }
    return Invoke-RestMethod @params
}

$secureToken = $null
$token = $null
$script:ApiHeaders = $null
try {
    Write-Host 'LOCAL AI FILTER IMPORTER' -ForegroundColor Cyan
    try { Invoke-RestMethod -Uri "$BaseUrl/ready" -TimeoutSec 5 | Out-Null }
    catch { throw 'Open WebUI is not ready. Run D:\LocalAI\Platform\START-CHAT.bat and sign in as administrator first.' }

    Write-Host 'Create an Admin API key in Settings > Account. The installer enables API Keys on a fresh database.' -ForegroundColor Yellow
    Write-Host 'Paste the key below. It is entered as a hidden SecureString and is not saved or written to the log.' -ForegroundColor Yellow
    $secureToken = Read-Host 'Open WebUI Admin API key' -AsSecureString
    if ($secureToken.Length -lt 8) { throw 'The API key is empty or too short.' }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    $script:ApiHeaders = @{ Authorization = "Bearer $token"; Accept = 'application/json' }

    # This request also validates the token before any writes are attempted.
    $existingFunctions = Invoke-OpenWebUIApi -Method GET -Path '/api/v1/functions/'
    $specs = @(
        @{ Id='localai_trusted_content_guard'; Name='Local AI - Trusted Content Guard'; File='01-Trusted-Content-Guard.py'; Description='Separates untrusted file, webpage and tool content from trusted instructions.' },
        @{ Id='localai_accuracy_thinking'; Name='Local Qwen - Accuracy and Thinking'; File='02-Accuracy-Thinking.py'; Description='Adds accuracy guidance and enables native Boolean thinking for the local Qwen 3.5 model.' },
        @{ Id='localai_selective_self_review'; Name='Local Qwen - Selective Self Review'; File='03-Selective-Self-Review.py'; Description='Uses a second local pass to review selected math, code and verification answers; keeps the original on failure.' }
    )

    foreach ($spec in $specs) {
        $sourcePath = Join-Path $FilterDir $spec.File
        if (-not (Test-Path $sourcePath)) { throw "Filter source is missing: $sourcePath" }
        $source = Get-Content -Path $sourcePath -Raw -Encoding UTF8
        # Do not create duplicate filters under another ID without the user's review.
        $sameName = @($existingFunctions | Where-Object { $_.name -eq $spec.Name -and $_.id -ne $spec.Id })
        if ($sameName.Count -gt 0) {
            throw "A filter named '$($spec.Name)' already exists with ID '$($sameName[0].id)'. Disable/remove the old duplicate after reviewing it, then rerun this importer."
        }
        $existing = @($existingFunctions | Where-Object { $_.id -eq $spec.Id }) | Select-Object -First 1
        $payload = @{
            id = $spec.Id
            name = $spec.Name
            content = $source
            meta = @{ description = $spec.Description; manifest = @{} }
            commit_message = 'Install or repair the validated Local AI filter bundle'
        }

        if ($existing) {
            $current = Invoke-OpenWebUIApi -Method GET -Path ("/api/v1/functions/id/" + [Uri]::EscapeDataString($spec.Id))
            if ($current.type -ne 'filter') { throw "Existing ID '$($spec.Id)' is type '$($current.type)', not filter. Refusing to overwrite it." }
            $backupPath = Join-Path $BackupDir ($spec.Id + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
            $current | ConvertTo-Json -Depth 30 | Set-Content -Path $backupPath -Encoding UTF8
            Write-Host "Updating existing filter and saving backup: $backupPath" -ForegroundColor Yellow
            $saved = Invoke-OpenWebUIApi -Method POST -Path ("/api/v1/functions/id/" + [Uri]::EscapeDataString($spec.Id) + '/update') -Body $payload
        }
        else {
            Write-Host "Creating filter: $($spec.Name)" -ForegroundColor Yellow
            $saved = Invoke-OpenWebUIApi -Method POST -Path '/api/v1/functions/create' -Body $payload
        }

        if ($saved.type -ne 'filter') { throw "Open WebUI did not identify '$($spec.Id)' as a Filter. No activation was attempted." }
        $state = Invoke-OpenWebUIApi -Method GET -Path ("/api/v1/functions/id/" + [Uri]::EscapeDataString($spec.Id))
        if (-not $state.is_active) {
            $state = Invoke-OpenWebUIApi -Method POST -Path ("/api/v1/functions/id/" + [Uri]::EscapeDataString($spec.Id) + '/toggle')
        }
        if (-not $state.is_global) {
            $state = Invoke-OpenWebUIApi -Method POST -Path ("/api/v1/functions/id/" + [Uri]::EscapeDataString($spec.Id) + '/toggle/global')
        }
        if (-not $state.is_active -or -not $state.is_global) { throw "Filter '$($spec.Id)' was saved but could not be confirmed Active and Global." }
        Write-Host "[OK] $($spec.Name) — active and global" -ForegroundColor Green
    }

    Write-Host "`nAll three Local AI filters are installed, active and global." -ForegroundColor Green
    Write-Host 'Open a NEW chat with local-qwen35 after import. Run CHECK-LOCALAI.bat if anything looks wrong.' -ForegroundColor Cyan
}
catch {
    Write-Host "`nFILTER IMPORT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No API key was saved by this script. Read the error above and rerun after correcting it.' -ForegroundColor Yellow
    exit 1
}
finally {
    $token = $null
    $script:ApiHeaders = $null
    if ($secureToken) { $secureToken.Dispose() }
    [GC]::Collect()
}
