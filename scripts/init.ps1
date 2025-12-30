$ErrorActionPreference = "Stop"

Write-Host "========================================="
Write-Host "share_stacks init"
Write-Host "========================================="

if (-not (Test-Path "docker-compose.yml")) {
  Write-Error "Run this script in repo root (docker-compose.yml missing)."
  exit 1
}

$dirs = @(
  "litellm",
  "mcpo",
  "postgres-init",
  "newapi-data",
  "logs\newapi",
  "logs\litellm"
)

foreach ($d in $dirs) {
  New-Item -ItemType Directory -Path $d -Force | Out-Null
}

if (-not (Test-Path ".env")) {
  if (Test-Path ".env.example") {
    Copy-Item ".env.example" ".env"
    Write-Warning ".env created from .env.example. Please change all CHANGE_ME_* values."
  } else {
    Write-Warning ".env.example not found; cannot create .env."
  }
} else {
  Write-Host "OK: .env already exists."
}
