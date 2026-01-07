# share_stacks - Agent 基础堆栈（gpt-load + LiteLLM）

> 面向 1Panel 的 Docker Compose 堆栈：算力 API 走 `gpt-load`，MCP Hub 走 `LiteLLM`，底座为 PostgreSQL + Valkey，并可选集成 SearXNG / Playwright / Firecrawl。

## 快速开始

1) 准备环境变量（不要直接提交 `.env`）

```bash
cp .env.example .env
vim .env  # 替换所有 CHANGE_ME
```

2) 确认 `1panel-network` 已存在

```bash
docker network create 1panel-network
```

3) 启动并查看状态

```bash
docker compose up -d
docker compose ps
```

## 服务与端口（默认）

说明：除数据库类服务外，其它服务默认都会发布到宿主机端口（便于 LAN 直连）；Postgres/Valkey 的 `ports` 在 `docker-compose.yml` 中默认注释掉。

| 服务 | 容器名 | 容器端口 | 宿主机端口 | 说明 |
|------|--------|----------|------------|------|
| gpt-load | share_gptload | 3001 | `${GPTLOAD_PORT}` | 算力 API 透明代理 |
| LiteLLM | share_litellm | 4000 | `${LITELLM_PORT}` | MCP Hub（Streamable HTTP） |
| SearXNG | share_searxng | 8080 | `${SEARXNG_PORT}` | 元搜索 |
| Playwright MCP | share_playwright | `${PLAYWRIGHT_MCP_PORT}` | `${PLAYWRIGHT_PORT}` | Browser MCP Server（可选） |
| Firecrawl | share_firecrawl | 3002 | `${FIRECRAWL_PORT}` | 爬取/抽取服务（可选） |
| Firecrawl PW | share_firecrawl_pw | `${FIRECRAWL_PW_PORT}` | `${FIRECRAWL_PW_PORT}` | `/scrape` 微服务（可选） |
| PostgreSQL | share_postgres | 5432 | （默认不暴露） | 数据库 |
| Valkey | share_valkey | 6379 | （默认不暴露） | 缓存 |
| RabbitMQ | share_rabbitmq | 5672 | （不对外暴露） | Firecrawl 作业队列 |

## 访问验证

```bash
curl http://localhost:3001/health
curl http://localhost:4000/health
curl http://localhost:8088/
curl http://localhost:7070/mcp  # 预期 400/403/405 也算“活着”
curl http://localhost:3002/v0/health/liveness
```

## 1Panel 反向代理（示例）

- `api.yourdomain.com` → `http://share_gptload:3001`
- `litellm.yourdomain.com` → `http://share_litellm:4000`
- `search.yourdomain.com` → `http://share_searxng:8080`
- （可选）`crawl.yourdomain.com` → `http://share_firecrawl:3002`
- （可选）`browser.yourdomain.com` → `http://share_playwright:${PLAYWRIGHT_MCP_PORT}`

## 常见提示

- DSN/URL 中会拼接密码（Postgres/Valkey/RabbitMQ）：建议使用 URL-safe 密码（字母数字 + `-_`），或自行做 percent-encode，避免 `@`、`:`、`/` 等字符导致连接串解析失败。
- gpt-load 代理入口：`/proxy/:group_name/*`，例如 `http://api.yourdomain.com/proxy/openai/v1/chat/completions`。

## 性能与稳定性

参考 `PERFORMANCE.md`（单机不拆分、16C/48GB 场景的优化路线图与已落地的 compose 改动）。
