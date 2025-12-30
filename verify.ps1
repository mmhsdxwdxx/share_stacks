# share_stacks 部署验证脚本 (Windows PowerShell)
# 用于检查所有服务是否正常运行

$ErrorActionPreference = "Continue"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "share_stacks 部署验证脚本" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# 加载环境变量
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

# 默认端口值
$NEWAPI_PORT = if ($env:NEWAPI_PORT) { $env:NEWAPI_PORT } else { "3000" }
$LITELLM_PORT = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { "4000" }
$MCPO_PORT = if ($env:MCPO_PORT) { $env:MCPO_PORT } else { "8010" }
$POSTGRES_PORT = if ($env:POSTGRES_PORT) { $env:POSTGRES_PORT } else { "5439" }
$VALKEY_PORT = if ($env:VALKEY_PORT) { $env:VALKEY_PORT } else { "6389" }

# 1. 检查 Docker 容器状态
Write-Host "1. 检查 Docker 容器状态" -ForegroundColor Cyan
Write-Host "-----------------------------------"
docker compose ps
Write-Host ""

# 2. 检查端口占用
Write-Host "2. 检查端口占用情况" -ForegroundColor Cyan
Write-Host "-----------------------------------"
$ports = @($NEWAPI_PORT, $LITELLM_PORT, $MCPO_PORT, $POSTGRES_PORT, $VALKEY_PORT)
$portNames = @("new-api", "litellm", "mcpo", "postgres", "valkey")

for ($i = 0; $i -lt $ports.Count; $i++) {
    $port = $ports[$i]
    $name = $portNames[$i]

    $connection = Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $port -and $_.State -eq "Listen" }

    if ($connection) {
        Write-Host "端口 $port ($name): " -NoNewline
        Write-Host "✓ 已监听" -ForegroundColor Green
    } else {
        Write-Host "端口 $port ($name): " -NoNewline
        Write-Host "✗ 未监听" -ForegroundColor Red
    }
}
Write-Host ""

# 3. 检查 new-api
Write-Host "3. 检查 new-api (端口 $NEWAPI_PORT)" -ForegroundColor Cyan
Write-Host "-----------------------------------"
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$NEWAPI_PORT/v1/models" -UseBasicParsing -TimeoutSec 5
    if ($response.Content -match "object|data") {
        Write-Host "✓ new-api 运行正常" -ForegroundColor Green
    } else {
        Write-Host "✗ new-api 响应异常" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ new-api 连接失败: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 4. 检查 LiteLLM
Write-Host "4. 检查 LiteLLM (端口 $LITELLM_PORT)" -ForegroundColor Cyan
Write-Host "-----------------------------------"
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$LITELLM_PORT/ui" -UseBasicParsing -TimeoutSec 5
    if ($response.Content -match "html|LiteLLM") {
        Write-Host "✓ LiteLLM UI 运行正常" -ForegroundColor Green
    } else {
        Write-Host "✗ LiteLLM UI 响应异常" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ LiteLLM UI 连接失败: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. 检查 mcpo OpenAPI
Write-Host "5. 检查 mcpo OpenAPI (端口 $MCPO_PORT)" -ForegroundColor Cyan
Write-Host "-----------------------------------"
if ($env:MCPO_API_KEY) {
    try {
        $headers = @{
            "Authorization" = "Bearer $($env:MCPO_API_KEY)"
        }
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$MCPO_PORT/deepwiki/openapi.json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        if ($response.Content -match "openapi") {
            Write-Host "✓ mcpo OpenAPI 运行正常" -ForegroundColor Green
        } else {
            Write-Host "✗ mcpo OpenAPI 响应异常" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ mcpo OpenAPI 连接失败: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ MCPO_API_KEY 未设置，跳过检查" -ForegroundColor Yellow
}
Write-Host ""

# 6. 检查 PostgreSQL 连接
Write-Host "6. 检查 PostgreSQL 连接" -ForegroundColor Cyan
Write-Host "-----------------------------------"
$postgresUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "postgres" }
$result = docker exec share_postgres pg_isready -U $postgresUser 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ PostgreSQL 连接正常" -ForegroundColor Green
} else {
    Write-Host "✗ PostgreSQL 连接失败" -ForegroundColor Red
}
Write-Host ""

# 7. 检查 Valkey 连接
Write-Host "7. 检查 Valkey 连接" -ForegroundColor Cyan
Write-Host "-----------------------------------"
if ($env:VALKEY_PASSWORD) {
    $result = docker exec share_valkey valkey-cli -a "$($env:VALKEY_PASSWORD)" ping 2>&1
    if ($result -match "PONG") {
        Write-Host "✓ Valkey 连接正常" -ForegroundColor Green
    } else {
        Write-Host "✗ Valkey 连接失败" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ VALKEY_PASSWORD 未设置，跳过检查" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "验证完成！" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "后续步骤建议:" -ForegroundColor Cyan
Write-Host "1. 在 LiteLLM UI 中创建 Virtual Key (LITELLM_MCP_VKEY)"
Write-Host "2. 更新 mcpo/config.json 中的 x-litellm-api-key"
Write-Host "3. 重启 mcpo: docker compose restart mcpo"
Write-Host "4. 在 OpenWebUI 中配置 OpenAPI Tool Server"
