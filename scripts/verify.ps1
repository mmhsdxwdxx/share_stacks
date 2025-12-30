$ErrorActionPreference = "Stop"

function Import-DotEnv([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line) { return }
    if ($line.StartsWith('#')) { return }
    if ($line -match '^([^=]+)=(.*)$') {
      $name = $matches[1].Trim()
      $value = $matches[2].Trim()
      Set-Item -Path "env:$name" -Value $value
    }
  }
}

Import-DotEnv ".env"

$NEWAPI_PORT = if ($env:NEWAPI_PORT) { $env:NEWAPI_PORT } else { "3000" }
$LITELLM_PORT = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { "4000" }
$MCPO_PORT = if ($env:MCPO_PORT) { $env:MCPO_PORT } else { "8010" }

function Test-Http([string]$Name, [string]$Url) {
  Write-Host -NoNewline "CHECK $Name ... "
  try {
    Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "OK"
  } catch {
    Write-Host "FAIL"
    throw
  }
}

Write-Host "1) docker compose ps"
docker compose ps

Write-Host "2) http health"
Test-Http "new-api" "http://127.0.0.1:$NEWAPI_PORT/v1/models"
Test-Http "litellm" "http://127.0.0.1:$LITELLM_PORT/health"
Test-Http "mcpo" "http://127.0.0.1:$MCPO_PORT/health"

Write-Host "OK: verify done"
