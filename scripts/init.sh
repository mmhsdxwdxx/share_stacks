#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "share_stacks init"
echo "========================================="

if [ ! -f "docker-compose.yml" ]; then
  echo "ERROR: run this script in repo root (docker-compose.yml missing)."
  exit 1
fi

mkdir -p litellm mcpo postgres-init newapi-data logs/newapi logs/litellm

echo "OK: directories ensured."

if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo "WARN: .env created from .env.example. Please change all CHANGE_ME_* values."
  else
    echo "WARN: .env.example not found; cannot create .env."
  fi
else
  echo "OK: .env already exists."
fi
