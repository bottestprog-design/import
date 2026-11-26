[CmdletBinding()]
param([switch]$RequireWhisper)

$ErrorActionPreference = 'Stop'
$Root = 'D:\LocalAI'
$Platform = Join-Path $Root 'Platform'
$Data = Join-Path $Platform 'Data'
$Python = Join-Path $Platform '.venv\Scripts\python.exe'
$BaseUrl = 'http://127.0.0.1:11434'
$ConfigPath = Join-Path $PSScriptRoot 'MODELS.json'
$StatusPath = Join-Path $Platform 'MODEL-STATUS.json'
$script:Config = $null
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:OllamaExe = $null
$script:Status = [ordered]@{
    schema_version = 1
    checked_at = (Get-Date).ToString('o')
    ollama = [ordered]@{ status = 'pending'; tag = ''; source = ''; store = ''; size_bytes = 0 }
    whisper = [ordered]@{ status = 'pending'; model = 'small'; path = ''; cache_dir = '' }
    warnings = @()
    error = ''
}

function Save-ModelStatus {
    $script:Status.checked_at = (Get-Date).ToString('o')
    $script:Status.warnings = @($script:Warnings)
    Set-Content -LiteralPath $StatusPath -Value ($script:Status | ConvertTo-Json -Depth 8) -Encoding UTF8
    @(
        'MODEL MANAGER STATUS'
        "Checked: $($script:Status.checked_at)"
        "Qwen: $($script:Status.ollama.status)"
        "Qwen tag: $($script:Status.ollama.tag)"
        "Ollama store: $($script:Status.ollama.store)"
        "Whisper Small: $($script:Status.whisper.status)"
        "Whisper path: $($script:Status.whisper.path)"
        "Warnings: $(@($script:Warnings).Count)"
    ) | Set-Content -LiteralPath (Join-Path $Platform 'MODEL-STATUS.txt') -Encoding UTF8
    @(
        "STATUS: $($script:Status.ollama.status)"
        "API: $BaseUrl"
        "Model: $($script:Status.ollama.tag)"
        "Model source: $($script:Status.ollama.source)"
        "Model store: $($script:Status.ollama.store)"
        "Model size bytes: $($script:Status.ollama.size_bytes)"
        "Whisper: $($script:Status.whisper.status)"
        "Whisper path: $($script:Status.whisper.path)"
        "Completed: $($script:Status.checked_at)"
    ) | Set-Content -LiteralPath (Join-Path $Root 'ENGINE-STATUS.txt') -Encoding UTF8
    if ($script:Status.ollama.store) {
        Set-Content -LiteralPath (Join-Path $Root 'MODEL-STORE-PATH.txt') -Value $script:Status.ollama.store -Encoding UTF8
    }
}

function Get-OllamaExe {
    $command = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe'),
        (Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe'),
        'C:\Program Files\Ollama\ollama.exe'
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Get-OllamaTags {
    $response = Invoke-RestMethod -Uri ($BaseUrl + '/api/tags') -TimeoutSec 30 -ErrorAction Stop
    return @($response.models)
}

function Get-ActiveModelStore {
    $configured = @(
        $env:OLLAMA_MODELS,
        [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','User'),
        [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','Machine')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1
    if ($configured) { return [IO.Path]::GetFullPath([string]$configured) }
    return Join-Path $env:USERPROFILE '.ollama\models'
}

function Get-ModelStoreRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @(
        (Get-ActiveModelStore),
        (Join-Path $env:USERPROFILE '.ollama\models'),
        (Join-Path $Root 'Models'),
        (Join-Path $Root 'Ollama\Models')
    ) + @($script:Config.ollama.search_store_roots)
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        try {
            $full = [IO.Path]::GetFullPath([string]$candidate).TrimEnd('\')
            if (-not $roots.Contains($full)) { $roots.Add($full) }
        } catch {}
    }
    return @($roots)
}

function Get-ManifestModelTag([string]$RelativePath) {
    $parts = @($RelativePath -split '[\\/]')
    if ($parts.Count -gt 0 -and $parts[0] -eq 'registry.ollama.ai' -and $parts.Count -gt 1) {
        $parts = @($parts | Select-Object -Skip 1)
    }
    if ($parts.Count -gt 0 -and $parts[0] -eq 'library' -and $parts.Count -gt 1) {
        $parts = @($parts | Select-Object -Skip 1)
    }
    if ($parts.Count -lt 2) { return '' }
    $tag = [string]$parts[$parts.Count - 1]
    $nameParts = @()
    for ($i=0; $i -lt ($parts.Count - 1); $i++) { $nameParts += [string]$parts[$i] }
    $name = $nameParts -join '/'
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($tag)) { return '' }
    return ($name + ':' + $tag)
}

function Test-OllamaManifest {
    param([string]$StoreRoot,[string]$ManifestFile,[string]$RelativePath)
    try {
        $manifest = Get-Content -LiteralPath $ManifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $manifest.config.digest -or -not $manifest.layers) { return $null }
        $items = New-Object System.Collections.Generic.List[object]
        $items.Add($manifest.config)
        foreach ($layer in @($manifest.layers)) { $items.Add($layer) }
        $blobs = New-Object System.Collections.Generic.List[object]
        foreach ($item in $items) {
            $digest = [string]$item.digest
            if ($digest -notmatch '^sha256:[0-9a-fA-F]{64}$') { return $null }
            $hash = $digest.Substring(7).ToLowerInvariant()
            $blobPath = Join-Path (Join-Path $StoreRoot 'blobs') ('sha256-' + $hash)
            if (-not (Test-Path -LiteralPath $blobPath -PathType Leaf)) { return $null }
            $blobInfo = Get-Item -LiteralPath $blobPath
            if ($item.size -and $blobInfo.Length -ne [long]$item.size) { return $null }
            $blobs.Add([pscustomobject]@{ Source=$blobPath; Name=('sha256-' + $hash); Size=[long]$blobInfo.Length })
        }
        return [pscustomobject]@{
            Tag = (Get-ManifestModelTag -RelativePath $RelativePath)
            RelativePath = $RelativePath
            ManifestFile = $ManifestFile
            Blobs = @($blobs)
        }
    } catch { return $null }
}

function Import-OllamaManifest {
    param([string]$ActiveRoot,$VerifiedManifest)
    $requiredBytes = [long]0
    foreach ($blob in @($VerifiedManifest.Blobs)) {
        $target = Join-Path (Join-Path $ActiveRoot 'blobs') $blob.Name
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $requiredBytes += [long]$blob.Size
        } elseif ((Get-Item -LiteralPath $target).Length -ne [long]$blob.Size) {
            throw "Existing Ollama blob has an unexpected size; it will not be overwritten: $target"
        }
    }
    if ($requiredBytes -gt 0) {
        $device = [IO.Path]::GetPathRoot($ActiveRoot).TrimEnd('\')
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction SilentlyContinue
        if ($disk -and [long]$disk.FreeSpace -lt ($requiredBytes + 512MB)) {
            throw "Not enough free space to import the found model. Additional bytes required: $requiredBytes."
        }
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $ActiveRoot 'blobs') | Out-Null
    foreach ($blob in @($VerifiedManifest.Blobs)) {
        $target = Join-Path (Join-Path $ActiveRoot 'blobs') $blob.Name
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-Host "[MODEL] Copying verified existing model blob $($blob.Name)" -ForegroundColor DarkCyan
            Copy-Item -LiteralPath $blob.Source -Destination $target
            $digest = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($digest -ne $blob.Name.Substring(7)) {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                throw "Copied model blob failed SHA-256 verification: $target"
            }
        }
    }

    $targetManifest = Join-Path (Join-Path $ActiveRoot 'manifests') $VerifiedManifest.RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetManifest) | Out-Null
    if (Test-Path -LiteralPath $targetManifest -PathType Leaf) {
        $a = (Get-FileHash -LiteralPath $targetManifest -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath $VerifiedManifest.ManifestFile -Algorithm SHA256).Hash
        if ($a -ne $b) {
            Copy-Item -LiteralPath $targetManifest -Destination ($targetManifest + '.localai-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $VerifiedManifest.ManifestFile -Destination $targetManifest -Force
        }
    } else {
        Copy-Item -LiteralPath $VerifiedManifest.ManifestFile -Destination $targetManifest
    }
    Write-Host "[OK] Existing model manifest imported from $($VerifiedManifest.Tag). The source store was not changed." -ForegroundColor Green
}

function Wait-ForOllamaTag([string]$Tag) {
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        $tags = Get-OllamaTags
        $names = @($tags | ForEach-Object { [string]$_.name })
        if ($names -contains $Tag) { return $tags }
        Start-Sleep -Seconds 2
    }
    return Get-OllamaTags
}

function Invoke-OllamaCopy([string]$SourceTag,[string]$DestinationTag) {
    try {
        $body = @{ source=$SourceTag; destination=$DestinationTag } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri ($BaseUrl + '/api/copy') -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 1800 | Out-Null
        return $true
    } catch {
        Write-Host "[WARN] Could not create local alias $DestinationTag: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Find-QwenTag([string[]]$Names) {
    $preferred = [string]$script:Config.ollama.preferred_tag
    if ($Names -contains $preferred) { return $preferred }
    foreach ($candidate in @($script:Config.ollama.known_tags)) {
        if ($Names -contains [string]$candidate) { return [string]$candidate }
    }
    foreach ($name in $Names) {
        if ($name -match '(?i)^qwen3\.5:9b' -or $name -match '(?i)^local-qwen35:') { return $name }
    }
    return ''
}

function Ensure-QwenModel {
    $tags = Get-OllamaTags
    $names = @($tags | ForEach-Object { [string]$_.name })
    $selected = Find-QwenTag -Names $names
    if ($selected) {
        $model = $tags | Where-Object { $_.name -eq $selected } | Select-Object -First 1
        $script:Status.ollama.status = 'ready_existing'
        $script:Status.ollama.tag = $selected
        $script:Status.ollama.source = 'Already registered by the running Ollama API'
        $script:Status.ollama.size_bytes = [long]$model.size
        Write-Host "[OK] Using the existing Qwen model: $selected ($([math]::Round($model.size/1GB,2)) GB)." -ForegroundColor Green
        return
    }

    $activeStore = Get-ActiveModelStore
    $script:Status.ollama.store = $activeStore
    $modelPattern = '(?i)(local-qwen35|qwen3\.5)'
    $importedTag = ''

    foreach ($store in (Get-ModelStoreRoots)) {
        if ([IO.Path]::GetFullPath($store).TrimEnd('\') -eq [IO.Path]::GetFullPath($activeStore).TrimEnd('\')) { continue }
        $manifestRoot = Join-Path $store 'manifests'
        if (-not (Test-Path -LiteralPath $manifestRoot -PathType Container)) { continue }
        $manifestFiles = @(Get-ChildItem -LiteralPath $manifestRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match $modelPattern } | Sort-Object FullName)
        foreach ($manifestFile in $manifestFiles) {
            $relative = $manifestFile.FullName.Substring($manifestRoot.Length) -replace '^[\\/]+',''
            $tag = Get-ManifestModelTag -RelativePath $relative
            if (-not $tag -or $tag -notmatch '(?i)(local-qwen35|qwen3\.5).*:') { continue }
            $verified = Test-OllamaManifest -StoreRoot $store -ManifestFile $manifestFile.FullName -RelativePath $relative
            if (-not $verified) { continue }

            Write-Host "[MODEL] Found complete Qwen files in another local Ollama store: $store" -ForegroundColor Cyan
            Import-OllamaManifest -ActiveRoot $activeStore -VerifiedManifest $verified
            $importedTag = $tag
            $tags = Wait-ForOllamaTag -Tag $tag
            $names = @($tags | ForEach-Object { [string]$_.name })
            if ($names -contains $tag) { break }
        }
        if ($importedTag -and $names -contains $importedTag) { break }
    }

    if (-not $importedTag -or $names -notcontains $importedTag) {
        if (-not [bool]$script:Config.ollama.auto_download_when_missing) {
            throw 'Qwen 3.5 9B was not found in the running Ollama API or the known local stores; automatic download is disabled.'
        }

        $pullTag = [string]$script:Config.ollama.official_pull_tag
        $device = [IO.Path]::GetPathRoot($activeStore).TrimEnd('\')
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction SilentlyContinue
        if ($disk -and [long]$disk.FreeSpace -lt 12GB) {
            throw "Qwen 3.5 9B is missing and the Ollama model store has less than 12 GB free: $activeStore"
        }

        $script:OllamaExe = Get-OllamaExe
        if (-not $script:OllamaExe) {
            throw 'Ollama CLI was not found. Automatic Qwen download requires ollama.exe in PATH or its standard install location.'
        }

        Write-Host "[MODEL] No local Qwen 3.5 9B copy was found. Downloading official Ollama tag $pullTag." -ForegroundColor Yellow
        $oldHost = $env:OLLAMA_HOST
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $env:OLLAMA_HOST = $BaseUrl
            & $script:OllamaExe pull $pullTag
            $pullExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
            if ($null -eq $oldHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue }
            else { $env:OLLAMA_HOST = $oldHost }
        }
        if ($pullExit -ne 0) {
            throw "ollama pull $pullTag failed with exit code $pullExit. Ollama was not restarted, reinstalled or upgraded."
        }

        $tags = Wait-ForOllamaTag -Tag $pullTag
        $names = @($tags | ForEach-Object { [string]$_.name })
        if ($names -notcontains $pullTag) { throw "Ollama pull finished, but $pullTag is missing from /api/tags." }
        $importedTag = $pullTag
        $script:Status.ollama.source = 'Downloaded from the official Ollama library because no valid local copy was found'
    } else {
        $script:Status.ollama.source = 'Verified local manifest and blobs imported into the active Ollama store'
        $tags = Get-OllamaTags
        $names = @($tags | ForEach-Object { [string]$_.name })
    }

    $preferred = [string]$script:Config.ollama.preferred_tag
    if ($importedTag -and $importedTag -ne $preferred -and $names -notcontains $preferred) {
        if (Invoke-OllamaCopy -SourceTag $importedTag -DestinationTag $preferred) {
            $tags = Wait-ForOllamaTag -Tag $preferred
            $names = @($tags | ForEach-Object { [string]$_.name })
        }
    }

    $selected = Find-QwenTag -Names $names
    if (-not $selected -and $names -contains $importedTag) { $selected = $importedTag }
    if (-not $selected) { throw 'Qwen model was imported or downloaded, but Ollama exposes no usable Qwen 3.5 9B tag.' }

    $model = $tags | Where-Object { $_.name -eq $selected } | Select-Object -First 1
    $script:Status.ollama.tag = $selected
    if ($model) { $script:Status.ollama.size_bytes = [long]$model.size }
    if ($script:Status.ollama.source -like 'Downloaded*') { $script:Status.ollama.status = 'ready_downloaded' }
    else { $script:Status.ollama.status = 'ready_imported' }
    Write-Host "[OK] Qwen model is ready: $selected." -ForegroundColor Green
}

function Ensure-WhisperModel {
    $modelDir = Join-Path $Data 'cache\whisper\models'
    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
    $env:HF_HUB_ETAG_TIMEOUT = '30'
    $env:HF_HUB_DOWNLOAD_TIMEOUT = '120'
    $env:HF_HUB_DISABLE_TELEMETRY = '1'
    $env:LOCALAI_WHISPER_MODEL_DIR = $modelDir
    $env:HF_HOME = Join-Path $Data 'cache\huggingface'
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME 'hub'
    New-Item -ItemType Directory -Force -Path $env:HF_HOME,$env:HUGGINGFACE_HUB_CACHE | Out-Null

    $pythonCode = @'
import json
import os
import shutil
import sys
from pathlib import Path
from faster_whisper.utils import download_model

target = Path(os.environ["LOCALAI_WHISPER_MODEL_DIR"]).resolve()
required = ("config.json", "model.bin", "tokenizer.json", "vocabulary.txt")

def complete(path):
    path = Path(path)
    if not path.is_dir():
        return False
    if not all((path / name).is_file() for name in required):
        return False
    if (path / "model.bin").stat().st_size < 1000000:
        return False
    try:
        config = json.loads((path / "config.json").read_text(encoding="utf-8"))
        return isinstance(config, dict) and "num_mel_bins" in config and "model_type" in config
    except Exception:
        return False

if complete(target):
    print("WHISPER_READY=" + str(target))
    sys.exit(0)

candidates = [
    target,
    Path(os.environ.get("USERPROFILE", "")) / ".cache" / "huggingface" / "hub",
    Path(os.environ.get("LOCALAPPDATA", "")) / "huggingface" / "hub",
    Path(os.environ.get("HF_HOME", "")) / "hub",
    Path(r"D:\LocalAI\Models"),
    Path(r"D:\LocalAI\Whisper"),
]
seen = set()
for cache in candidates:
    try:
        if not cache.exists():
            continue
        key = str(cache.resolve()).lower()
        if key in seen:
            continue
        seen.add(key)
        snapshot = Path(download_model("small", cache_dir=str(cache), local_files_only=True))
        if not complete(snapshot):
            continue
        target.mkdir(parents=True, exist_ok=True)
        for name in required:
            shutil.copy2(str(snapshot / name), str(target / name))
        src = snapshot / "preprocessor_config.json"
        if src.is_file():
            shutil.copy2(str(src), str(target / "preprocessor_config.json"))
        if complete(target):
            print("WHISPER_READY=" + str(target))
            sys.exit(0)
    except Exception:
        pass

try:
    target.mkdir(parents=True, exist_ok=True)
    print("Downloading multilingual Whisper Small to " + str(target), flush=True)
    result = Path(download_model("small", output_dir=str(target), local_files_only=False))
    if not complete(result):
        raise RuntimeError("download completed but required model files or config are incomplete")
    print("WHISPER_READY=" + str(result.resolve()))
    sys.exit(0)
except Exception as exc:
    print("WHISPER_FAILED=" + type(exc).__name__ + ": " + str(exc), file=sys.stderr)
    sys.exit(10)
'@

    Write-Host '[MODEL] Searching local Whisper Small caches before any download...' -ForegroundColor Cyan
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Python -c $pythonCode 2>&1)
        $pythonExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $combined = $output -join [Environment]::NewLine
    if ($pythonExit -eq 0 -and $combined -match 'WHISPER_READY=(.+)') {
        $script:Status.whisper.status = 'ready'
        $script:Status.whisper.path = $matches[1].Trim()
        $script:Status.whisper.cache_dir = $modelDir
        Write-Host "[OK] Whisper Small is ready: $($script:Status.whisper.path)" -ForegroundColor Green
        return
    }

    $warning = 'Whisper Small is not ready: ' + $combined
    $script:Status.whisper.status = 'warning_missing_or_download_failed'
    $script:Status.whisper.cache_dir = $modelDir
    $script:Warnings.Add($warning)
    Write-Host "[WARN] $warning" -ForegroundColor Yellow
    if ($RequireWhisper) { throw $warning }
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Missing model configuration: $ConfigPath" }
    $script:Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$script:Config.schema_version -ne 1) { throw 'Unsupported MODELS.json schema version.' }
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "Project Python is missing: $Python. Run LocalAI-Studio.bat repair." }

    New-Item -ItemType Directory -Force -Path $Root,$Platform,$Data,(Join-Path $Data 'Temp') | Out-Null
    $env:TEMP = Join-Path $Data 'Temp'
    $env:TMP = $env:TEMP
    $env:TMPDIR = $env:TEMP

    $apiVersion = Invoke-RestMethod -Uri ($BaseUrl + '/api/version') -TimeoutSec 8 -ErrorAction Stop
    $script:OllamaExe = Get-OllamaExe
    $script:Status.ollama.store = Get-ActiveModelStore
    Write-Host "Ollama $($apiVersion.version) is online. Checking Qwen 3.5 9B and Whisper Small." -ForegroundColor Cyan

    Ensure-QwenModel
    Ensure-WhisperModel
    Save-ModelStatus

    Write-Host "Model report: $StatusPath" -ForegroundColor Cyan
    if ($script:Warnings.Count -gt 0) {
        Write-Host 'Qwen chat is ready; local audio transcription needs a network retry.' -ForegroundColor Yellow
        if ($RequireWhisper) { exit 2 }
    }
    exit 0
} catch {
    $script:Status.error = $_.Exception.Message
    try { Save-ModelStatus } catch {}
    Write-Host "MODEL CHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
