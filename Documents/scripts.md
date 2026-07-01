# 脚本说明

## 概述

项目当前主要保留三类脚本：

- 构建与启动脚本
- 日志收集脚本
- 版本管理脚本

它们服务于 SVN 合并助手的日常开发、打包和排障，不再承担通用流程平台相关的扩展职责。

## 脚本文件

### 构建与启动

- macOS/Linux: `scripts/deploy.sh`
- Windows: `scripts/deploy.bat`

主要用途：

- 检查 Flutter 环境
- 同步版本号
- 构建桌面应用
- 启动对应桌面目标

### 日志收集

- macOS/Linux: `scripts/collect_logs.sh`
- Windows: `scripts/collect_logs.bat`

主要用途：

- 收集应用日志文件（包含当前 `latest.log` 和归档 `app_*.log`）
- 收集内置预置配置和用户配置快照
- 收集系统信息，便于排查问题

### 版本管理

- macOS/Linux: `scripts/version.sh`
- Windows: `scripts/version.bat`

主要用途：

- 查询或修改版本号
- 同步版本到 `pubspec.yaml`
- 为发布构建准备版本信息

## 使用方法

### macOS/Linux

```bash
./scripts/deploy.sh
./scripts/collect_logs.sh
./scripts/version.sh get app
```

### Windows

```batch
scripts\deploy.bat
scripts\collect_logs.bat
scripts\version.bat get app
```

PowerShell 下也可直接执行：

```powershell
.\scripts\deploy.bat
.\scripts\collect_logs.bat
.\scripts\version.bat get app
```

## 配置相关说明

- `assets/config/source_urls.json` 是打包进应用的预置配置
- 用户真实运行时配置优先读取用户配置目录中的 `source_urls.json`
- 仓库内的 `config/source_urls.json` 主要作为模板保留
- 即使构建输出目录中附带了模板配置，运行时也仍以用户配置目录为准

## 注意事项

1. Windows 用户如果已经安装 Git Bash 或 WSL，也可以直接使用 `.sh` 脚本。
2. 日志收集脚本会同时抓取预置配置、用户配置以及应用支持目录中的日志，适合问题回溯。
3. 构建脚本面向桌面目标，默认围绕当前这套 SVN 合并助手桌面程序工作。
4. 旧的脚本节点示例、GitHub Actions 实验脚本、CR/工蜂调研脚本、临时实验脚本已经从仓库移除。

## 相关文档

- [配置说明](configuration.md)
- [版本管理](development/version-management.md)

当前脚本只围绕现行的应用支持目录和构建产物名工作。
