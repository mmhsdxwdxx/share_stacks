#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "share_stacks diagnostics"
echo "========================================="
echo ""

echo "1) docker compose ps"
echo "-----------------------------------"
docker compose ps
echo ""

echo "2) container stats (live)"
echo "-----------------------------------"
docker stats --no-stream
echo ""

echo "3) resource limits check"
echo "-----------------------------------"
echo "LiteLLM memory limit:"
docker inspect share_litellm --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "Container not running"
echo "new-api memory limit:"
docker inspect share_newapi --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "Container not running"
echo "PostgreSQL memory limit:"
docker inspect share_postgres --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "Container not running"
echo ""

echo "4) recent logs (last 50 lines)"
echo "-----------------------------------"
echo "Select service to view logs:"
echo "  1) new-api"
echo "  2) litellm"
echo "  3) mcpo"
echo "  4) postgres"
echo "  5) valkey"
echo "  6) skip"
read -p "Choose (1-6): " log_choice

case $log_choice in
  1) docker compose logs new-api --tail=50 ;;
  2) docker compose logs litellm --tail=50 ;;
  3) docker compose logs mcpo --tail=50 ;;
  4) docker compose logs postgres --tail=50 ;;
  5) docker compose logs valkey --tail=50 ;;
  6) echo "Skipping logs" ;;
esac

echo ""
echo "========================================="
echo "Diagnostics complete"
echo "========================================="
