# share_stacks - API + MCP Hub 堆栈（运行与维护要点）

share_stacks 是一个面向 1Panel 的 Docker Compose 堆栈，提供：

- **API 网关**：gpt-load（透明代理）
- **MCP Hub**：LiteLLM（Streamable HTTP）
- **基础设施**：PostgreSQL（pgvector）+ Valkey（Redis 兼容）
- **可选能力**：SearXNG / Playwright MCP / Firecrawl

## 快速开始（本仓库当前仅维护单一 Compose）

```bash
cp .env.example .env
vim .env  # 替换所有 CHANGE_ME
docker network create 1panel-network
docker compose up -d
docker compose ps
```

## 关键文件

- `docker-compose.yml`: 所有服务统一接入外部网络 `1panel-network`。
- `.env.example`: 环境变量模板（每项都有注释）；实际部署请复制为 `.env` 并填充密钥/密码。
- `litellm/config.yaml`: LiteLLM 的 DB/缓存与 MCP server 配置。
- `postgres-init/02-enable-extensions.sql`: 由一次性任务 `share_pg_init` 执行（扩展启用）。
- `1panel-deployment-guide.md`: 1Panel 反向代理与部署步骤。
- `network-design.md`: 网络与端口暴露策略说明。

## 运维检查

- `share_pg_init` 是一次性初始化任务：应显示 `exited (0)`；失败先看 `docker logs share_pg_init`。
- 密码会出现在 DSN/URL 中（Postgres/Valkey/RabbitMQ）：建议使用 URL-safe 密码或自行 percent-encode，避免连接串解析失败。
