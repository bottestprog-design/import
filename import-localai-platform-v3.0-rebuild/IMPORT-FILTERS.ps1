$ErrorActionPreference='Stop'
$Base='http://127.0.0.1:8080'
$FilterDir=Join-Path 'D:\LocalAI\Platform' 'Filters'
function Api([string]$Method,[string]$Path,$Body=$null) {
  $p=@{Uri=($Base+$Path);Method=$Method;Headers=$script:Headers;TimeoutSec=60;ErrorAction='Stop'}
  if($null -ne $Body){$p.ContentType='application/json; charset=utf-8';$p.Body=ConvertTo-Json -InputObject $Body -Depth 30 -Compress}
  Invoke-RestMethod @p
}
$secure=$null;$token=$null
try {
  Invoke-RestMethod "$Base/ready" -TimeoutSec 5 | Out-Null
  Write-Host 'Create an admin API key in Settings > Account > API Keys.' -ForegroundColor Yellow
  Write-Host 'The token is read as a hidden secure input and is not saved or logged.' -ForegroundColor Yellow
  $secure=Read-Host 'Admin API key' -AsSecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try{$token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  $script:Headers=@{Authorization="Bearer $token";Accept='application/json'}
  $all=Api 'GET' '/api/v1/functions/'
  if($all -and ($all.PSObject.Properties.Name -contains 'functions')){$items=@($all.functions)}else{$items=@($all)}
  $specs=@(
    @{Id='localai_trusted_content_guard';Name='Local AI - Trusted Content Guard';File='01-Trusted-Content-Guard.py'},
    @{Id='localai_accuracy_thinking';Name='Local Qwen - Accuracy and Thinking';File='02-Accuracy-Thinking.py'},
    @{Id='localai_selective_self_review';Name='Local Qwen - Selective Self Review';File='03-Selective-Self-Review.py'}
  )
  $backupDir='D:\LocalAI\Platform\Backups\Functions';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
  foreach($s in $specs){
    $file=Join-Path $FilterDir $s.File;if(-not(Test-Path $file)){throw "Missing source $file"}
    $source=Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $existing=@($items|Where-Object{$_.id -eq $s.Id}|Select-Object -First 1)
    $sameName=@($items|Where-Object{$_.name -eq $s.Name -and $_.id -ne $s.Id})
    if($sameName.Count -gt 0){throw "Duplicate name already exists with another ID: $($sameName[0].id). Review it manually before proceeding."}
    $payload=@{id=$s.Id;name=$s.Name;content=$source;meta=@{description=$s.Name;manifest=@{}};commit_message='Local AI platform continuation v1'}
    if($existing.Count -gt 0){
      $cur=Api 'GET' ("/api/v1/functions/id/"+[Uri]::EscapeDataString($s.Id))
      if($cur.type -ne 'filter'){throw "Existing ID $($s.Id) is not a filter; refusing to overwrite."}
      $cur|ConvertTo-Json -Depth 30|Set-Content (Join-Path $backupDir ($s.Id+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')) -Encoding UTF8
      $saved=Api 'POST' ("/api/v1/functions/id/"+[Uri]::EscapeDataString($s.Id)+'/update') $payload
    } else {$saved=Api 'POST' '/api/v1/functions/create' $payload}
    if($saved.type -and $saved.type -ne 'filter'){throw "Open WebUI did not detect $($s.Name) as a Filter."}
    $idPath = "/api/v1/functions/id/"+[Uri]::EscapeDataString($s.Id)
    $state=Api 'GET' $idPath
    if($state.type -ne 'filter'){throw "Open WebUI did not register $($s.Id) as a Filter (reported type: $($state.type))."}
    if(-not $state.is_active){
      $null=Api 'POST' ($idPath+'/toggle')
      $state=Api 'GET' $idPath
    }
    if(-not $state.is_global){
      $null=Api 'POST' ($idPath+'/toggle/global')
      $state=Api 'GET' $idPath
    }
    if(-not $state.is_active -or -not $state.is_global){throw "Could not confirm Active and Global for $($s.Id)."}
    Write-Host "[OK] $($s.Name) is a Filter, Active and Global." -ForegroundColor Green
  }
  Write-Host 'All three filters were imported, activated and set Global.' -ForegroundColor Green
} catch { Write-Host "FILTER IMPORT FAILED: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
finally{$token=$null;$script:Headers=$null;if($secure){$secure.Dispose()};[GC]::Collect()}
