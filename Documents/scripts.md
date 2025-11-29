# 脚本说明

## 概述

项目提供了跨平台的部署和日志收集脚本，支持 macOS、Linux 和 Windows。

## 脚本文件

### 部署脚本

- **macOS/Linux**: `scripts/deploy.sh`
- **Windows**: `scripts/deploy.bat`

**功能：**
- 检查 Flutter 环境
- 构建应用
- 安装到设备（移动平台）
- 启动应用
- 自动复制配置文件到构建输出

### 日志收集脚本

- **macOS/Linux**: `scripts/collect_logs.sh`
- **Windows**: `scripts/collect_logs.bat`

**功能：**
- 收集应用日志文件
- 收集配置文件
- 收集系统信息
- 生成日志摘要

## 使用方法

### macOS/Linux

```bash
# 部署应用
./scripts/deploy.sh

# 收集日志
./scripts/collect_logs.sh
```

### Windows

在命令提示符（CMD）中：

```batch
REM 部署应用
scripts\deploy.bat

REM 收集日志
scripts\collect_logs.bat
```

或者在 PowerShell 中：

```powershell
# 部署应用
.\scripts\deploy.bat

# 收集日志
.\scripts\collect_logs.bat
```

## 跨平台支持

根据项目规则要求，脚本应该考虑跨平台兼容性：

1. **macOS/Linux**: 使用 Bash 脚本（`.sh`）
2. **Windows**: 使用批处理脚本（`.bat`）

两个平台的脚本功能相同，只是实现方式不同。

## 注意事项

1. **Windows 用户**：如果系统已安装 Git Bash 或 WSL，也可以使用 `.sh` 脚本
2. **macOS/Linux 用户**：只能使用 `.sh` 脚本
3. **配置文件**：构建脚本会自动复制 `config/source_urls.json` 到构建输出目录
4. **Windows 桌面应用**：部署脚本会自动检测平台，对于 Windows 桌面应用会跳过设备检测步骤

## 脚本设计原则

根据项目规则（`.cursor/rules/02-scripts.mdc`）：

1. **模块化设计** - 每个脚本负责单一职责
2. **单点可复用** - 避免重复编写相同逻辑
3. **通用和跨平台化** - 确保脚本在不同环境下都能正常工作

## 相关文档

- 配置说明：[configuration.md](configuration.md)

