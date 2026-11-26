$ErrorActionPreference = 'Stop'
$Platform = 'D:\LocalAI\Platform'
$Python = Join-Path $Platform '.venv\Scripts\python.exe'
$backup = Join-Path $Platform 'Backups\OpenWebUI\custom.css.original'
if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw 'No original CSS backup was found. Nothing was changed.' }
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Project Python was not found. Run platform repair first.' }
$probe = & $Python -c 'import importlib.util,pathlib; s=importlib.util.find_spec("open_webui"); print(str(pathlib.Path(s.origin).parent / "static" / "custom.css") if s and s.origin else "")'
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve Open WebUI static asset directory.' }
$customCss = [string]($probe | Select-Object -Last 1)
$customCss = $customCss.Trim()
if (-not $customCss) { throw 'Open WebUI static custom.css was not found.' }
Copy-Item -LiteralPath $backup -Destination $customCss -Force
Write-Host '[SUCCESS] Original Open WebUI custom.css restored. Restart Open WebUI to refresh browser assets.' -ForegroundColor Green
