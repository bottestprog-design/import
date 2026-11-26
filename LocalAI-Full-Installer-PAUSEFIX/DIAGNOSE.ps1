$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $env:USERPROFILE }
$out = Join-Path $desktop "LocalAI-Diagnostics-$stamp.txt"
$lines = New-Object System.Collections.Generic.List[string]
function AddLine([string]$s) { [void]$lines.Add($s) }
function AddCommand([string]$name, [string[]]$cliArgs = @()) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { AddLine "$name : NOT FOUND"; return }
    AddLine "$name : $($cmd.Source)"
    if ($cliArgs.Count -gt 0) {
        try { $v = & $cmd.Source @cliArgs 2>&1 | Select-Object -First 2; foreach ($x in $v) { AddLine "  $x" } } catch { AddLine "  ERROR: $($_.Exception.Message)" }
    }
}
AddLine 'LOCAL AI DIAGNOSTIC REPORT - READ ONLY'
AddLine "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
AddLine 'No API keys, tokens, or secret file contents are collected.'
AddLine ''
AddLine '[WINDOWS]'
try { $os = Get-CimInstance Win32_OperatingSystem; AddLine "Caption: $($os.Caption)"; AddLine "Version: $($os.Version)"; AddLine "Build: $($os.BuildNumber)"; AddLine "Architecture: $env:PROCESSOR_ARCHITECTURE" } catch { AddLine "OS query failed: $($_.Exception.Message)" }
AddLine "PowerShell: $($PSVersionTable.PSVersion)"
AddLine ''
AddLine '[CPU / RAM / GPU]'
try { Get-CimInstance Win32_Processor | ForEach-Object { AddLine "CPU: $($_.Name) | cores=$($_.NumberOfCores) | logical=$($_.NumberOfLogicalProcessors)" } } catch {}
try { $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; AddLine ('RAM GB: ' + [math]::Round($ram/1GB,1)) } catch {}
try { Get-CimInstance Win32_VideoController | ForEach-Object { AddLine "GPU: $($_.Name) | VRAM bytes=$($_.AdapterRAM)" } } catch {}
AddLine ''
AddLine '[DRIVES]'
try { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { AddLine "$($_.DeviceID) totalGB=$([math]::Round($_.Size/1GB,1)) freeGB=$([math]::Round($_.FreeSpace/1GB,1))" } } catch {}
AddLine ''
AddLine '[TOOLS]'
AddCommand 'winget.exe' @('--version')
AddCommand 'ollama.exe' @('--version')
AddCommand 'ffmpeg.exe' @('-version')
AddCommand 'py.exe' @('--version')
AddCommand 'python.exe' @('--version')
AddLine ''
AddLine '[LOCAL SERVICES]'
foreach ($p in @(11434,8080)) {
    try { $c = New-Object System.Net.Sockets.TcpClient; $a = $c.BeginConnect('127.0.0.1',$p,$null,$null); $ok = $a.AsyncWaitHandle.WaitOne(700); if ($ok -and $c.Connected) { AddLine "127.0.0.1:$p LISTENING" } else { AddLine "127.0.0.1:$p NOT LISTENING" }; $c.Close() } catch { AddLine "127.0.0.1:$p NOT LISTENING" }
}
try { $v = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3; AddLine "Ollama API: OK version=$($v.version)" } catch { AddLine "Ollama API: ERROR $($_.Exception.Message)" }
try { $t = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5; AddLine 'Ollama models:'; foreach ($m in $t.models) { AddLine "  $($m.name) size=$($m.size)" } } catch { AddLine "Ollama tags: unavailable ($($_.Exception.Message))" }
try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/ready' -TimeoutSec 3 -UseBasicParsing; AddLine "Open WebUI ready endpoint: HTTP $($r.StatusCode)" } catch { AddLine "Open WebUI ready endpoint: ERROR $($_.Exception.Message)" }
AddLine ''
AddLine '[INSTALL STATUS FILES]'
foreach ($p in @('D:\LocalAI\ENGINE-STATUS.txt','D:\LocalAI\Platform\PLATFORM-STATUS.txt','D:\LocalAI\FULL-STATUS.txt')) {
    if (Test-Path $p) { AddLine "--- $p"; Get-Content $p -TotalCount 25 | ForEach-Object { AddLine $_ } } else { AddLine "MISSING: $p" }
}
AddLine ''
AddLine '[LATEST INSTALL LOG TAILS]'
$logDir = 'D:\LocalAI\Logs'
if (Test-Path $logDir) {
    Get-ChildItem $logDir -File -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
        AddLine "--- $($_.FullName)"
        Get-Content $_.FullName -Tail 35 -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -match '(?i)(api[_ -]?key|token|secret|password)\s*[:=]') { AddLine '[REDACTED POSSIBLE SECRET LINE]' } else { AddLine $_ } }
    }
} else { AddLine 'D:\LocalAI\Logs not found.' }
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "Diagnostic report created: $out" -ForegroundColor Green
Write-Host 'Review it for personal paths before uploading it to chat.' -ForegroundColor Yellow
