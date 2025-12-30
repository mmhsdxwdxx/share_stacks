# share_stacks 目录结构初始化脚本 (Windows PowerShell)
# 用于创建部署所需的目录结构

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "share_stacks 目录结构初始化" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# 检查是否在项目根目录
if (-not (Test-Path "docker-compose.yml")) {
    Write-Host "错误: 请在 share_stacks 项目根目录下运行此脚本" -ForegroundColor Red
    exit 1
}

Write-Host "创建目录结构..." -ForegroundColor Green

# 创建主要目录
$directories = @(
    "litellm",
    "mcpo",
    "postgres-init",
    "newapi-data",
    "logs\newapi",
    "logs\litellm"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "✓ $dir" -ForegroundColor Green
    } else {
        Write-Host "✓ $dir (已存在)" -ForegroundColor Yellow
    }
}

Write-Host ""

# 检查 .env 文件
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Write-Host "复制 .env.example 到 .env" -ForegroundColor Green
        Copy-Item ".env.example" ".env"
        Write-Host "⚠ 请编辑 .env 文件，修改所有密码和密钥！" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "警告: .env.example 文件不存在" -ForegroundColor Yellow
    }
} else {
    Write-Host "✓ .env 文件已存在" -ForegroundColor Green
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "初始化完成！" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "下一步操作:" -ForegroundColor Cyan
Write-Host "1. 编辑 .env 文件，修改所有密码和密钥"
Write-Host "2. 运行: docker compose up -d"
Write-Host "3. 运行验证脚本: powershell -File verify.ps1"
