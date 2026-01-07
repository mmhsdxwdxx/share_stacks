# Repository Guidelines

## Project Structure & Module Organization

This repo is a Docker Compose stack for 1Panel deployments (API gateway + MCP hub) built around PostgreSQL + Valkey.

- `docker-compose.yml`: the maintained Compose definition (all services attach to `1panel-network`).
- `.env.example`: documented environment template (copy to `.env` and fill secrets locally).
- `.env`: runtime configuration (keep secrets out of Git).
- `litellm/config.yaml`: LiteLLM (MCP hub) configuration.
- `postgres-init/`: SQL used by `pg_init` to create DBs/users and enable extensions.
- `scripts/`: utilities like `scripts/safe_cleanup.ps1` (safe, reversible cleanup).
- `*.md`: operational docs (`README.md`, `network-design.md`, `building-rules.md`).
- `searxng/`: local SearXNG config only (the service itself runs from the `searxng/searxng` image).

## Build, Test, and Development Commands

- `docker compose up -d`: start the default (simple) stack.
- `docker compose ps`: check container status (expect `share_pg_init` to exit `0` after initialization).
- `docker compose logs -f <service>`: inspect logs while debugging.
- `curl http://localhost:3001/health` / `curl http://localhost:4000/health`: basic liveness checks.
- `pwsh ./scripts/safe_cleanup.ps1` (preview) / `pwsh ./scripts/safe_cleanup.ps1 -Apply`: move generated junk to `.trash/` (no deletion).

## Coding Style & Naming Conventions

- YAML: 2-space indentation; keep values and env-var references consistent with existing files.
- Env vars: `UPPER_SNAKE_CASE` in `.env`; avoid committing real secrets/keys.
- Docker Compose variants: prefer the existing naming pattern `docker-compose.<scenario>.yml`.

## Testing Guidelines

There are no unit tests in this repo. Validate changes by:

- `docker compose config` to catch YAML/schema issues.
- Bringing the stack up and verifying health endpoints + expected ports.

## Commit & Pull Request Guidelines

This root workspace may not have Git history available; use Conventional Commits:

- Examples: `feat: add service X`, `fix: pg_init quoting`, `docs: update deployment guide`.

PRs should include: what changed, which compose variant was tested, and any config/doc updates needed (plus screenshots for 1Panel proxy changes when relevant).
