# SVN 自动合并工具 (Flutter 版本)

一个跨平台的 SVN 自动合并桌面工具，支持自动重试提交、任务队列、插件扩展等功能。

## 文档

详细的文档请查看 [Documents/](Documents/) 目录：

- [配置说明](Documents/configuration.md) - 配置文件使用和部署说明
- [脚本说明](Documents/scripts.md) - 部署和日志收集脚本使用说明
- [版本管理](Documents/development/version-management.md) - 版本号管理和 CI/CD 说明

## 快速开始

### 环境准备（推荐方案）

**🥇 方案 1：使用 WSL2（最推荐，最简单）**

```bash
# 在 WSL2 Ubuntu 中
cd /mnt/d/workspace/GitHub/SvnMergeTool
flutter pub get
flutter run -d windows
```

**🥈 方案 2：Windows 原生（简化版）**

```powershell
# 快速开始脚本（自动检测 Flutter）
.\scripts\quick_start.ps1

# 或手动安装 Flutter
# 下载: https://docs.flutter.dev/get-started/install/windows
# 或使用: choco install flutter -y
```

**🥉 方案 3：GitHub Codespaces（零配置）**

- 在 GitHub 上打开项目
- 点击 "Code" > "Codespaces" > "Create codespace"
- 等待环境启动，直接开始开发

> 💡 **详细说明请查看：[Windows 开发最佳实践](Documents/development/windows-dev-best-practices.md)**

### 运行应用

1. 配置 SVN 源 URL：编辑 `config/source_urls.json`
2. 部署应用：运行 `scripts/deploy.sh`（macOS/Linux）或 `scripts/deploy.bat`（Windows）
3. 查看日志：运行 `scripts/collect_logs.sh`（macOS/Linux）或 `scripts/collect_logs.bat`（Windows）

更多信息请参考 [文档目录](Documents/README.md)：
- [配置说明](Documents/configuration.md) - 配置文件使用和部署说明
- [脚本说明](Documents/scripts.md) - 部署和日志收集脚本使用说明
- [版本管理](Documents/development/version-management.md) - 版本号管理和 CI/CD 说明
