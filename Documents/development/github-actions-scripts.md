# GitHub Actions 脚本使用文档

## 概述

本项目提供了一套用于操作 GitHub Actions 的脚本工具，包括：

1. **触发脚本** - 触发 GitHub Actions workflow 并获取 run ID
2. **监控脚本** - 监控 workflow 执行状态并获取错误日志
3. **组合脚本** - 自动触发并监控 workflow

## 前置要求

### 1. 安装 GitHub CLI

**macOS/Linux:**
```bash
# macOS
brew install gh

# Linux (Ubuntu/Debian)
sudo apt install gh

# 或从官网下载: https://cli.github.com/
```

**Windows:**
```powershell
# 使用 winget
winget install --id GitHub.cli

# 或使用 Chocolatey
choco install gh

# 或从官网下载: https://cli.github.com/
```

### 2. 登录 GitHub CLI

```bash
gh auth login
```

按照提示完成登录流程。

### 3. 验证安装

```bash
gh --version
gh auth status
```

## 脚本说明

### 1. trigger_workflow.sh / trigger_workflow.bat

触发指定的 GitHub Actions workflow 并获取 run ID。

**功能：**
- 触发指定的 workflow
- 传递输入参数
- 获取并保存 run ID 到 `.github_run_id.txt`

**使用方法：**

```bash
# macOS/Linux
./scripts/trigger_workflow.sh <workflow_file> [--ref <ref>] [--input <key=value>]...

# Windows
scripts\trigger_workflow.bat <workflow_file> [--ref <ref>] [--input <key=value>]...
```

**参数说明：**
- `workflow_file` - workflow 文件路径（必需）
- `--ref <ref>` - Git 引用（分支、标签或提交 SHA），默认为当前分支
- `--input <key=value>` - workflow 输入参数，可以多次使用

**示例：**

```bash
# 触发构建 workflow，使用 main 分支，传递版本号参数
./scripts/trigger_workflow.sh .github/workflows/build.yml --ref main --input version=1.0.7

# 触发发布 workflow，使用当前分支，传递多个参数
./scripts/trigger_workflow.sh .github/workflows/release.yml \
  --input version=1.0.7 \
  --input platform=all
```

**输出：**
- 在控制台显示触发结果和 run ID
- 将 run ID 保存到 `.github_run_id.txt` 文件

### 2. monitor_workflow.sh / monitor_workflow.bat

监控 GitHub Actions workflow 的执行状态。

**功能：**
- 持续监控 workflow 状态
- 每 5 秒查询一次状态
- 成功时退出（退出码 0）
- 失败时获取错误日志并退出（退出码 1）

**使用方法：**

```bash
# macOS/Linux
./scripts/monitor_workflow.sh [run_id]

# Windows
scripts\monitor_workflow.bat [run_id]
```

**参数说明：**
- `run_id` - GitHub Actions run ID（可选）
  - 如果不提供，将从 `.github_run_id.txt` 文件读取
  - 如果文件不存在，将报错退出

**示例：**

```bash
# 使用 run ID 监控
./scripts/monitor_workflow.sh 1234567890

# 从文件读取 run ID 并监控
./scripts/monitor_workflow.sh
```

**输出：**
- 实时显示 workflow 状态（排队中、运行中、完成）
- 成功时显示成功消息并退出
- 失败时：
  - 显示失败消息
  - 获取所有失败 job 的日志
  - 将日志保存到 `workflow_logs/workflow_{run_id}_error.log`
  - 显示简要错误信息

**日志文件位置：**
- `workflow_logs/workflow_{run_id}_error.log` - 失败时的错误日志

### 3. collect_workflow_logs.sh / collect_workflow_logs.bat

收集 GitHub Actions workflow 的详细日志。

**功能：**
- 收集 workflow run 的详细信息
- 收集所有 jobs 的日志（包括失败的 jobs）
- 保存到统一的日志文件
- 支持多种日志获取方式（job ID、job 名称、完整日志）

**使用方法：**

```bash
# macOS/Linux
./scripts/collect_workflow_logs.sh [run_id]

# Windows
scripts\collect_workflow_logs.bat [run_id]
```

**参数说明：**
- `run_id` - GitHub Actions run ID（可选）
  - 如果不提供，将从 `.github_run_id.txt` 文件读取
  - 如果文件不存在，将报错退出

**示例：**

```bash
# 使用 run ID 收集日志
./scripts/collect_workflow_logs.sh 1234567890

# 从文件读取 run ID 并收集日志
./scripts/collect_workflow_logs.sh
```

**输出：**
- 日志文件保存到 `workflow_logs/workflow_{run_id}_error.log`
- 包含 workflow 基本信息、jobs 摘要、失败 jobs 的详细日志

**日志文件内容：**
- Workflow 基本信息（Run ID、Workflow 名称、分支、事件等）
- Jobs 摘要（所有 jobs 的状态和结论）
- 失败的 Jobs 列表
- 每个失败 Job 的详细日志
- 如果无法获取日志，会提供 GitHub Actions URL

### 4. run_workflow.sh / run_workflow.bat

组合脚本：自动触发 workflow 并监控执行状态。

**功能：**
- 调用触发脚本触发 workflow
- 自动获取 run ID
- 调用监控脚本监控 workflow 状态
- 成功或失败时自动退出

**使用方法：**

```bash
# macOS/Linux
./scripts/run_workflow.sh <workflow_file> [--ref <ref>] [--input <key=value>]...

# Windows
scripts\run_workflow.bat <workflow_file> [--ref <ref>] [--input <key=value>]...
```

**参数说明：**
与 `trigger_workflow.sh` 相同。

**示例：**

```bash
# 触发并监控构建 workflow
./scripts/run_workflow.sh .github/workflows/build.yml --ref main --input version=1.0.7
```

**输出：**
- 显示触发结果
- 自动开始监控
- 根据执行结果退出（成功：0，失败：1）

## 使用场景

### 场景 1: 触发并等待完成

使用组合脚本，一次性完成触发和监控：

```bash
./scripts/run_workflow.sh .github/workflows/build.yml --ref main
```

### 场景 2: 触发后稍后监控

先触发 workflow，稍后再监控：

```bash
# 步骤 1: 触发 workflow
./scripts/trigger_workflow.sh .github/workflows/build.yml --ref main

# 步骤 2: 稍后监控（从文件读取 run ID）
./scripts/monitor_workflow.sh
```

### 场景 3: 监控已知的 run ID

如果已经知道 run ID，直接监控：

```bash
./scripts/monitor_workflow.sh 1234567890
```

### 场景 4: 收集 workflow 日志

当 workflow 失败后，收集详细日志进行分析：

```bash
# 从文件读取 run ID 并收集日志
./scripts/collect_workflow_logs.sh

# 或直接指定 run ID
./scripts/collect_workflow_logs.sh 1234567890
```

## 配置文件

### workflow_config.json.example

提供了一个配置文件示例，可以用于存储常用的 workflow 配置。

**位置：** `scripts/workflow_config.json.example`

**格式：**
```json
{
  "workflows": {
    "build": {
      "file": ".github/workflows/build.yml",
      "description": "构建所有平台",
      "default_ref": "main",
      "default_inputs": {
        "version": ""
      }
    }
  },
  "repository": {
    "owner": "",
    "name": ""
  }
}
```

**注意：** 当前脚本尚未实现配置文件读取功能，此文件仅供参考。未来可能会添加此功能。

## 错误处理

### 常见错误

1. **GitHub CLI 未安装**
   ```
   错误：未找到 GitHub CLI (gh)
   ```
   **解决方法：** 安装 GitHub CLI（见前置要求）

2. **GitHub CLI 未登录**
   ```
   错误：GitHub CLI 未登录
   ```
   **解决方法：** 运行 `gh auth login`

3. **无法获取 run ID**
   ```
   警告：无法获取 run ID
   ```
   **解决方法：** 
   - 等待几秒后重试
   - 手动查看 GitHub Actions 页面获取 run ID
   - 使用 `gh run list` 命令查看最近的 runs

4. **无法获取 run 信息**
   ```
   错误：无法获取 run 信息
   ```
   **解决方法：** 
   - 检查 run ID 是否正确
   - 检查是否有权限访问该 run
   - 检查网络连接

### 日志文件

失败时的错误日志保存在：
- `workflow_logs/workflow_{run_id}_error.log`

日志包含：
- 失败的 job 列表
- 每个失败 job 的完整日志
- 错误信息和堆栈跟踪

## 最佳实践

1. **使用组合脚本** - 对于简单的触发和监控场景，使用 `run_workflow.sh` 更便捷

2. **保存 run ID** - 触发脚本会自动保存 run ID，方便后续查询和监控

3. **定期检查日志** - 失败时使用 `collect_workflow_logs.sh` 收集详细日志
4. **使用日志收集脚本** - 当 workflow 失败后，使用专门的日志收集脚本获取完整错误信息

4. **使用版本参数** - 触发 workflow 时传递版本号等参数，确保构建正确的版本

5. **监控长时间运行的 workflow** - 对于长时间运行的 workflow，可以使用 `monitor_workflow.sh` 在后台监控

## 脚本文件列表

- `scripts/trigger_workflow.sh` - 触发脚本（macOS/Linux）
- `scripts/trigger_workflow.bat` - 触发脚本（Windows）
- `scripts/monitor_workflow.sh` - 监控脚本（macOS/Linux）
- `scripts/monitor_workflow.bat` - 监控脚本（Windows）
- `scripts/collect_workflow_logs.sh` - 日志收集脚本（macOS/Linux）
- `scripts/collect_workflow_logs.bat` - 日志收集脚本（Windows）
- `scripts/run_workflow.sh` - 组合脚本（macOS/Linux）
- `scripts/run_workflow.bat` - 组合脚本（Windows）
- `scripts/workflow_config.json.example` - 配置文件示例

## 注意事项

1. **执行权限** - Linux/macOS 上首次使用前需要添加执行权限：
   ```bash
   chmod +x scripts/*.sh
   ```

2. **网络连接** - 脚本需要网络连接来访问 GitHub API

3. **API 限制** - GitHub API 有速率限制，频繁查询可能会触发限制

4. **长时间运行** - 监控脚本会持续运行直到 workflow 完成，可能需要较长时间

5. **中断处理** - 按 Ctrl+C 可以停止监控，但不会取消 workflow

## 相关文档

- [GitHub CLI 文档](https://cli.github.com/manual/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [项目 GitHub Actions 规则](../.cursor/rules/07-github-actions.mdc)

