# share_stacks: API + MCP 分发堆栈

[English](#english) | [简体中文](#中文)

---

## 中文

一个统一的分发堆栈，集成了 new-api、LiteLLM、mcpo、PostgreSQL 和 Valkey，用于内网部署的 AI 服务基础设施。

### 特性

- ✅ **STO MCP 支持**：完整支持 Stdio、SSE、Streamable HTTP 三种传输方式
- ✅ **自定义构建**：使用自定义构建的 LiteLLM 镜像，版本固定为 v1.50.0
- ✅ **资源优化**：针对 8 核 16GB 服务器优化，支持 10 个并发用户
- ✅ **健康检查**：所有服务配置健康检查和自动重启
- ✅ **内网隔离**：专用 Docker 桥接网络，服务间通过容器名通信

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                         share_stacks                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │ new-api  │    │ LiteLLM  │    │  mcpo    │               │
│  │  :3000   │    │  :4000   │    │  :8010   │               │
│  └──────────┘    └──────────┘    └──────────┘               │
│       │                │                 │                   │
│       └────────────────┼─────────────────┘                   │
│                        │                                     │
│              ┌─────────┴─────────┐                           │
│              │  PostgreSQL (pg17)│                           │
│              │  + pgvector       │                           │
│              │       :5439       │                           │
│              └───────────────────┘                           │
│                        │                                     │
│              ┌─────────┴─────────┐                           │
│              │     Valkey        │                           │
│              │      :6389        │                           │
│              └───────────────────┘                           │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## 组件说明

- **new-api** (端口 3000): OpenAI 标准 API 转发入口
- **LiteLLM** (端口 4000): 统一的 API 网关 + MCP Hub
- **mcpo** (端口 8010): 将 MCP 转换为 OpenAPI Tool Server
- **PostgreSQL** (端口 5439): pg17 + pgvector，共享数据库实例
- **Valkey** (端口 6389): Redis 兼容的缓存/队列服务

## 快速开始

### 前置要求

- Docker 和 Docker Compose
- Linux/macOS 或 Windows (WSL2 推荐)

### 1. 初始化目录结构

**Linux/macOS (Ubuntu 部署环境):**
```bash
bash scripts/init.sh
```

**Windows PowerShell (仅开发环境):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/init.ps1
```

### 2. 配置环境变量

编辑 `.env` 文件，修改所有密码和密钥：

```bash
# 重要：修改所有 CHANGE_ME_* 为强密码
POSTGRES_PASSWORD=your_secure_password
NEWAPI_DB_PASSWORD=your_newapi_password
LITELLM_DB_PASSWORD=your_litellm_password
VALKEY_PASSWORD=your_valkey_password
NEWAPI_SESSION_SECRET=your_session_secret
NEWAPI_CRYPTO_SECRET=your_crypto_secret
LITELLM_MASTER_KEY=sk-your-master-key
LITELLM_SALT_KEY=sk-your-salt-key
MCPO_API_KEY=sk-your-mcpo-key
```

### 3. 启动服务

```bash
docker compose up -d
```

查看启动状态：
```bash
docker compose ps
```

### 4. 验证部署

**Linux/macOS (Ubuntu 部署环境):**
```bash
bash scripts/verify.sh
```

**Windows PowerShell (仅开发环境):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```

## 配置说明

### LiteLLM Virtual Key（重要安全配置）

mcpo 调用 LiteLLM MCP 时应使用专用 Virtual Key，而非 Master Key：

1. 访问 `http://<LAN_IP>:4000/ui`
2. 创建一个新的 Virtual Key（记为 `LITELLM_MCP_VKEY`）
3. 更新 [mcpo/config.json](mcpo/config.json) 中的 `x-litellm-api-key`
4. 重启 mcpo：
   ```bash
   docker compose restart mcpo
   ```

### 添加更多 MCP Server

编辑 [mcpo/config.json](mcpo/config.json)，在 `mcpServers` 中添加：

```json
{
  "mcpServers": {
    "deepwiki": {
      "type": "streamable-http",
      "url": "http://litellm:4000/deepwiki_mcp/mcp",
      "headers": {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "x-litellm-api-key": "Bearer sk-your-vkey"
      }
    },
    "another_mcp": {
      "type": "streamable-http",
      "url": "http://litellm:4000/another_mcp/mcp",
      "headers": {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "x-litellm-api-key": "Bearer sk-your-vkey"
      }
    }
  }
}
```

重启 mcpo 使配置生效。

## 访问地址

| 服务 | URL | 说明 |
|------|-----|------|
| new-api | `http://<LAN_IP>:3000` | OpenAI 兼容 API |
| LiteLLM UI | `http://<LAN_IP>:4000/ui` | LiteLLM 管理界面 |
| mcpo | `http://<LAN_IP>:8010` | OpenAPI Tool Server |

## OpenWebUI 接入

### 模型配置

- Base URL: `http://<LAN_IP>:3000/v1`
- API Key: 你的 new-api token

### 工具配置（OpenAPI Tool Server）

- URL: `http://<LAN_IP>:8010/deepwiki`
- Spec: `openapi.json`
- Auth Bearer: `MCPO_API_KEY` 的值

## 常见问题

### 端口冲突

修改 [.env](.env) 中的端口配置：

```bash
NEWAPI_PORT=3001
LITELLM_PORT=4001
MCPO_PORT=8011
```

### 数据库初始化失败

检查 `share_pg_init` 容器日志：

```bash
docker compose logs pg_init
```

### MCP 406 错误

确保 [mcpo/config.json](mcpo/config.json) 中包含正确的 headers：

```json
"headers": {
  "Accept": "application/json",
  "Content-Type": "application/json"
}
```

## 维护命令

```bash
# 查看日志
docker compose logs -f [service_name]

# 重启服务
docker compose restart [service_name]

# 停止所有服务
docker compose down

# 完全清理（包括数据卷）
docker compose down -v

# 更新服务
docker compose pull
docker compose up -d
```

## 目录结构

```
share_stacks/
├── docker-compose.yml          # 主配置文件
├── Dockerfile.litellm          # LiteLLM 自定义构建文件
├── .env                        # 环境变量（需手动配置）
├── .env.example               # 环境变量模板
├── scripts/                   # 自动化脚本目录
│   ├── init.sh               # Linux/Ubuntu 初始化脚本
│   ├── verify.sh             # Linux/Ubuntu 验证脚本
│   ├── init.ps1              # Windows 初始化脚本（仅开发环境）
│   └── verify.ps1            # Windows 验证脚本（仅开发环境）
├── README.md                  # 本文件
├── 新手配置指南.md              # 新手详细配置指南
├── 构建规范.md                 # 构建规范文档
├── 部署指南.md                 # Ubuntu 部署指南
├── 网络配置.md                 # 网络配置说明
├── litellm/
│   └── config.yaml            # LiteLLM 配置
├── mcpo/
│   └── config.json            # mcpo 配置
├── postgres-init/
│   ├── 01-create-dbs.sql
│   ├── 02-enable-extensions.sql
│   └── 03-performance-tuning.conf
├── newapi-data/               # new-api 数据目录
└── logs/                      # 日志目录
    ├── newapi/
    └── litellm/
```

## 安全建议

1. **修改所有默认密码**：不要使用 `.env.example` 中的占位符
2. **使用 Virtual Key**：mcpo → LiteLLM 使用专用 Virtual Key，而非 Master Key
3. **限制端口暴露**：生产环境注释掉 docker-compose.yml 中 PostgreSQL 和 Valkey 的端口映射
4. **定期备份**：备份 `newapi-data` 和 PostgreSQL 数据卷
5. **日志监控**：定期检查 `logs/` 目录

## 许可证

本项目配置文件遵循 MIT 许可证。

## 参考资料

- [new-api 文档](https://github.com/Calcium-Ion/new-API)
- [LiteLLM 文档](https://docs.litellm.ai/)
- [mcpo 文档](https://github.com/open-webui/mcpo)
- 详细配置文档：参见 [新手配置指南.md](新手配置指南.md)
- 部署指南：参见 [部署指南.md](部署指南.md)
- 网络配置：参见 [网络配置.md](网络配置.md)

---

## English

A unified distribution stack integrating new-api, LiteLLM, mcpo, PostgreSQL, and Valkey for on-premise AI service infrastructure.

### Features

- ✅ **STO MCP Support**: Full support for Stdio, SSE, and Streamable HTTP transports
- ✅ **Custom Build**: Uses custom-built LiteLLM image, pinned at version v1.50.0
- ✅ **Resource Optimized**: Optimized for 8-core 16GB servers, supporting 10 concurrent users
- ✅ **Health Checks**: All services configured with health checks and auto-restart
- ✅ **Network Isolation**: Dedicated Docker bridge network with inter-service communication via container names

For detailed documentation in English, please refer to the Chinese documentation sections above or use translation tools.
