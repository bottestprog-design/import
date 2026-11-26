$ErrorActionPreference='Stop'
$uri='http://127.0.0.1:11434/api/chat'
$tags=Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
$model=$tags.models | Where-Object {$_.name -eq 'local-qwen35:latest' -or $_.name -like 'local-qwen35*'} | Select-Object -First 1
if(-not $model){$model=$tags.models | Where-Object {$_.name -like 'qwen3.5:9b-q4_K_M*'} | Select-Object -First 1}
if(-not $model){throw 'Qwen model tag not found. This test will not download anything.'}
$body=@{
  model=$model.name
  messages=@(@{role='user';content='أجب بالعربية بجملة قصيرة: اكتب كلمة جاهز ثم احسب 2+2.'})
  think=$false
  stream=$false
  keep_alive='0'
  options=@{num_ctx=4096;num_predict=128;temperature=0.1}
}
$json=ConvertTo-Json -InputObject $body -Depth 10 -Compress
Write-Host "Testing actual inference with $($model.name). This may take several minutes on CPU; no model download is performed." -ForegroundColor Cyan
try { $response=Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 900 }
catch { throw "Ollama chat request failed: $($_.Exception.Message)" }
$content=[string]$response.message.content
$thinking=[string]$response.message.thinking
if([string]::IsNullOrWhiteSpace($content)) {
  if(-not [string]::IsNullOrWhiteSpace($thinking)) { throw "Model returned thinking but no final content. done=$($response.done) reason=$($response.done_reason). Test uses think=false, so inspect Ollama logs." }
  throw 'Model response content is empty. Inspect server.log; the model is installed but inference is not verified.'
}
if($response.done -ne $true){throw "Response did not finish. done_reason=$($response.done_reason)"}
Write-Host "[SUCCESS] Model inference completed. done_reason=$($response.done_reason)" -ForegroundColor Green
Write-Host "MODEL RESPONSE: $content"
$report=Join-Path 'D:\LocalAI\Logs' ('model-inference-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
@("Model: $($model.name)","Done: $($response.done)","Done reason: $($response.done_reason)","Response: $content") | Set-Content $report -Encoding UTF8
Write-Host "Report: $report"
