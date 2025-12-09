---
title: WSL2 环境设置指南
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# WSL2 Flutter 开发环境设置指南

## 快速开始

### 步骤 1: 安装系统依赖

```bash
# 运行依赖安装脚本（需要输入 sudo 密码）
bash scripts/setup_wsl2_dependencies.sh

# 或者手动安装
sudo apt-get update
sudo apt-get install -y unzip curl git xz-utils zip libglu1-mesa
```

### 步骤 2: 安装 Flutter

```bash
# 运行 Flutter 安装脚本
bash scripts/setup_wsl2_flutter.sh
```

脚本会自动：
- 克隆 Flutter stable 版本到 `~/flutter`
- 配置 PATH（添加到 `~/.bashrc`）
- 运行 `flutter doctor` 检查环境
- 获取项目依赖

### 步骤 3: 验证安装

```bash
# 重新加载 shell 配置（或重启终端）
source ~/.bashrc

# 检查 Flutter
flutter --version

# 检查环境
flutter doctor

# 查看可用设备
flutter devices
```

### 步骤 4: 开始开发

```bash
# 获取项目依赖
flutter pub get

# 运行应用（Windows 桌面）
flutter run -d windows

# 或使用部署脚本
./scripts/deploy.sh
```

## 常见问题

### 1. Flutter 命令未找到

**问题：** 运行 `flutter` 命令提示未找到

**解决：**
```bash
# 检查 PATH
echo $PATH | grep flutter

# 如果不在 PATH 中，手动添加
export PATH="$PATH:$HOME/flutter/bin"

# 永久添加到 ~/.bashrc
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 2. 缺少 unzip 工具

**问题：** `Missing "unzip" tool. Unable to extract Dart SDK.`

**解决：**
```bash
sudo apt-get install -y unzip
```

### 3. Flutter doctor 显示问题

**问题：** `flutter doctor` 显示某些工具未安装

**解决：**
- **Android Studio:** 可选，如果只开发 Windows 应用不需要
- **VS Code:** 可选，但推荐安装 Flutter 扩展
- **Chrome:** 可选，用于 Web 开发

对于 Windows 桌面开发，只需要：
- ✅ Flutter SDK
- ✅ Windows 开发工具（在 Windows 主机上）

### 4. 权限问题

**问题：** 无法写入某些目录

**解决：**
```bash
# 确保 Flutter 目录有正确权限
chmod -R 755 ~/flutter
```

## 项目配置

### PATH 配置

Flutter 已自动添加到 `~/.bashrc`：
```bash
# Flutter SDK
export PATH="$PATH:$HOME/flutter/bin"
```

### 项目路径

项目位于 Windows 文件系统，通过 `/mnt/d/` 访问：
```bash
cd /mnt/d/workspace/GitHub/SvnMergeTool
```

### 使用部署脚本

项目提供了部署脚本，自动处理构建和运行：
```bash
./scripts/deploy.sh
```

脚本会：
- 检查 Flutter 环境
- 同步版本号
- 获取依赖
- 构建应用
- 复制配置文件

## 开发工作流

### 日常开发

```bash
# 1. 进入项目目录
cd /mnt/d/workspace/GitHub/SvnMergeTool

# 2. 获取最新代码
git pull

# 3. 获取依赖（如果有更新）
flutter pub get

# 4. 运行应用
flutter run -d windows

# 5. 热重载：按 'r'
# 6. 热重启：按 'R'
# 7. 退出：按 'q'
```

### 调试

```bash
# 运行并启用调试
flutter run -d windows --debug

# 查看日志
flutter logs

# 或使用项目日志收集脚本
./scripts/collect_logs.sh
```

### 构建

```bash
# Debug 构建
flutter build windows --debug

# Release 构建
flutter build windows --release
```

## 性能优化

### WSL2 文件系统性能

- **推荐：** 在 WSL2 文件系统中开发（`~/projects/`）
- **可接受：** 在 Windows 文件系统中开发（`/mnt/d/`），但性能稍慢

### 构建缓存

Flutter 会自动缓存构建产物，首次构建较慢，后续会更快。

## 相关资源

- [Flutter 官方文档](https://docs.flutter.dev/)
- [WSL2 文档](https://learn.microsoft.com/zh-cn/windows/wsl/)
- [项目部署脚本说明](../scripts.md)

