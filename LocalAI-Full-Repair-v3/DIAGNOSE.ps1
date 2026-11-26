$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $env:USERPROFILE }
$out = Join-Path $desktop "LocalAI-Diagnostics-v3-$stamp.txt"
$lines = New-Object System.Collections.Generic.List[string]
function AddLine([string]$s) { [void]$lines.Add($s) }
function Safe([string]$s) { if ($null -eq $s) { return '' }; return ($s -replace '(?i)(https?://[^\s"''<>?]+)\?[^\s"''<>]+', '$1?[SIGNED_QUERY_REDACTED]') }
AddLine 'LOCAL AI DIAGNOSTIC REPORT V3 - READ ONLY'
AddLine "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
AddLine 'No API keys, tokens, passwords, or secret file contents are collected.'
AddLine ''
AddLine '[WINDOWS]'
try { $os = Get-CimInstance Win32_OperatingSystem; AddLine "Caption: $($os.Caption)"; AddLine "Version: $($os.Version)"; AddLine "Build: $($os.BuildNumber)" } catch { AddLine "OS query failed: $($_.Exception.Message)" }
AddLine "PowerShell: $($PSVersionTable.PSVersion)"
AddLine ''
AddLine '[CPU RAM GPU]'
try { Get-CimInstance Win32_Processor | ForEach-Object { AddLine "CPU: $($_.Name) | cores=$($_.NumberOfCores) | logical=$($_.NumberOfLogicalProcessors)" } } catch {}
try { $ram=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; AddLine "RAM GB: $([math]::Round($ram/1GB,1))" } catch {}
try { Get-CimInstance Win32_VideoController | ForEach-Object { AddLine "GPU: $($_.Name) | VRAM bytes=$($_.AdapterRAM)" } } catch {}
AddLine ''
AddLine '[DRIVES]'
try { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { AddLine "$($_.DeviceID) totalGB=$([math]::Round($_.Size/1GB,1)) freeGB=$([math]::Round($_.FreeSpace/1GB,1))" } } catch {}
AddLine ''
AddLine '[OLLAMA]'
AddLine "User OLLAMA_MODELS: $([Environment]::GetEnvironmentVariable('OLLAMA_MODELS','User'))"
AddLine "Process OLLAMA_MODELS: $env:OLLAMA_MODELS"
$ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ollama) { AddLine "Executable: $($ollama.Source)"; try { AddLine (Safe ((& $ollama.Source --version | Out-String).Trim())) } catch { AddLine "Version error: $($_.Exception.Message)" } } else { AddLine 'ollama.exe: NOT FOUND' }
try { $v=Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 5; AddLine "API: OK $($v.version)" } catch { AddLine "API: NOT READY $($_.Exception.Message)" }
try { $t=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10; AddLine 'Model tags:'; foreach($m in $t.models){AddLine "  $($m.name) size=$($m.size)"} } catch { AddLine "Tags error: $($_.Exception.Message)" }
$serverLog = Join-Path $env:LOCALAPPDATA 'Ollama\server.log'
if (Test-Path $serverLog) { AddLine 'Latest server config OLLAMA_MODELS lines (redacted):'; Get-Content $serverLog -Tail 1000 | Where-Object { $_ -match '(?i)server config' -and $_ -match 'OLLAMA_MODELS:' } | Select-Object -Last 5 | ForEach-Object { AddLine (Safe $_) } }
$recoveryLogs = Get-ChildItem 'D:\LocalAI\Logs' -Filter 'model-recovery-v3-*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($recoveryLogs -and $recoveryLogs.Count -gt 0) {
    AddLine "Latest recovery log: $($recoveryLogs[0].FullName)"
    Get-Content -LiteralPath $recoveryLogs[0].FullName -Tail 120 -ErrorAction SilentlyContinue | ForEach-Object { AddLine (Safe $_) }
} else { AddLine 'No model-recovery-v3 log found.' }
foreach ($p in @('D:\LocalAI\Models','C:\Users\'+$env:USERNAME+'\.ollama\models')) {
    if (Test-Path $p) { try { $files=Get-ChildItem $p -File -Recurse -ErrorAction SilentlyContinue; $bytes=($files | Measure-Object Length -Sum).Sum; AddLine "Model directory: $p | files=$($files.Count) | sizeGB=$([math]::Round($bytes/1GB,2))" } catch { AddLine "Model directory: $p | size query failed" } }
}
AddLine ''
AddLine '[LOCAL SERVICES]'
foreach ($port in @(11434,8080)) {
    $c = $null
    try {
        $c = New-Object Net.Sockets.TcpClient
        $a = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        $ok = $a.AsyncWaitHandle.WaitOne(800)
        if ($ok -and $c.Connected) { AddLine ("127.0.0.1:$port LISTENING") }
        else { AddLine ("127.0.0.1:$port NOT LISTENING") }
    } catch { AddLine ("127.0.0.1:$port NOT LISTENING") }
    finally { if ($c) { $c.Close() } }
}
try { $r=Invoke-WebRequest 'http://127.0.0.1:8080/ready' -TimeoutSec 4 -UseBasicParsing; AddLine "Open WebUI /ready: HTTP $($r.StatusCode)" } catch { AddLine 'Open WebUI /ready: NOT READY' }
AddLine ''
AddLine '[RECENT LOCAL AI LOGS - TAIL 60]'
$logDir='D:\LocalAI\Logs'
if(Test-Path $logDir){Get-ChildItem $logDir -File -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 6 | ForEach-Object { AddLine "--- $($_.Name)"; Get-Content $_.FullName -Tail 60 -ErrorAction SilentlyContinue | ForEach-Object { AddLine (Safe $_) } }} else {AddLine 'D:\LocalAI\Logs not found.'}
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "Diagnostic report created: $out" -ForegroundColor Green
Write-Host 'Review personal Windows paths before uploading. Secret files are not read.' -ForegroundColor Yellow
