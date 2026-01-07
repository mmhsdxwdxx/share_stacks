# share_stacks 在 1Panel 中的部署指南

## 网络方案选择

统一使用单一网络方案：全部服务接入 `1panel-network`，容器间通过容器名互访。

## 部署前准备

### 1) 清理旧堆栈（如果存在）

```bash
docker compose down -v --remove-orphans
```

### 2) 确认 `1panel-network` 存在

```bash
docker network ls | grep 1panel
docker network create 1panel-network
```

### 3) 修改环境变量

优先从模板生成 `.env`（避免把真实密钥误提交到仓库）：

```bash
cp .env.example .env
vim .env  # 替换所有 CHANGE_ME
```

必须设置（至少）：

- `POSTGRES_PASSWORD` / `GPTLOAD_DB_PASSWORD` / `LITELLM_DB_PASSWORD` / `VALKEY_PASSWORD`
- `GPTLOAD_AUTH_KEY`（gpt-load 管理端登录必需，强随机）
- `LITELLM_MASTER_KEY` / `LITELLM_SALT_KEY`（LiteLLM API 鉴权/盐值）
- `SEARXNG_SECRET`（SearXNG 实例签名，强随机）
- （建议）`GPTLOAD_ENCRYPTION_KEY`（gpt-load 静态加密，按需启用）
- （可选）`FIRECRAWL_DB_PASSWORD` / `FIRECRAWL_BULL_AUTH_KEY` / `FIRECRAWL_RABBITMQ_PASSWORD`（启用 Firecrawl 时）
- （可选）`PLAYWRIGHT_IMAGE` / `PLAYWRIGHT_MCP_PORT`（Playwright 浏览器 MCP）

> 注意：Postgres/Valkey/RabbitMQ 的连接串会在容器里按 URL 形式拼接密码（如 `postgresql://user:password@...`）。
> 推荐使用 URL-safe 密码（字母数字 + `-_`），或自行 percent-encode，避免 `@`、`:`、`/` 等字符导致解析失败。

## 部署步骤

### 方式一：命令行部署（推荐）

```bash
docker compose up -d
```

## 反向代理设置

在 1Panel 中创建网站（反向代理）：

### gpt-load

- 域名：`api.yourdomain.com`
- 代理地址：`http://share_gptload:3001`

### LiteLLM

- 域名：`litellm.yourdomain.com`
- 代理地址：`http://share_litellm:4000`

### SearXNG

- 域名：`search.yourdomain.com`
- 代理地址：`http://share_searxng:8080`

### Playwright（可选）

建议默认不对外暴露，仅容器内通过 `share_playwright:7070/mcp` 调用。

### Firecrawl（可选）

- 域名：`crawl.yourdomain.com`
- 代理地址：`http://share_firecrawl:3002`

### 验证

```bash
curl https://api.yourdomain.com/health
curl https://litellm.yourdomain.com/health
curl https://search.yourdomain.com/
curl https://crawl.yourdomain.com/v0/health/liveness
```

## 端口映射对照表（开发模式）

| 服务 | 容器端口 | 宿主机端口 | 说明 |
|------|----------|------------|------|
| gpt-load | 3001 | `${GPTLOAD_PORT}` | 算力 API 透明代理 |
| LiteLLM | 4000 | `${LITELLM_PORT}` | MCP Hub |
| SearXNG | 8080 | `${SEARXNG_PORT}` | 元搜索 |
| Playwright | 7070 | `${PLAYWRIGHT_PORT}` | Browser MCP Server（可选） |
| Firecrawl | 3002 | `${FIRECRAWL_PORT}` | 爬取/抽取服务（可选） |
| PostgreSQL | 5432 | `${POSTGRES_PORT}`（可选） | 数据库 |
| Valkey | 6379 | `${VALKEY_PORT}`（可选） | 缓存 |

当前默认已发布所有非数据库类服务端口，可直接通过 LAN IP 访问；数据库类服务（Postgres/Valkey/RabbitMQ）默认不发布端口（需要调试时再在 `docker-compose.yml` 中取消注释）。

## 常见问题

### Q1: 反向代理 502

确认 1Panel 的 Nginx/Traefik 容器与业务容器在同一网络：

```bash
docker network inspect 1panel-network
```

### Q2: pg_init 一直失败

```bash
docker logs share_pg_init
```

常见原因：

- 密码包含 `@`/`:`/`/` 等 URL 保留字符，导致 DSN 解析失败（优先改为 URL-safe 或 percent-encode）
- Postgres 未通过健康检查（先看 `docker compose ps` / `docker logs share_postgres`）
- `.env` 缺项或拼写错误（建议对照 `.env.example`）
