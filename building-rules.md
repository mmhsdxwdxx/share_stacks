# share_stacks 部署要点（精简版）

本文件记录 share_stacks 在 Docker Compose + 1Panel 场景下的关键部署要点与踩坑规避。

## 组件

- **API 网关**：`gpt-load`（OpenAI/Gemini/Anthropic 透明代理）
- **LiteLLM**：统一 API 网关能力 + MCP Hub
- **PostgreSQL（pg17 + pgvector）**：为网关/LiteLLM 提供持久化
- **Valkey**：Redis 兼容缓存/队列/限流能力

## 端口规划（默认）

- `3001` → API 网关（gpt-load）
- `4000` → LiteLLM
- `5439` → postgres（可选暴露，仅调试）
- `6389` → valkey（可选暴露，仅调试）

## 8C/32GB + 2000rpm/30rpm 建议

- `.env`: `POSTGRES_MAX_CONNECTIONS=800`（gpt-load 内置连接池上限较高，避免触顶）
- `.env`: `POSTGRES_SHARED_BUFFERS=4GB`，`POSTGRES_EFFECTIVE_CACHE_SIZE=12GB`，`POSTGRES_WORK_MEM=2MB`
- `.env`: `VALKEY_MAXMEMORY=4gb`
- `.env`: `GPTLOAD_MAX_CONCURRENT_REQUESTS=400`

## 关键雷点（已在仓库配置中规避/修复）

1. **Postgres 初始化脚本变量展开**：不要依赖 Postgres entrypoint 自动替换 SQL 文件变量；使用一次性 `pg_init` 任务显式建库/建用户、再执行扩展脚本。
2. **密码/特殊字符兼容**：不要把密码直接内联进 SQL 字面量；应通过 psql 变量并使用 `:'var'`（SQL literal）/`:var`（raw）来避免引号/`$` 等字符带来的解析问题。
3. **DSN/URL 中的密码字符**：本堆栈会在容器内拼接 `postgresql://user:password@...` / `redis://:password@...` / `amqp://user:password@...`，建议使用 URL-safe 密码（字母数字 + `-_`），或自行 percent-encode，避免 `@`、`:`、`/` 等字符导致解析失败。
4. **网络隔离（可选扩展）**：本仓库当前仅维护 `docker-compose.yml`（统一接入 `1panel-network`）。如需生产隔离，可自行复制 compose 文件，把数据库/缓存放入 `internal: true` 的私有网络并取消宿主机端口映射。

## 验收建议

```bash
docker compose ps
curl http://localhost:4000/health
curl http://localhost:3001/health
```
