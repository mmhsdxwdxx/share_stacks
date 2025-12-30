#!/bin/bash

# share_stacks 部署验证脚本
# 用于检查所有服务是否正常运行

set -e

echo "========================================="
echo "share_stacks 部署验证脚本"
echo "========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_service() {
    local service_name=$1
    local service_url=$2
    local expected_pattern=$3

    echo -n "检查 $service_name ... "

    if curl -sS "$service_url" 2>/dev/null | grep -q "$expected_pattern"; then
        echo -e "${GREEN}✓ 正常${NC}"
        return 0
    else
        echo -e "${RED}✗ 失败${NC}"
        return 1
    fi
}

# 1. 检查 Docker 容器状态
echo "1. 检查 Docker 容器状态"
echo "-----------------------------------"
docker compose ps
echo ""

# 2. 检查端口占用
echo "2. 检查端口占用情况"
echo "-----------------------------------"
source .env 2>/dev/null || true
for port in "${NEWAPI_PORT:-3000}" "${LITELLM_PORT:-4000}" "${MCPO_PORT:-8010}" "${POSTGRES_PORT:-5439}" "${VALKEY_PORT:-6389}"; do
    if netstat -an | grep -q ":$port.*LISTEN" || ss -lntp 2>/dev/null | grep -q ":$port "; then
        echo -e "端口 $port: ${GREEN}已监听${NC}"
    else
        echo -e "端口 $port: ${RED}未监听${NC}"
    fi
done
echo ""

# 3. 检查 new-api
echo "3. 检查 new-api (端口 ${NEWAPI_PORT:-3000})"
echo "-----------------------------------"
check_service "new-api" "http://127.0.0.1:${NEWAPI_PORT:-3000}/v1/models" "object\|data"
echo ""

# 4. 检查 LiteLLM
echo "4. 检查 LiteLLM (端口 ${LITELLM_PORT:-4000})"
echo "-----------------------------------"
check_service "LiteLLM UI" "http://127.0.0.1:${LITELLM_PORT:-4000/ui" "html\|LiteLLM"
echo ""

# 5. 检查 mcpo OpenAPI
echo "5. 检查 mcpo OpenAPI (端口 ${MCPO_PORT:-8010})"
echo "-----------------------------------"
if [ -n "$MCPO_API_KEY" ]; then
    check_service "mcpo deepwiki" "http://127.0.0.1:${MCPO_PORT:-8010}/deepwiki/openapi.json" "openapi"
else
    echo -e "${YELLOW}⚠ MCPO_API_KEY 未设置，跳过检查${NC}"
fi
echo ""

# 6. 检查 PostgreSQL 连接
echo "6. 检查 PostgreSQL 连接"
echo "-----------------------------------"
if docker exec share_postgres pg_isready -U ${POSTGRES_USER:-postgres} >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL 连接正常${NC}"
else
    echo -e "${RED}✗ PostgreSQL 连接失败${NC}"
fi
echo ""

# 7. 检查 Valkey 连接
echo "7. 检查 Valkey 连接"
echo "-----------------------------------"
if docker exec share_valkey valkey-cli -a ${VALKEY_PASSWORD} ping 2>/dev/null | grep -q PONG; then
    echo -e "${GREEN}✓ Valkey 连接正常${NC}"
else
    echo -e "${RED}✗ Valkey 连接失败${NC}"
fi
echo ""

# 8. 查看日志（最后20行）
echo "8. 最近日志（最后20行）"
echo "-----------------------------------"
echo "选择要查看的服务日志:"
echo "  1) new-api"
echo "  2) litellm"
echo "  3) mcpo"
echo "  4) postgres"
echo "  5) valkey"
echo "  6) 跳过"
read -p "请选择 (1-6): " log_choice

case $log_choice in
    1) docker compose logs new-api --tail=20 ;;
    2) docker compose logs litellm --tail=20 ;;
    3) docker compose logs mcpo --tail=20 ;;
    4) docker compose logs postgres --tail=20 ;;
    5) docker compose logs valkey --tail=20 ;;
    6) echo "跳过日志查看" ;;
esac

echo ""
echo "========================================="
echo -e "${GREEN}验证完成！${NC}"
echo "========================================="
echo ""
echo "后续步骤建议:"
echo "1. 在 LiteLLM UI 中创建 Virtual Key (LITELLM_MCP_VKEY)"
echo "2. 更新 mcpo/config.json 中的 x-litellm-api-key"
echo "3. 重启 mcpo: docker compose restart mcpo"
echo "4. 在 OpenWebUI 中配置 OpenAPI Tool Server"
