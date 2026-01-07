# share_stacks 网络架构设计（1Panel 集成版）

## 目标

1. **与 1Panel 集成**：接入 1Panel 默认网络 `1panel-network`
2. **服务隔离**：数据库/缓存默认不对外暴露
3. **双入口**：算力 API（gpt-load）+ MCP（LiteLLM）

## 当前默认拓扑（本仓库维护的模式）

本仓库当前仅维护 `docker-compose.yml`：所有服务接入 `1panel-network`（外部网络），便于 1Panel 统一管理与反向代理；数据库类服务默认不暴露宿主机端口（`ports` 已注释）。

```
┌─────────────────────────────────────────────────────────┐
│            1panel-network (外部网络)                      │
│                                                           │
│  ┌───────────────  share_stacks 服务组  ──────────────┐   │
│  │                                                     │   │
│  │  ┌─────────┐        ┌─────────┐                    │   │
│  │  │gpt-load │        │LiteLLM  │                    │   │
│  │  │  :3001  │        │  :4000  │                    │   │
│  │  └────┬────┘        └────┬────┘                    │   │
│  │       │                  │                         │   │
│  │       └───────────┬──────┘                         │   │
│  │                   │                                │   │
│  │            ┌──────▼──────┐   ┌──────────┐          │   │
│  │            │PostgreSQL   │   │ Valkey   │          │   │
│  │            │  :5432      │   │  :6379   │          │   │
│  │            └─────────────┘   └──────────┘          │   │
│  └────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 可选：生产隔离（自定义扩展）

如果你希望把 Postgres/Valkey 放到 `internal: true` 的私有网络中（仅容器内可达），可以在本仓库基础上复制一份 compose 文件并做如下改造（示意）：

```
┌──────────────────────────────────────────────────────────┐
│            1panel-network (public)                         │
│                                                            │
│   ┌─────────────┐          ┌─────────────┐                 │
│   │  gpt-load    │          │   LiteLLM    │                 │
│   │  :3001       │          │   :4000      │                 │
│   └──────┬───────┘          └──────┬───────┘                 │
└──────────┼──────────────────────────┼────────────────────────┘
           │                          │
           │      ┌───────────────────┘
           │      │
┌──────────┼──────┼──────────────────────────────────────────┐
│          │      │        share_internal (internal)          │
│   ┌──────▼──────▼───┐            ┌──────────┐              │
│   │   PostgreSQL     │            │  Valkey  │              │
│   │     :5432        │            │  :6379   │              │
│   └──────────────────┘            └──────────┘              │
└────────────────────────────────────────────────────────────┘
```

## 端口暴露策略

### 默认策略（本仓库当前行为）

- **除数据库类服务外，均发布到宿主机/LAN**：便于直接用局域网 IP 访问
- **数据库类服务不发布端口**：Postgres / Valkey / RabbitMQ 仅供容器内访问（通过容器名互访）

```yaml
services:
  gpt-load:
    ports:
      - "${GPTLOAD_PORT}:3001"
  litellm:
    ports:
      - "${LITELLM_PORT}:4000"
  searxng:
    ports:
      - "${SEARXNG_PORT}:8080"
  playwright:
    ports:
      - "${PLAYWRIGHT_PORT}:${PLAYWRIGHT_MCP_PORT}"
  firecrawl:
    ports:
      - "${FIRECRAWL_PORT}:3002"
```

## 1Panel 反向代理示例

### gpt-load（算力 API 网关）

```nginx
location / {
    proxy_pass http://share_gptload:3001;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_set_header X-Accel-Buffering no;
    chunked_transfer_encoding on;
}
```

### LiteLLM（MCP Hub）

```nginx
location / {
    proxy_pass http://share_litellm:4000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## 服务间通信

| 从服务 | 到服务 | 连接地址 |
|--------|--------|----------|
| gpt-load | postgres | `postgres:5432` |
| gpt-load | valkey | `valkey:6379` |
| litellm | postgres | `postgres:5432` |
| litellm | valkey | `valkey:6379` |
| searxng | valkey（可选） | `valkey:6379` |
| litellm/agent | playwright | `share_playwright:7070`（MCP: `/mcp` 或 `/sse`） |
| firecrawl | postgres | `postgres:5432` |
| firecrawl | valkey | `valkey:6379` |
| firecrawl | rabbitmq | `rabbitmq:5672` |
| firecrawl | searxng | `searxng:8080`（`SEARXNG_ENDPOINT`） |
| firecrawl | firecrawl-playwright | `firecrawl-playwright:3000/scrape` |

> 注意：Playwright MCP 默认有 Host header 校验；本堆栈默认通过 `PLAYWRIGHT_ALLOWED_HOSTS=*` 放开，以便容器间使用容器名访问。

## 端口清单（确保无冲突）

### 容器内端口（固定）

- gpt-load：`3001/tcp`
- LiteLLM：`4000/tcp`
- SearXNG：`8080/tcp`
- Playwright MCP：`7070/tcp`（可配置 `PLAYWRIGHT_MCP_PORT`）
- Firecrawl：`3002/tcp`
- Firecrawl Playwright：`3000/tcp`
- PostgreSQL：`5432/tcp`
- Valkey：`6379/tcp`
- RabbitMQ：`5672/tcp`

### 宿主机端口（仅在暴露 ports 时占用）

- `GPTLOAD_PORT`（默认 `3001`） → `share_gptload:3001`
- `LITELLM_PORT`（默认 `4000`） → `share_litellm:4000`
- `SEARXNG_PORT`（默认 `8088`） → `share_searxng:8080`
- `PLAYWRIGHT_PORT`（默认 `7070`） → `share_playwright:${PLAYWRIGHT_MCP_PORT}`
- `FIRECRAWL_PORT`（默认 `3002`） → `share_firecrawl:3002`
- `POSTGRES_PORT`（默认 `5439`，可选） → `share_postgres:5432`
- `VALKEY_PORT`（默认 `6389`，可选） → `share_valkey:6379`

说明：默认不暴露 `postgres/valkey`，只通过容器网络访问；如果你自建“生产隔离”变体，建议也只通过 1Panel 反向代理暴露必要入口。

## 启动顺序（无循环依赖）

1. `postgres` 启动并通过健康检查（`pg_isready`）
2. `pg_init` 一次性执行：创建 `gptload/litellm` 数据库与用户、启用扩展（成功后退出）
3. `valkey` 启动并通过健康检查（`valkey-cli ping`）
4. `gpt-load` 与 `litellm` 在 `pg_init` 成功且 `valkey` 健康后启动
5. `searxng` 在 `valkey` 健康后启动（默认不强依赖 valkey，避免配置不匹配导致卡死）
6. `playwright` 独立启动（不依赖 DB/Cache），供 MCP/Agent 调用
7. `rabbitmq` 独立启动（内部作业队列）
8. `firecrawl-playwright` 启动（Firecrawl 专用 /scrape 微服务）
9. `firecrawl` 在 `pg_init/valkey/rabbitmq/searxng/firecrawl-playwright` 就绪后启动

依赖方向为单向链路（`postgres → pg_init → {gpt-load, litellm}` 且 `{gpt-load, litellm} → valkey`），不存在循环依赖；若 `pg_init` 失败，会阻止上层服务启动（避免“启动了但无法读写 DB”的半死状态）。

## 算力 API 流动线路（避免死循环）

### 标准路径（推荐）

1. Agent/客户端 →（域名/端口）→ `gpt-load:3001`
2. `gpt-load` →（容器网络）→ `postgres:5432` / `valkey:6379`（鉴权、配置、缓存、限流等）
3. `gpt-load` →（公网）→ 上游算力 API（OpenAI/Anthropic/Gemini/等真实上游）

### 可选路径（当 LiteLLM 也需要走算力 API 时）

Agent/客户端 → `litellm:4000` →（把模型上游 base_url 指向 gpt-load）→ `gpt-load:3001` → 上游算力 API

### 避免回环的配置检查

- 不要把 **gpt-load 分组的上游地址** 配成 `http://share_gptload:3001` 或你的 `api.yourdomain.com`（这会让 gpt-load 代理再次命中自己，形成回环）。
- 不要把 **LiteLLM 的 MCP server URL** 配成 `http://share_litellm:4000` 或你的 `litellm.yourdomain.com`（会回环）。

## 故障排查

```bash
docker exec share_gptload ping postgres -c 3
docker exec share_litellm ping valkey -c 3
docker exec 1panel-nginx curl http://share_gptload:3001/health
```
