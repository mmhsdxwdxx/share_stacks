# 性能与稳定性优化路线图（16C / 48GB，单机不拆分）

场景假设：每次用户提问会触发多次 SearXNG 查询 + 多网页抓取（Playwright/Firecrawl）+ gpt-load 长时间流式输出；并发用户 6–10 人高强度使用。

## 核心结论（以体验为中心）

单机不拆分时，**最容易拖垮体验的不是 LLM，而是“检索 + 浏览器渲染/爬取”的并发与重试放大**。优化目标应是：快速失败、强限流、充分缓存、避免 OOM、避免队列/连接风暴。

## 路线图（按优先级逐步推进）

### 第 0 步：先把系统“压不死”

已在 `docker-compose.yml` 落地：

- 日志轮转（避免磁盘被打满）：json-file `max-size=10m`/`max-file=3`
- 关键服务资源上限（避免单点抢光内存/CPU 导致整体雪崩）：`mem_limit`/`cpus`/`pids_limit`
- `init: true`（避免子进程僵尸，提升长跑稳定性）
- Valkey AOF 写入优化（降低 fsync 卡顿尖刺）
- Playwright/FW Playwright `shm_size` 提升到 `4gb`（减少 Chromium 共享内存崩溃）

验证：

```bash
docker compose config
docker compose up -d
docker compose ps
```

### 第 1 步：给“抓取/渲染”做硬限流（体验最敏感）

在 `.env`（参考 `.env.example` 的 16C/48GB 默认值）优先调整：

- Firecrawl：`NUM_WORKERS_PER_QUEUE`、`CRAWL_CONCURRENT_REQUESTS`、`MAX_CONCURRENT_JOBS`、`BROWSER_POOL_SIZE`
- Firecrawl Playwright：`FIRECRAWL_PW_MAX_CONCURRENT_PAGES`、超时（`*_TIMEOUT_MS`）、`BLOCK_MEDIA=true`
- Playwright MCP：超时（`PLAYWRIGHT_TIMEOUT_*`）、`BLOCK_SERVICE_WORKERS=true`

目标：高峰时延迟可控、失败可预期（少重试、少堆积），不要把机器打满。

### 第 2 步：缓存与去重（把“几十页”变成“少量增量”）

实施思路（在你的 Agent 侧做最有效）：

- 搜索结果缓存（query + engines + categories → TTL），避免同一问题重复打搜索引擎
- URL 规范化/去重（去 tracking 参数、同页合并）
- 抓取结果缓存（URL + 策略 hash → TTL），优先复用上次渲染/抽取结果

目标：降低平均耗时与波动，减少外部搜索限流概率。

### 第 3 步：观测与告警（稳定性靠“提前发现”）

最小观测集合（不依赖反代）：

- Firecrawl：liveness、任务堆积/失败率、平均抓取耗时
- Playwright：容器 RSS、打开页面数、失败率
- Valkey：内存占用、AOF rewrite 时间
- Postgres：活跃连接数、慢查询（`pg_stat_statements`）、磁盘 IO wait
- gpt-load：并发数、请求耗时、流式断开率（客户端侧可统计）

### 第 4 步：DB 连接与写入优化（防止长跑退化）

当你观察到 Postgres 连接数或锁等待异常时，再做：

- 降低不必要的最大连接、提升慢查询治理
- 需要时再引入连接池（如 PgBouncer）——仍可在同一 compose 内，不算“拆分”

## 推荐落地方式

1) 用 `.env.example` 覆盖式对照更新你的 `.env`（不要提交真实密钥）
2) 每次只改一组参数（抓取并发 / 超时 / 资源上限），在固定压测脚本下对比 P95 延迟与失败率
3) 以“失败快、少重试、少堆积”为准则做迭代
