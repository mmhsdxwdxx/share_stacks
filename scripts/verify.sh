#!/usr/bin/env bash
set -euo pipefail

check_http() {
  local name="$1"
  local url="$2"

  echo -n "CHECK ${name} ... "
  if curl -fsS "$url" >/dev/null; then
    echo "OK"
  else
    echo "FAIL"
    return 1
  fi
}

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env || true
  set +a
fi

NEWAPI_PORT="${NEWAPI_PORT:-3000}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
MCPO_PORT="${MCPO_PORT:-8010}"

echo "1) docker compose ps"
docker compose ps

echo "2) http health"
check_http "new-api" "http://127.0.0.1:${NEWAPI_PORT}/v1/models"
check_http "litellm" "http://127.0.0.1:${LITELLM_PORT}/health"
check_http "mcpo" "http://127.0.0.1:${MCPO_PORT}/health"

echo "3) postgres"
docker exec share_postgres pg_isready -U "${POSTGRES_USER:-postgres}" >/dev/null

echo "4) valkey"
if [ -n "${VALKEY_PASSWORD:-}" ]; then
  docker exec share_valkey valkey-cli -a "${VALKEY_PASSWORD}" ping | grep -q PONG
else
  echo "SKIP: VALKEY_PASSWORD empty"
fi

echo "OK: verify done"
