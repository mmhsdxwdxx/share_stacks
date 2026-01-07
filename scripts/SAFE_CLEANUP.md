# 安全清理（杜绝误删除）

目标：只做“可回滚”的清理 —— 通过 **移动到 `.trash/`** 完成，不执行 `rm`/永久删除。

## 1) 预览（默认）

```powershell
pwsh ./scripts/safe_cleanup.ps1
```

默认会扫描常见的缓存/构建产物（如 `node_modules/`、`__pycache__/`、`*.log` 等），输出候选清单，但 **不会移动任何文件**。

## 2) 执行清理（移动到 .trash）

```powershell
pwsh ./scripts/safe_cleanup.ps1 -Apply
```

会把候选项移动到 `.trash/<时间戳>/...`，保留相对路径，方便随时找回。

## 3) 可选：把旧 new-api 数据也加入候选（仍然是移动，不是删除）

```powershell
pwsh ./scripts/safe_cleanup.ps1 -IncludeLegacyData
pwsh ./scripts/safe_cleanup.ps1 -IncludeLegacyData -Apply
```

## 4) 仅扫描指定目录（例如只清理 gpt-load）

```powershell
pwsh ./scripts/safe_cleanup.ps1 -Roots @("gpt-load")
pwsh ./scripts/safe_cleanup.ps1 -Roots @("gpt-load") -Apply
```

例如只清理新增的大仓库（如 `firecrawl` / `playwright` / `searxng`）：

```powershell
pwsh ./scripts/safe_cleanup.ps1 -Roots @("firecrawl","playwright","searxng") -Apply
```
