param(
  [switch]$Apply,
  [string]$TrashDir = ".trash",
  [string[]]$Roots = @("."),
  [switch]$IncludeLegacyData
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$trashRoot = Join-Path $repoRoot $TrashDir
$trashRun = Join-Path $trashRoot $timestamp

$directoryNames = @(
  "__pycache__",
  ".pytest_cache",
  ".mypy_cache",
  ".ruff_cache",
  ".cache",
  ".venv",
  "node_modules",
  "dist",
  "build",
  "coverage",
  ".next",
  ".turbo",
  "target"
)

$exactFileNames = @(
  ".DS_Store",
  "Thumbs.db"
)

$filePatterns = @(
  "*.log",
  "*.tmp",
  "*.swp",
  "*.swo",
  "*.bak",
  "*~"
)

function Test-IsExcludedPath {
  param([string]$fullName)
  $normalized = $fullName.Replace("/", "\")
  return (
    $normalized -match "\\\.git(\\|$)" -or
    $normalized -match "\\\.trash(\\|$)"
  )
}

function Get-RelativePath {
  param([string]$basePath, [string]$targetPath)
  $base = [System.IO.Path]::GetFullPath($basePath)
  $target = [System.IO.Path]::GetFullPath($targetPath)
  return [System.IO.Path]::GetRelativePath($base, $target)
}

$candidates = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]

foreach ($root in $Roots) {
  $rootPath = Resolve-Path (Join-Path $repoRoot $root)

  Get-ChildItem -Path $rootPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if (Test-IsExcludedPath -fullName $_.FullName) { return }

    if ($_.PSIsContainer) {
      if ($directoryNames -contains $_.Name) {
        $candidates.Add($_)
      }
      return
    }

    if ($exactFileNames -contains $_.Name) {
      $candidates.Add($_)
      return
    }

    foreach ($pattern in $filePatterns) {
      if ($_.Name -like $pattern) {
        $candidates.Add($_)
        return
      }
    }
  }
}

if ($IncludeLegacyData) {
  foreach ($legacy in @("newapi-data")) {
    $legacyPath = Join-Path $repoRoot $legacy
    if (Test-Path $legacyPath) {
      $candidates.Add((Get-Item -Force $legacyPath))
    }
  }
}

$uniqueCandidates = $candidates |
  Sort-Object FullName -Unique |
  Where-Object { Test-Path $_.FullName }

if (-not $uniqueCandidates -or $uniqueCandidates.Count -eq 0) {
  Write-Host "No cleanup candidates found."
  exit 0
}

Write-Host "Cleanup candidates (dry-run=$(-not $Apply)):"
$uniqueCandidates | ForEach-Object { Write-Host ("- " + (Get-RelativePath -basePath $repoRoot -targetPath $_.FullName)) }

if (-not $Apply) {
  Write-Host ""
  Write-Host "Nothing moved. Re-run with -Apply to move candidates into '$TrashDir\\$timestamp\\...'."
  exit 0
}

New-Item -ItemType Directory -Force -Path $trashRun | Out-Null

foreach ($item in $uniqueCandidates) {
  $relative = Get-RelativePath -basePath $repoRoot -targetPath $item.FullName
  $dest = Join-Path $trashRun $relative
  $destParent = Split-Path -Parent $dest

  if (-not (Test-Path $destParent)) {
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
  }

  Move-Item -Force -Path $item.FullName -Destination $dest
}

Write-Host ""
Write-Host "Moved $($uniqueCandidates.Count) item(s) to: $trashRun"
