---
title: WSL2 环境设置指南
category: development
created: 2024-12-19
updated: 2026-05-23
author: 开发团队
status: approved
---

# WSL2 Flutter 开发环境设置指南

## 适用范围

这份说明面向当前仓库的日常开发，不依赖旧版的一键安装脚本。目标是用最少步骤把 WSL2 环境稳定跑起来。

## 前置条件

1. Windows 已启用 WSL2。
2. 已安装 Ubuntu 或其他常见发行版。
3. Windows 主机侧已经具备 Windows 桌面构建能力。

如果只是在 WSL2 内跑 `flutter analyze`、`flutter test`，第三条不是必须；如果要 `flutter run -d windows`，则仍然需要 Windows 主机侧工具链可用。

## 步骤 1：安装基础依赖

在 WSL2 终端执行：

```bash
sudo apt-get update
sudo apt-get install -y unzip curl git xz-utils zip libglu1-mesa
```

这些工具主要用于：

- 解压 Dart / Flutter 依赖
- 拉取 Flutter SDK
- 支持常见桌面命令链

## 步骤 2：安装 Flutter

推荐直接安装 stable 分支：

```bash
git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

验证：

```bash
flutter --version
flutter doctor
```

## 步骤 3：进入项目并获取依赖

```bash
cd /mnt/<drive>/<path>/SvnAutoMerge
flutter pub get
```

如果你已经把仓库放在 WSL2 文件系统中，也可以直接进入 Linux 路径开发。

## 步骤 4：常用开发命令

代码检查：

```bash
flutter analyze
flutter test
```

运行桌面应用：

```bash
flutter run -d windows
```

或使用仓库脚本：

```bash
./scripts/deploy.sh
./scripts/collect_logs.sh
./scripts/version.sh get app
```

## 常见问题

### 1. `flutter` 命令不存在

检查 PATH：

```bash
which flutter
echo "$PATH"
```

如果没有指向 `~/flutter/bin`，重新执行：

```bash
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 2. 缺少 `unzip`

错误一般类似：`Missing "unzip" tool. Unable to extract Dart SDK.`

解决：

```bash
sudo apt-get install -y unzip
```

### 3. `flutter run -d windows` 无法工作

这通常不是 WSL2 内的 Flutter 本身有问题，而是 Windows 主机侧缺少桌面工具链。先在 Windows 侧执行：

```powershell
flutter doctor
```

确认 Windows 桌面相关依赖已经正常。

### 4. 文件系统性能较慢

如果在 `/mnt/<drive>/...` 下开发感觉偏慢，可以考虑把仓库放进 WSL2 文件系统中，再通过编辑器远程访问。

## 建议

- 保持 Flutter 只有一套主要安装路径。
- 避免同时混用多套版本管理方案。
- 出问题先跑：`flutter doctor`、`flutter pub get`、`flutter analyze`、`flutter test`。
- 日志排查优先用 `./scripts/collect_logs.sh`。

## 相关文档

- [Windows 开发最佳实践](windows-dev-best-practices.md)
- [脚本说明](../scripts.md)
- [Flutter 官方文档](https://docs.flutter.dev/)
