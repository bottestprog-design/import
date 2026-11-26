$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot 'MANIFEST-SHA256.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host 'FAIL: MANIFEST-SHA256.txt is missing.' -ForegroundColor Red
    exit 2
}

$manifestLines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#')
})
if ($manifestLines.Count -lt 10) {
    Write-Host 'FAIL: manifest is incomplete.' -ForegroundColor Red
    exit 2
}

$ok = 0
$bad = 0

foreach ($line in $manifestLines) {
    $parts = $line.Trim() -split '\s+', 2
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[0-9A-Fa-f]{64}$') {
        Write-Host "BAD MANIFEST LINE: $line" -ForegroundColor Red
        $bad++
        continue
    }

    $expected = $parts[0].ToLowerInvariant()
    $relative = $parts[1].Trim()
    if ($relative.StartsWith('*')) { $relative = $relative.Substring(1) }
    $path = Join-Path $PSScriptRoot $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "MISSING: $relative" -ForegroundColor Red
        $bad++
        continue
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Write-Host "HASH MISMATCH: $relative" -ForegroundColor Red
        $bad++
    } else {
        Write-Host "OK: $relative" -ForegroundColor Green
        $ok++
    }
}

# Parse every PowerShell file with the Windows PowerShell 5.1 parser.
$powerShellFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)
foreach ($scriptFile in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            $message = '{0}:{1}:{2} {3}' -f $scriptFile.Name, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message
            Write-Host "POWERSHELL SYNTAX ERROR: $message" -ForegroundColor Red
            $bad++
        }
    } else {
        Write-Host "POWERSHELL SYNTAX OK: $($scriptFile.Name)" -ForegroundColor Green
    }
}

# Validate the batch file without using fragile multiline regular expressions.
$launcherPath = Join-Path $PSScriptRoot 'LocalAI-Studio.bat'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    Write-Host 'MISSING: LocalAI-Studio.bat' -ForegroundColor Red
    $bad++
} else {
    $launcherLines = @(Get-Content -LiteralPath $launcherPath -Encoding UTF8)
    $labels = @{}

    foreach ($launcherLine in $launcherLines) {
        $trimmed = $launcherLine.Trim()
        if ($trimmed.StartsWith(':') -and $trimmed.Length -gt 1) {
            $labelName = $trimmed.Substring(1).Trim().ToUpperInvariant()
            if ($labelName -match '^[A-Z0-9_-]+$') {
                $labels[$labelName] = $true
            }
        }
        if ($trimmed.ToLowerInvariant().StartsWith('call :')) {
            Write-Host "INVALID: nested batch subroutine call: $trimmed" -ForegroundColor Red
            $bad++
        }
    }

    foreach ($launcherLine in $launcherLines) {
        $lowerLine = $launcherLine.ToLowerInvariant()
        $gotoPosition = $lowerLine.LastIndexOf('goto ')
        if ($gotoPosition -lt 0) { continue }

        $targetText = $launcherLine.Substring($gotoPosition + 5).Trim()
        if ($targetText.StartsWith(':')) { $targetText = $targetText.Substring(1) }
        $targetParts = $targetText -split '\s+', 2
        $target = $targetParts[0].Trim().ToUpperInvariant()

        if ($target -match '^[A-Z0-9_-]+$' -and -not $labels.ContainsKey($target)) {
            Write-Host "INVALID: launcher jumps to missing label: $target" -ForegroundColor Red
            $bad++
        }
    }

    $requiredRuntimeFiles = @(
        'REPAIR-AND-RESUME.ps1',
        'START-CHAT.ps1',
        'STOP-CHAT.ps1',
        'CHECK-LOCALAI.ps1',
        'VERIFY-MODEL.ps1',
        'IMPORT-FILTERS.ps1',
        'RESTORE-OPENWEBUI-STYLE.ps1',
        'ENSURE-MODELS.ps1',
        'MODELS.json',
        'TEST-FILTERS.py',
        'Filters\01-Trusted-Content-Guard.py',
        'Filters\02-Accuracy-Thinking.py',
        'Filters\03-Selective-Self-Review.py'
    )
    foreach ($requiredFile in $requiredRuntimeFiles) {
        $requiredPath = Join-Path $PSScriptRoot $requiredFile
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Write-Host "MISSING REQUIRED PROJECT FILE: $requiredFile" -ForegroundColor Red
            $bad++
        }
    }

    # Check the model configuration is valid JSON and contains the two required model definitions.
    $modelsPath = Join-Path $PSScriptRoot 'MODELS.json'
    if (Test-Path -LiteralPath $modelsPath -PathType Leaf) {
        try {
            $modelConfig = Get-Content -LiteralPath $modelsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$modelConfig.schema_version -ne 1 -or
                [string]$modelConfig.ollama.official_pull_tag -ne 'qwen3.5:9b-q4_K_M' -or
                [string]$modelConfig.whisper.model_size -ne 'small' -or
                [string]::IsNullOrWhiteSpace([string]$modelConfig.ollama.preferred_tag) -or
                [string]::IsNullOrWhiteSpace([string]$modelConfig.ollama.official_pull_tag) -or
                [string]::IsNullOrWhiteSpace([string]$modelConfig.whisper.model_size) -or
                [string]::IsNullOrWhiteSpace([string]$modelConfig.whisper.repository)) {
                throw 'MODELS.json is missing required model settings.'
            }
            Write-Host '[OK] MODELS.json is valid.' -ForegroundColor Green
        } catch {
            Write-Host "INVALID MODELS.json: $($_.Exception.Message)" -ForegroundColor Red
            $bad++
        }
    }
}

Write-Host ("Package verification: OK={0} BAD={1}" -f $ok, $bad)
if ($bad -gt 0) { exit 1 }
Write-Host 'PACKAGE_INTEGRITY: SUCCESS' -ForegroundColor Green
exit 0
