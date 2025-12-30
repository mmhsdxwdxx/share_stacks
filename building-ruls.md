下面是一份**“share_stacks：API + MCP 分发堆栈”最终定稿可复现部署文档**（已把我们踩过的坑全部规避、把变量名异同说清楚、按生产思路做了最小安全与可维护性设计）。你可以直接复制到新对话继续迭代优化。

---

# share_stacks 最终定稿部署方案（Docker Compose）

## 目标

在一台内网主机上用 **docker compose** 部署一个统一分发堆栈 **share_stacks**，实现：

* **new-api**：你习惯的 OpenAI 标准 API 转发入口（LAN IP 访问）
* **LiteLLM**：统一的 API 网关 + MCP Hub（对外提供 MCP Streamable HTTP）
* **mcpo**：把 MCP 转成 **OpenAPI Tool Server**（给 OpenWebUI / LobeHub 用）
* **PostgreSQL（pg17 + pgvector）**：两套应用共用同一实例，但各自独立 DB/用户；提前开启向量能力
* **Valkey**：提供缓存/队列/限流等基础能力；用于 new-api 与 LiteLLM 的缓存与性能提升

---

## 0. Checklist（开工前必须确认）

### 端口规划（可改，但先按此）

* `3000` → new-api
* `4000` → litellm
* `8010` → mcpo
* `5439` → postgres（可选暴露）
* `6389` → valkey（可选暴露）

检查端口空闲：

```bash
ss -lntp | egrep ':(3000|4000|8010|5439|6389)\s' || echo "ports look free"
```

### 必备密钥/密码（不要用默认）

* Postgres：`POSTGRES_PASSWORD`
* new-api DB 用户密码：`NEWAPI_DB_PASSWORD`
* LiteLLM DB 用户密码：`LITELLM_DB_PASSWORD`
* Valkey 密码：`VALKEY_PASSWORD`
* new-api：`SESSION_SECRET`、`CRYPTO_SECRET`
* litellm：`LITELLM_MASTER_KEY`、`LITELLM_SALT_KEY`
* mcpo：`MCPO_API_KEY`

> **雷点**：密钥曾在聊天中暴露过，正式部署务必换新；并且不要把 key 贴到公开位置。

---

## 1. 目录结构（推荐）

在你的分发主机上执行（示例路径）：

```bash
mkdir -p /opt/stacks/share_stacks/{litellm,mcpo,postgres-init,newapi-data,logs}
cd /opt/stacks/share_stacks
```

---

## 2. `.env`（统一变量源，避免混乱）

创建 `/opt/stacks/share_stacks/.env`：

```bash
cat > .env <<'EOF'
TZ=Asia/Shanghai

# Ports
NEWAPI_PORT=3000
LITELLM_PORT=4000
MCPO_PORT=8010
POSTGRES_PORT=5439
VALKEY_PORT=6389

# Postgres superuser
POSTGRES_USER=postgres
POSTGRES_PASSWORD=CHANGE_ME_POSTGRES_PASSWORD

# NewAPI DB
NEWAPI_DB_NAME=newapi
NEWAPI_DB_USER=newapi
NEWAPI_DB_PASSWORD=CHANGE_ME_NEWAPI_DB_PASSWORD

# LiteLLM DB
LITELLM_DB_NAME=litellm
LITELLM_DB_USER=litellm
LITELLM_DB_PASSWORD=CHANGE_ME_LITELLM_DB_PASSWORD

# Valkey
VALKEY_PASSWORD=CHANGE_ME_VALKEY_PASSWORD

# new-api secrets (prod recommended)
NEWAPI_SESSION_SECRET=CHANGE_ME_SESSION_SECRET
NEWAPI_CRYPTO_SECRET=CHANGE_ME_CRYPTO_SECRET

# LiteLLM keys (must start with sk-)
LITELLM_MASTER_KEY=sk-CHANGE_ME_LITELLM_MASTER
LITELLM_SALT_KEY=sk-CHANGE_ME_LITELLM_SALT

# mcpo key (OpenWebUI/LobeHub calls mcpo)
MCPO_API_KEY=sk-CHANGE_ME_MCPO_KEY
EOF
```

---

## 3. Postgres 初始化（自动建库/用户 + 启用扩展）

### 3.1 `postgres-init/01-create-dbs.sql`

> **雷点规避**：不要手动进库创建，交给 init 脚本，重装可复现。

```bash
cat > postgres-init/01-create-dbs.sql <<'EOF'
-- create databases and users using environment variables substituted by docker-entrypoint
-- NOTE: docker-entrypoint-initdb.d does not expand ${VAR} by itself. We therefore create
-- separate init that uses psql with envsubst via docker compose (see compose section).
EOF
```

> ✅ 重要说明：Postgres 官方 entrypoint **不会自动替换 SQL 文件里的 `${VAR}`**。
> 所以我们不用“SQL 里写变量”的方式，而是采用 **docker compose 里用一次性 init 容器生成 SQL**（见第 6 节），彻底避免“变量不展开导致脚本没生效”的坑。

### 3.2 扩展 SQL（固定，不需要变量）

`postgres-init/02-enable-extensions.sql`：

```bash
cat > postgres-init/02-enable-extensions.sql <<'EOF'
-- This file will be applied AFTER db creation (by init job).
-- It enables extensions in each app database.

\connect newapi
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\connect litellm
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF
```

---

## 4. LiteLLM 配置（`litellm/config.yaml`）

> **雷点规避**：
>
> * `Accept: application/json` 是 MCP/HTTP 客户端常见坑（你之前遇到 406）。
> * LiteLLM 缓存用 Redis host/port/password（Valkey 兼容）。
> * deepwiki 是公网 MCP，上游 URL 写公网是正常的（Hub 在内网）。

```bash
cat > litellm/config.yaml <<'EOF'
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: os.environ/REDIS_HOST
    port: os.environ/REDIS_PORT
    password: os.environ/REDIS_PASSWORD

mcp_servers:
  deepwiki_mcp:
    url: "https://mcp.deepwiki.com/mcp"
EOF
```

---

## 5. mcpo 配置（一个容器托管 N 个 MCP，不要建 10 个容器）

`mcpo/config.json`（先只配 deepwiki，后续你加 10 个 MCP 就继续往 `mcpServers` 里加）：

```bash
cat > mcpo/config.json <<'EOF'
{
  "mcpServers": {
    "deepwiki": {
      "type": "streamable-http",
      "url": "http://litellm:4000/deepwiki_mcp/mcp",
      "headers": {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "x-litellm-api-key": "Bearer sk-CHANGE_ME_LITELLM_MCP_KEY"
      }
    }
  }
}
EOF
```

### ✅ 关键雷点：mcpo→LiteLLM 不要用 master key

* 不要把 `LITELLM_MASTER_KEY` 写进 mcpo 的 config（权限过大）
* 正确做法：LiteLLM UI 里创建一个 **Virtual Key**（只给 MCP 用），把它填到 `x-litellm-api-key` 里
* 这个 key 记为：`LITELLM_MCP_VKEY`

> **你现在先把文件里的占位符改成你新建的 vkey**，这是最重要的安全改动。

---

## 6. docker-compose.yml（最终堆栈）

> **雷点规避清单：**
>
> 1. Postgres 的“变量 SQL 不展开”用 init job 解决（一次性容器跑 psql）。
> 2. mcpo 不做模板替换，避免 compose 的 `$` 插值坑（你之前踩过）。
> 3. 依赖顺序：db/valkey healthcheck → new-api/litellm。
> 4. 只跑一个 mcpo。
> 5. 可选暴露 DB/Redis：默认保留端口映射，便于你调试；上生产可注释 ports。

创建 `/opt/stacks/share_stacks/docker-compose.yml`：

```bash
cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  postgres:
    image: pgvector/pgvector:pg17
    container_name: share_postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      TZ: ${TZ}
    volumes:
      - share_pg_data:/var/lib/postgresql/data
      - ./postgres-init:/init:ro
    ports:
      - "${POSTGRES_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      timeout: 5s
      retries: 30

  # one-shot init job to create db/users and enable extensions (env-safe)
  pg_init:
    image: pgvector/pgvector:pg17
    container_name: share_pg_init
    depends_on:
      postgres:
        condition: service_healthy
    restart: "no"
    env_file: .env
    volumes:
      - ./postgres-init:/init:ro
    entrypoint: ["/bin/sh", "-lc"]
    command: >
      psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/postgres" -v ON_ERROR_STOP=1 <<SQL
      DO \$\$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${NEWAPI_DB_USER}') THEN
          EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${NEWAPI_DB_USER}', '${NEWAPI_DB_PASSWORD}');
        END IF;
        IF NOT EXISTS (SELECT FROM pg_database WHERE datname='${NEWAPI_DB_NAME}') THEN
          EXECUTE format('CREATE DATABASE %I OWNER %I', '${NEWAPI_DB_NAME}', '${NEWAPI_DB_USER}');
        END IF;

        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${LITELLM_DB_USER}') THEN
          EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${LITELLM_DB_USER}', '${LITELLM_DB_PASSWORD}');
        END IF;
        IF NOT EXISTS (SELECT FROM pg_database WHERE datname='${LITELLM_DB_NAME}') THEN
          EXECUTE format('CREATE DATABASE %I OWNER %I', '${LITELLM_DB_NAME}', '${LITELLM_DB_USER}');
        END IF;
      END
      \$\$;
SQL
      && psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/postgres" -v ON_ERROR_STOP=1 -f /init/02-enable-extensions.sql

  valkey:
    image: valkey/valkey:7.2-alpine
    container_name: share_valkey
    restart: always
    command: ["valkey-server", "--appendonly", "yes", "--requirepass", "${VALKEY_PASSWORD}"]
    ports:
      - "${VALKEY_PORT}:6379"
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli -a ${VALKEY_PASSWORD} ping | grep PONG"]
      interval: 5s
      timeout: 5s
      retries: 30

  new-api:
    image: calciumion/new-api:latest
    container_name: share_newapi
    restart: always
    depends_on:
      pg_init:
        condition: service_completed_successfully
      valkey:
        condition: service_healthy
    ports:
      - "${NEWAPI_PORT}:3000"
    volumes:
      - ./newapi-data:/data
      - ./logs/newapi:/app/logs
    environment:
      TZ: ${TZ}

      # new-api official env names
      SQL_DSN: "postgresql://${NEWAPI_DB_USER}:${NEWAPI_DB_PASSWORD}@postgres:5432/${NEWAPI_DB_NAME}"
      REDIS_CONN_STRING: "redis://default:${VALKEY_PASSWORD}@valkey:6379"

      SESSION_SECRET: ${NEWAPI_SESSION_SECRET}
      CRYPTO_SECRET: ${NEWAPI_CRYPTO_SECRET}

      ERROR_LOG_ENABLED: "true"
      MEMORY_CACHE_ENABLED: "true"
      STREAMING_TIMEOUT: "300"

  litellm:
    image: docker.litellm.ai/berriai/litellm:main-stable
    container_name: share_litellm
    restart: always
    depends_on:
      pg_init:
        condition: service_completed_successfully
      valkey:
        condition: service_healthy
    ports:
      - "${LITELLM_PORT}:4000"
    volumes:
      - ./litellm/config.yaml:/app/config.yaml:ro
      - ./logs/litellm:/var/log/litellm
    environment:
      TZ: ${TZ}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: "postgresql://${LITELLM_DB_USER}:${LITELLM_DB_PASSWORD}@postgres:5432/${LITELLM_DB_NAME}"

      REDIS_HOST: valkey
      REDIS_PORT: "6379"
      REDIS_PASSWORD: ${VALKEY_PASSWORD}
    command: ["--config", "/app/config.yaml", "--port", "4000", "--run_gunicorn"]

  mcpo:
    image: ghcr.io/open-webui/mcpo:main
    container_name: share_mcpo
    restart: always
    depends_on:
      litellm:
        condition: service_started
    ports:
      - "${MCPO_PORT}:8000"
    volumes:
      - ./mcpo/config.json:/config/config.json:ro
    command: ["--host","0.0.0.0","--port","8000","--api-key","${MCPO_API_KEY}","--config","/config/config.json"]

volumes:
  share_pg_data:
EOF
```

---

## 7. 启动顺序（严格按这个来，避免“半初始化”）

```bash
cd /opt/stacks/share_stacks
docker compose up -d
docker compose ps
```

重点观察：

* `share_pg_init` 必须 **exit 0**（完成一次性初始化）
* `share_postgres`、`share_valkey` 必须健康
* `share_newapi`、`share_litellm`、`share_mcpo` Up

---

## 8. 验收（必须做到这四项）

### 8.1 LiteLLM UI

打开：

* `http://<LAN_IP>:4000/ui`
  用 master key/账号体系配置（你之前已会用）。

### 8.2 mcpo OpenAPI

```bash
curl -sS -H "Authorization: Bearer ${MCPO_API_KEY}" \
  "http://127.0.0.1:8010/deepwiki/openapi.json" | head -c 300; echo
```

应返回 openapi JSON。

### 8.3 new-api OpenAI API

```bash
curl -sS "http://127.0.0.1:3000/v1/models" -H "Authorization: Bearer <你的newapi token>" | head
```

### 8.4 OpenWebUI 接入（LAN IP）

* 模型：Base URL `http://<LAN_IP>:3000/v1`
* 工具（OpenAPI Tool Server）：
  URL `http://<LAN_IP>:8010/deepwiki`
  Spec `openapi.json`
  Auth Bearer = `MCPO_API_KEY`

测试问题（强制工具调用）：

> “请使用 deepwiki 工具查询 BerriAI/litellm 的文档结构并总结 MCP Gateway 的配置要点。”

---

## 9. 已排除/规避的雷点（带去新对话非常关键）

1. **Compose 的 `$` 插值坑**：不在 compose `command` 里写 `${%s}`/复杂替换；mcpo 配置不使用模板渲染（你之前踩过）。
2. **Postgres init SQL 变量不展开**：不用 `${VAR}` 写进 `.sql` 让 entrypoint 替换；改用一次性 `pg_init` job 直接读 `.env` 并执行 SQL（最稳）。
3. **MCP 406 Not Acceptable**：mcpo → LiteLLM 的 headers 固定 `Accept: application/json`。
4. **mcpo 多 MCP 扩展**：只跑 1 个 mcpo 容器；`mcpServers` 里追加即可。
5. **Key 权限隔离**：mcpo 调 LiteLLM MCP 用 **Virtual Key**，不要用 LiteLLM master key（避免过权）。
6. **速度变慢**：OpenWebUI→mcpo→litellm→上游 MCP 多 hop 正常；后续靠缓存/并发策略优化。

---

## 10. 你下一步优化方向（带到新对话的 TODO）

* 为 mcpo 专门创建 LiteLLM Virtual Key，并替换 `mcpo/config.json` 的 `x-litellm-api-key`
* 将更多 MCP 加入 `mcpo/config.json`（保持单容器）
* LiteLLM 的 cache 策略：TTL、对哪些请求缓存、以及 OpenWebUI 工具调用并发/超时策略
* 如果要把 new-api “算力 API”更深地纳入 LiteLLM 做统一网关：在 LiteLLM `model_list` 里将上游指向 `http://new-api:3000/v1` 并做路由/限流

---

如果你把这份文档带到新对话里，下一步你只要说：“我们开始做 **Virtual Key 权限隔离 + 多 MCP 扩展 + 性能优化（缓存/并发/超时）**”，我就能直接在这个基础上继续往下推进。
