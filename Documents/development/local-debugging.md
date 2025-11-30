---
title: 本地调试 GitHub Actions
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# 本地调试 GitHub Actions

## 概述

使用 `nektos/act` 工具可以在本地运行和调试 GitHub Actions 工作流，无需每次修改后都推送到 GitHub。这大大提高了调试效率。

## 前置要求

### 1. 安装 Docker Desktop

`act` 工具依赖 Docker 来模拟 GitHub Actions 的运行环境。

**Windows:**
1. 下载 Docker Desktop: https://www.docker.com/products/docker-desktop
2. 安装并启动 Docker Desktop
3. 等待 Docker 完全启动（系统托盘图标显示为运行状态）

**验证安装:**
```powershell
docker --version
docker ps
```

### 2. 安装 act 工具

**使用 Scoop (Windows):**
```powershell
scoop install act
```

**使用安装脚本:**
```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_act.ps1
```

**验证安装:**
```powershell
act --version
```

## 使用方法

### 列出可用的工作流和作业

```powershell
act -l
```

这会显示所有可用的工作流、作业和触发事件。

### 运行整个工作流

```powershell
# 使用默认事件 (push)
act

# 使用特定事件
act workflow_dispatch

# 指定工作流文件
act -W .github/workflows/build.yml
```

### 运行特定作业

```powershell
# 运行 macOS 构建作业
act -W .github/workflows/build.yml -j build-macos

# 运行 Windows 构建作业
act -W .github/workflows/build.yml -j build-windows
```

### 使用测试脚本

项目提供了便捷的测试脚本：

```powershell
# 测试整个工作流
powershell -ExecutionPolicy Bypass -File scripts\test_workflow_local.ps1 .github/workflows/build.yml

# 测试特定作业
powershell -ExecutionPolicy Bypass -File scripts\test_workflow_local.ps1 .github/workflows/build.yml "build-macos"
```

## 注意事项

### 限制

1. **平台特定运行器:** `act` 主要支持 Linux 运行器。macOS 和 Windows 运行器需要特殊配置，可能无法完全模拟。

2. **GitHub Actions 功能:** 某些 GitHub Actions 功能可能不完全支持：
   - Secrets（需要手动配置）
   - 某些第三方 Actions
   - 某些 GitHub API 功能

3. **首次运行:** 首次运行时会提示选择 Docker 镜像大小，建议选择 `Medium`。

### 配置 Secrets

如果需要使用 secrets，可以创建 `.secrets` 文件（不要提交到版本控制）：

```bash
# .secrets
GITHUB_TOKEN=your_token_here
```

然后在运行 act 时指定：

```powershell
act --secret-file .secrets
```

### 调试技巧

1. **使用详细模式:** 添加 `--verbose` 参数查看详细输出
   ```powershell
   act -W .github/workflows/build.yml --verbose
   ```

2. **只运行特定步骤:** 使用 `-s` 参数跳过某些步骤
   ```powershell
   act -W .github/workflows/build.yml -s
   ```

3. **使用本地 Actions:** 如果工作流使用了本地 Actions，确保路径正确

## 优势

- ✅ **快速反馈:** 无需等待 GitHub Actions 运行
- ✅ **快速迭代:** 可以快速测试和修复问题
- ✅ **节省配额:** 不消耗 GitHub Actions 分钟数
- ✅ **离线工作:** 可以在没有网络的情况下测试基本功能
- ✅ **成本效益:** 本地运行不产生任何费用

## 故障排除

### Docker 未运行

**错误信息:**
```
Couldn't get a valid docker connection: no DOCKER_HOST and an invalid container socket
```

**解决方法:**
1. 确保 Docker Desktop 已安装并运行
2. 等待 Docker 完全启动
3. 验证: `docker ps`

### 作业失败

如果作业在本地失败但在 GitHub 上成功，可能是：
1. 平台差异（macOS/Windows 运行器）
2. 缺少必要的 secrets
3. 某些 Actions 不支持本地运行

### 性能问题

- 首次运行会下载 Docker 镜像，可能需要一些时间
- 建议使用 `Medium` 镜像大小以平衡功能和性能

## 相关资源

- [act 官方文档](https://github.com/nektos/act)
- [act GitHub 仓库](https://github.com/nektos/act)
- [Docker Desktop 下载](https://www.docker.com/products/docker-desktop)





