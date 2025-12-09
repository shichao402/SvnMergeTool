---
title: Windows Flutter 开发最佳实践
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# Windows Flutter 开发最佳实践

## 问题分析

Windows 上 Flutter 开发常见痛点：
1. **环境配置复杂** - PATH、权限、版本管理
2. **FVM 配置繁琐** - JSON/YAML 格式、安装时间长
3. **跨平台兼容性** - WSL、PowerShell、CMD 混用
4. **依赖管理** - 各种工具链配置

## 推荐方案（按优先级）

### 方案 1：使用 WSL2 + Flutter（最推荐）⭐

**优势：**
- ✅ 接近 Linux 原生体验，配置简单
- ✅ 避免 Windows 路径和权限问题
- ✅ 脚本统一，跨平台兼容性好
- ✅ 性能好，接近原生 Linux

**步骤：**

1. **安装 WSL2 和 Ubuntu：**
   ```powershell
   # 在 PowerShell (管理员) 中运行
   wsl --install
   # 重启后会自动安装 Ubuntu
   ```

2. **在 WSL2 中安装 Flutter：**
   ```bash
   # 在 WSL2 Ubuntu 终端中
   cd ~
   git clone https://github.com/flutter/flutter.git -b stable
   export PATH="$PATH:$HOME/flutter/bin"
   flutter doctor
   ```

3. **永久添加到 PATH：**
   ```bash
   # 编辑 ~/.bashrc
   echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```

4. **在 WSL2 中开发：**
   ```bash
   # 项目路径映射到 WSL
   cd /mnt/d/workspace/GitHub/SvnMergeTool
   flutter pub get
   flutter run -d windows  # 仍然可以构建 Windows 应用
   ```

**为什么推荐：**
- 脚本统一（都是 bash）
- 避免 Windows 路径问题
- 配置简单，一次设置长期使用

---

### 方案 2：使用 GitHub Codespaces（云端开发）⭐

**优势：**
- ✅ 零配置，开箱即用
- ✅ 环境一致，团队共享
- ✅ 不占用本地资源
- ✅ 支持 VS Code 远程开发

**步骤：**

1. **创建 `.devcontainer/devcontainer.json`：**
   ```json
   {
     "name": "Flutter Development",
     "image": "cirrusci/flutter:stable",
     "features": {
       "ghcr.io/devcontainers/features/git:1": {}
     },
     "customizations": {
       "vscode": {
         "extensions": [
           "Dart-Code.dart-code",
           "Dart-Code.flutter"
         ]
       }
     },
     "forwardPorts": [8080, 3000],
     "postCreateCommand": "flutter pub get"
   }
   ```

2. **在 GitHub 上：**
   - 打开项目
   - 点击 "Code" > "Codespaces" > "Create codespace"
   - 等待环境启动（约 1-2 分钟）

3. **直接开始开发：**
   - VS Code 会自动连接
   - Flutter 已预装
   - 可以直接运行和调试

**适用场景：**
- 快速开始，不想配置环境
- 团队协作，环境一致
- 临时调试，不占用本地资源

---

### 方案 3：简化 Windows 原生开发（如果必须用 Windows）

**简化配置步骤：**

1. **直接安装 Flutter（不用 FVM）：**
   ```powershell
   # 下载 Flutter SDK
   # https://docs.flutter.dev/get-started/install/windows
   
   # 解压到 C:\src\flutter（避免空格和中文路径）
   # 添加到 PATH: C:\src\flutter\bin
   ```

2. **使用 Chocolatey 一键安装：**
   ```powershell
   # 以管理员身份运行 PowerShell
   choco install flutter -y
   ```

3. **验证安装：**
   ```powershell
   flutter doctor
   flutter --version
   ```

4. **项目直接使用系统 Flutter：**
   ```powershell
   # 不需要 FVM，直接使用
   flutter pub get
   flutter run
   ```

**为什么简化：**
- FVM 在 Windows 上配置复杂
- 单个项目通常只需要一个 Flutter 版本
- 直接使用系统 Flutter 更简单

---

### 方案 4：使用 Docker（容器化开发）

**优势：**
- ✅ 环境隔离，不影响系统
- ✅ 可重复，团队一致
- ✅ 支持多版本

**步骤：**

1. **创建 `Dockerfile`：**
   ```dockerfile
   FROM cirrusci/flutter:stable
   
   WORKDIR /app
   COPY . .
   RUN flutter pub get
   
   CMD ["flutter", "run"]
   ```

2. **创建 `docker-compose.yml`：**
   ```yaml
   version: '3.8'
   services:
     flutter:
       build: .
       volumes:
         - .:/app
       command: flutter run -d windows
   ```

3. **使用：**
   ```bash
   docker-compose up
   ```

---

## 针对本项目的建议

### 当前问题

1. **FVM 配置复杂** - `.fvmrc` 格式问题
2. **Windows 路径问题** - WSL 和 Windows 路径混用
3. **环境不一致** - 不同开发者环境不同

### 推荐方案

**立即可用的方案：**

1. **删除 FVM 配置，直接使用系统 Flutter：**
   ```powershell
   # 如果系统有 Flutter，直接使用
   flutter pub get
   flutter run -d windows
   ```

2. **或者使用 WSL2：**
   ```bash
   # 在 WSL2 中
   cd /mnt/d/workspace/GitHub/SvnMergeTool
   flutter pub get
   flutter run -d windows
   ```

3. **或者使用 GitHub Codespaces：**
   - 创建 `.devcontainer` 配置
   - 在云端开发，零配置

### 简化部署脚本

更新部署脚本，支持：
- 自动检测 Flutter（系统或 FVM）
- 优先使用系统 Flutter（更简单）
- 如果检测到 FVM 才使用 FVM

---

## 最佳实践总结

### 1. 环境选择优先级

1. **WSL2** - 如果主要开发 Linux/跨平台应用
2. **GitHub Codespaces** - 如果快速开始或团队协作
3. **Windows 原生** - 如果必须用 Windows 且只开发 Windows 应用
4. **Docker** - 如果需要环境隔离或多版本

### 2. 避免的陷阱

- ❌ 不要混用 FVM 和系统 Flutter（选择一种）
- ❌ 不要在路径中使用空格和中文
- ❌ 不要过度配置（简单就是美）
- ❌ 不要在 WSL 和 Windows 之间频繁切换

### 3. 推荐的开发流程

```
1. 选择环境（WSL2 或 Codespaces）
   ↓
2. 安装 Flutter（一次配置）
   ↓
3. 克隆项目
   ↓
4. flutter pub get
   ↓
5. flutter run
   ↓
6. 开始开发
```

### 4. 团队协作建议

- **统一环境** - 团队使用相同环境（WSL2 或 Codespaces）
- **文档化** - 记录环境配置步骤
- **自动化** - 使用脚本自动化常见操作
- **容器化** - 考虑 Docker 确保一致性

---

## 快速开始（推荐：WSL2）

```bash
# 1. 在 WSL2 Ubuntu 中
cd /mnt/d/workspace/GitHub/SvnMergeTool

# 2. 安装 Flutter（如果还没有）
# 参考上面的 WSL2 安装步骤

# 3. 获取依赖
flutter pub get

# 4. 运行应用
flutter run -d windows

# 5. 开始调试
# 在 VS Code 中打开项目，设置断点
```

---

## 相关资源

- [Flutter Windows 安装指南](https://docs.flutter.dev/get-started/install/windows)
- [WSL2 安装指南](https://learn.microsoft.com/zh-cn/windows/wsl/install)
- [GitHub Codespaces 文档](https://docs.github.com/en/codespaces)
- [Flutter Docker 镜像](https://hub.docker.com/r/cirrusci/flutter)

---

## 总结

**Windows 上 Flutter 开发并不难，关键是选择合适的环境：**

- 🥇 **WSL2** - 最推荐，接近原生体验
- 🥈 **GitHub Codespaces** - 零配置，开箱即用
- 🥉 **Windows 原生** - 简化配置，直接使用系统 Flutter
- 🏅 **Docker** - 环境隔离，团队一致

**记住：简单就是美，不要过度配置！**

