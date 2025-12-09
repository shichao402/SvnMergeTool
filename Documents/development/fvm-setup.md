---
title: FVM 环境设置指南
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# FVM 环境设置指南

## 概述

本项目使用 FVM (Flutter Version Management) 来管理 Flutter 版本，确保开发环境的一致性。

## 前置要求

### 1. 安装 FVM

**使用 Dart pub 安装（推荐）：**
```powershell
dart pub global activate fvm
```

**验证安装：**
```powershell
fvm --version
```

**更多安装方式：**
- 访问 [FVM 官方文档](https://fvm.app/docs/getting_started/installation)

### 2. 确保 FVM 在 PATH 中

安装 FVM 后，确保 `fvm` 命令可以在命令行中访问。如果无法访问，可能需要：

1. 将 `%USERPROFILE%\AppData\Local\Pub\Cache\bin` 添加到 PATH
2. 或者重新打开命令行窗口

## 快速设置

### 使用自动化脚本（推荐）

**Windows (PowerShell):**
```powershell
.\scripts\setup_fvm.ps1
```

**Windows (Batch):**
```batch
scripts\setup_fvm.bat
```

脚本会自动：
1. 检查 FVM 安装
2. 从 `.fvmrc` 读取 Flutter 版本
3. 安装指定的 Flutter 版本
4. 配置项目使用 FVM Flutter
5. 获取项目依赖

### 手动设置

1. **安装 Flutter 版本：**
   ```powershell
   fvm install 3.27.0
   ```

2. **配置项目使用 FVM：**
   ```powershell
   fvm use 3.27.0
   ```

3. **获取依赖：**
   ```powershell
   fvm flutter pub get
   ```

## 项目配置

### .fvmrc 文件

项目根目录包含 `.fvmrc` 文件，指定了项目使用的 Flutter 版本：

```yaml
flutter: "3.27.0"
channel: "stable"
```

### 使用 FVM Flutter

在项目中使用 FVM Flutter，需要在所有 Flutter 命令前加上 `fvm`：

```powershell
# 获取依赖
fvm flutter pub get

# 运行应用
fvm flutter run

# 构建应用
fvm flutter build windows --debug

# 运行测试
fvm flutter test
```

### 部署脚本支持

项目的部署脚本（`scripts/deploy.bat` 和 `scripts/deploy.ps1`）已自动支持 FVM：

- 如果检测到 `.fvmrc` 文件且 FVM 已安装，会自动使用 `fvm flutter`
- 否则使用系统 PATH 中的 `flutter` 命令

## IDE 配置

### VS Code

1. 安装 [FVM VS Code 扩展](https://marketplace.visualstudio.com/items?itemName=leoafarias.fvm)
2. 扩展会自动检测 `.fvmrc` 并配置 Flutter SDK 路径

### Android Studio / IntelliJ IDEA

1. 打开项目设置
2. 导航到 Languages & Frameworks > Flutter
3. 将 Flutter SDK path 设置为：`.fvm/flutter_sdk`
4. 或者使用 FVM 扩展（如果可用）

## 常见问题

### FVM 命令未找到

**问题：** 运行 `fvm` 命令时提示未找到

**解决方法：**
1. 确保已安装 FVM：`dart pub global activate fvm`
2. 检查 PATH 是否包含：`%USERPROFILE%\AppData\Local\Pub\Cache\bin`
3. 重新打开命令行窗口

### Flutter 版本不匹配

**问题：** 项目要求 Flutter 3.27.0，但系统安装的是其他版本

**解决方法：**
1. 使用 FVM 安装正确版本：`fvm install 3.27.0`
2. 配置项目使用：`fvm use 3.27.0`
3. 使用 `fvm flutter` 而不是 `flutter`

### 依赖获取失败

**问题：** `fvm flutter pub get` 失败

**解决方法：**
1. 确保 FVM Flutter 已正确安装：`fvm list`
2. 检查网络连接
3. 清理缓存：`fvm flutter pub cache repair`
4. 重新获取：`fvm flutter pub get`

## 版本管理

### 查看已安装的 Flutter 版本

```powershell
fvm list
```

### 切换 Flutter 版本

```powershell
fvm use <version>
```

### 设置全局默认版本

```powershell
fvm global <version>
```

## 最佳实践

1. **始终使用 FVM：** 在项目中使用 `fvm flutter` 而不是直接使用 `flutter`
2. **提交 .fvmrc：** 确保 `.fvmrc` 文件已提交到版本控制
3. **团队协作：** 团队成员应使用相同的 Flutter 版本（通过 `.fvmrc` 指定）
4. **CI/CD：** GitHub Actions 使用固定版本（3.27.0），与本地开发环境保持一致

## 相关资源

- [FVM 官方文档](https://fvm.app/)
- [FVM GitHub 仓库](https://github.com/leoafarias/fvm)
- [项目部署脚本](../scripts.md)

