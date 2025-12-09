---
title: Windows Flutter 开发环境配置经验总结
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# Windows Flutter 开发环境配置经验总结

## 背景

本文档记录了在 Windows 环境下配置 Flutter 开发环境的完整过程，包括遇到的问题、尝试的解决方案、最终选择的方案以及经验教训。

## 时间线

### 阶段 1: 尝试使用 FVM（Flutter Version Management）

**目标：** 使用 FVM 管理 Flutter 版本，确保团队环境一致

**遇到的问题：**
1. **FVM 配置文件格式错误**
   - 最初创建了 `.fvmrc` 文件，使用 YAML 格式
   - FVM 实际需要 JSON 格式的配置文件（`.fvm/fvm_config.json`）
   - 错误：`FormatException: Unexpected character (at character 1)`

2. **FVM 安装 Flutter 耗时过长**
   - 首次安装需要下载完整的 Flutter SDK（~365MB）
   - 在 Windows 环境下下载速度较慢
   - 用户多次取消安装过程

3. **Windows 路径问题**
   - WSL 和 Windows 路径格式混用
   - PowerShell 和 CMD 脚本路径处理不一致
   - 跨平台脚本兼容性问题

**尝试的解决方案：**
- 创建 `.fvmrc` 配置文件（失败）
- 使用 `fvm use` 命令自动生成配置（部分成功）
- 创建 FVM 设置脚本（`setup_fvm.ps1`, `setup_fvm.bat`）

**结果：** 放弃 FVM，选择更简单的方案

---

### 阶段 2: 简化 Windows 原生开发

**目标：** 直接在 Windows 上使用系统 Flutter，避免 FVM 的复杂性

**遇到的问题：**
1. **系统 Flutter 未安装**
   - Windows 系统 PATH 中找不到 Flutter
   - 需要手动安装 Flutter SDK

2. **环境配置复杂**
   - 需要配置多个环境变量
   - 需要安装 Visual Studio、Windows SDK 等依赖
   - 配置过程繁琐

**尝试的解决方案：**
- 创建快速开始脚本（`quick_start.ps1`）
- 更新部署脚本，优先使用系统 Flutter
- 提供 Chocolatey 一键安装方案

**结果：** 虽然可行，但配置仍然复杂

---

### 阶段 3: 选择 WSL2 作为开发环境（最终方案）

**目标：** 使用 WSL2 提供接近 Linux 原生的开发体验

**优势：**
- ✅ 配置简单，接近 Linux 原生体验
- ✅ 避免 Windows 路径和权限问题
- ✅ 脚本统一（都是 bash），跨平台兼容性好
- ✅ 性能好，接近原生 Linux

**实施过程：**
1. **检查 WSL2 环境**
   - 确认 WSL2 已安装并运行
   - 确认在 WSL2 Ubuntu 环境中

2. **安装 Flutter**
   - 克隆 Flutter stable 版本到 `~/flutter`
   - 配置 PATH（添加到 `~/.bashrc`）
   - 首次运行需要下载 Dart SDK

3. **安装系统依赖**
   - 需要 `unzip` 工具（Flutter 解压 Dart SDK 需要）
   - 需要 `curl`, `git`, `xz-utils`, `zip`, `libglu1-mesa`
   - 使用 `sudo apt-get install` 安装

4. **验证环境**
   - 运行 `flutter doctor` 检查环境
   - 获取项目依赖 `flutter pub get`
   - 验证构建能力

**遇到的问题：**
1. **缺少系统依赖**
   - 首次运行 Flutter 时提示缺少 `unzip`
   - 需要 sudo 权限安装依赖

2. **首次下载耗时**
   - Dart SDK 下载需要时间（~20MB）
   - Flutter 工具构建需要时间

**解决方案：**
- 创建依赖安装脚本（`setup_wsl2_dependencies.sh`）
- 创建 Flutter 安装脚本（`setup_wsl2_flutter.sh`）
- 创建验证脚本（`verify_build.sh`）

**结果：** ✅ 成功，环境配置完成

---

## 经验教训

### 1. 不要过度配置

**教训：** 最初尝试使用 FVM 是为了版本管理，但实际上：
- 单个项目通常只需要一个 Flutter 版本
- FVM 在 Windows 上配置复杂，收益有限
- 简单直接使用系统 Flutter 或 WSL2 更实用

**建议：**
- 优先选择最简单的方案
- 只有在真正需要时才引入复杂工具
- 评估工具带来的价值 vs 配置成本

### 2. 环境选择很重要

**教训：** Windows 原生开发环境配置复杂，而 WSL2 提供了更简单的方案

**对比：**

| 方案 | 配置复杂度 | 开发体验 | 推荐度 |
|------|-----------|---------|--------|
| Windows 原生 + FVM | ⭐⭐⭐⭐⭐ 很高 | ⭐⭐⭐ 一般 | ⭐⭐ |
| Windows 原生 + 系统 Flutter | ⭐⭐⭐ 中等 | ⭐⭐⭐ 一般 | ⭐⭐⭐ |
| WSL2 + Flutter | ⭐⭐ 较低 | ⭐⭐⭐⭐⭐ 很好 | ⭐⭐⭐⭐⭐ |
| GitHub Codespaces | ⭐ 很低 | ⭐⭐⭐⭐ 很好 | ⭐⭐⭐⭐ |

**建议：**
- 优先考虑 WSL2（如果主要开发跨平台应用）
- 考虑 GitHub Codespaces（如果快速开始或团队协作）
- Windows 原生作为备选（如果必须用 Windows 且只开发 Windows 应用）

### 3. 文档和脚本很重要

**教训：** 在配置过程中，创建了多个脚本和文档，大大简化了后续操作

**创建的脚本：**
- `setup_wsl2_dependencies.sh` - 安装系统依赖
- `setup_wsl2_flutter.sh` - 安装 Flutter
- `verify_build.sh` - 验证环境
- `quick_start.ps1` - Windows 快速开始
- `setup_fvm.ps1` / `setup_fvm.bat` - FVM 设置（虽然最终未使用）

**创建的文档：**
- `windows-dev-best-practices.md` - Windows 开发最佳实践
- `wsl2-setup-guide.md` - WSL2 设置指南
- `fvm-setup.md` - FVM 设置指南（虽然最终未使用）

**建议：**
- 将配置过程脚本化
- 记录问题和解决方案
- 为团队提供清晰的文档

### 4. 首次配置需要耐心

**教训：** Flutter 首次安装需要下载大量文件，需要耐心等待

**首次安装需要：**
- Flutter SDK（~365MB）
- Dart SDK（~20MB）
- 各种依赖包

**建议：**
- 首次安装时预留足够时间
- 使用稳定的网络连接
- 可以考虑使用镜像源加速下载

### 5. 工具版本和格式很重要

**教训：** FVM 配置文件格式错误导致无法使用

**问题：**
- 创建了 YAML 格式的 `.fvmrc`
- FVM 实际需要 JSON 格式的 `.fvm/fvm_config.json`
- 应该使用 `fvm use` 命令自动生成，而不是手动创建

**建议：**
- 仔细阅读工具文档
- 使用工具提供的命令生成配置文件
- 不要假设配置文件格式

---

## 最佳实践总结

### 1. 环境选择优先级

```
1. WSL2（最推荐）
   - 配置简单
   - 开发体验好
   - 跨平台兼容

2. GitHub Codespaces（零配置）
   - 快速开始
   - 团队一致
   - 不占用本地资源

3. Windows 原生（备选）
   - 直接使用系统 Flutter
   - 避免 FVM 复杂性
   - 简化配置
```

### 2. 配置流程

**WSL2 环境：**
```bash
# 1. 安装系统依赖
bash scripts/setup_wsl2_dependencies.sh

# 2. 安装 Flutter
bash scripts/setup_wsl2_flutter.sh

# 3. 验证环境
bash scripts/verify_build.sh

# 4. 开始开发
flutter pub get
flutter run -d windows
```

**Windows 原生：**
```powershell
# 1. 安装 Flutter（使用 Chocolatey）
choco install flutter -y

# 2. 快速开始
.\scripts\quick_start.ps1

# 3. 开始开发
flutter pub get
flutter run -d windows
```

### 3. 脚本设计原则

1. **模块化** - 每个脚本负责单一职责
2. **跨平台** - 提供 Windows、macOS、Linux 版本
3. **非交互式** - 避免需要用户输入（AI 友好）
4. **错误处理** - 清晰的错误提示和解决建议
5. **文档化** - 脚本内包含注释和使用说明

### 4. 文档组织

```
Documents/
├── development/
│   ├── windows-dev-best-practices.md  # 最佳实践
│   ├── wsl2-setup-guide.md            # WSL2 设置指南
│   ├── windows-environment-lessons-learned.md  # 本文档
│   └── fvm-setup.md                   # FVM 设置（参考）
```

### 5. 避免的陷阱

- ❌ 不要混用 FVM 和系统 Flutter
- ❌ 不要在路径中使用空格和中文
- ❌ 不要过度配置（简单就是美）
- ❌ 不要在 WSL 和 Windows 之间频繁切换
- ❌ 不要假设配置文件格式

---

## 最终方案

### 推荐配置

**开发环境：** WSL2 Ubuntu + Flutter Stable

**配置步骤：**
1. 确保 WSL2 已安装并运行
2. 运行 `bash scripts/setup_wsl2_dependencies.sh` 安装依赖
3. 运行 `bash scripts/setup_wsl2_flutter.sh` 安装 Flutter
4. 运行 `bash scripts/verify_build.sh` 验证环境
5. 开始开发

**优势：**
- ✅ 配置简单，一次设置长期使用
- ✅ 开发体验接近 Linux 原生
- ✅ 脚本统一，易于维护
- ✅ 跨平台兼容性好

### 备选方案

**GitHub Codespaces：** 如果不想配置本地环境，可以使用云端开发

**Windows 原生：** 如果必须用 Windows 且只开发 Windows 应用

---

## 关键指标

### 配置时间对比

| 方案 | 首次配置时间 | 后续使用 |
|------|------------|---------|
| WSL2 | ~15-20 分钟 | 即开即用 |
| Windows + FVM | ~30-45 分钟 | 需要维护 |
| Windows 原生 | ~20-30 分钟 | 即开即用 |
| Codespaces | ~2-3 分钟 | 即开即用 |

### 配置复杂度对比

| 方案 | 复杂度 | 需要工具 |
|------|--------|---------|
| WSL2 | ⭐⭐ | WSL2, Flutter |
| Windows + FVM | ⭐⭐⭐⭐⭐ | Flutter, FVM, Dart |
| Windows 原生 | ⭐⭐⭐ | Flutter, VS/Windows SDK |
| Codespaces | ⭐ | 浏览器 |

---

## 总结

### 核心经验

1. **简单就是美** - 不要过度配置，选择最简单的可行方案
2. **环境选择很重要** - WSL2 提供了更好的开发体验
3. **文档和脚本是关键** - 脚本化配置过程，文档化经验教训
4. **首次配置需要耐心** - 预留足够时间，使用稳定网络
5. **工具版本和格式很重要** - 仔细阅读文档，使用正确格式

### 最终建议

**对于新项目：**
- 🥇 优先使用 WSL2
- 🥈 考虑 GitHub Codespaces
- 🥉 Windows 原生作为备选

**对于现有项目：**
- 评估当前环境配置复杂度
- 如果配置复杂，考虑迁移到 WSL2
- 保持文档和脚本更新

**对于团队：**
- 统一开发环境（推荐 WSL2）
- 提供清晰的设置文档
- 脚本化常见操作

---

## 相关资源

- [Windows 开发最佳实践](windows-dev-best-practices.md)
- [WSL2 设置指南](wsl2-setup-guide.md)
- [项目脚本说明](../../scripts.md)
- [Flutter 官方文档](https://docs.flutter.dev/)
- [WSL2 官方文档](https://learn.microsoft.com/zh-cn/windows/wsl/)

---

**文档版本：** 1.0  
**最后更新：** 2024-12-19  
**作者：** 开发团队

