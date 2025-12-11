---
title: 环境配置经验总结
category: development
created: 2024-12-19
updated: 2024-12-19
author: 开发团队
status: approved
---

# 环境配置经验总结

## 核心教训

**手动安装环境比自动化脚本更靠谱**

经过多次尝试使用自动化脚本配置开发环境，最终发现手动安装各种开发工具和环境更加可靠和可控。

## 问题分析

### 自动化脚本的局限性

1. **环境差异**：不同开发者的系统配置、已安装软件、PATH 设置都不同
2. **权限问题**：环境变量设置、PATH 修改需要管理员权限或用户级权限
3. **跨平台复杂性**：WSL、Windows、PowerShell、CMD 混用导致脚本兼容性问题
4. **错误处理困难**：脚本失败时难以定位具体问题
5. **维护成本高**：需要不断更新脚本以适应各种环境变化

### 手动安装的优势

1. **可控性强**：每一步都能看到具体操作和结果
2. **问题定位清晰**：遇到问题能立即知道是哪一步出错
3. **学习效果好**：手动安装能更好地理解环境配置原理
4. **灵活性高**：可以根据实际情况调整安装步骤
5. **一次配置长期使用**：环境配置好后通常不需要频繁修改

## Windows Flutter 开发环境配置要点

### 1. Flutter SDK 安装

**推荐方式：**
- 下载 Flutter SDK 压缩包
- 解压到不含空格的路径（如 `C:\tools\flutter`）
- 手动添加到系统 PATH 环境变量

**验证：**
```powershell
flutter --version
flutter doctor
```

### 2. Android Studio 配置

**关键步骤：**

1. **安装 Android Studio**
   - 从官网下载安装
   - 首次启动会自动配置 Android SDK

2. **安装 Command-line Tools（重要）**
   - 打开 Android Studio
   - `File` > `Settings` > `Appearance & Behavior` > `System Settings` > `Android SDK`
   - 点击 `SDK Tools` 标签
   - 勾选 `Android SDK Command-line Tools (latest)`
   - 点击 `Apply` 安装

3. **设置环境变量**
   - `ANDROID_HOME`: `C:\Users\<用户名>\AppData\Local\Android\sdk`
   - `ANDROID_SDK_ROOT`: 同上
   - 添加到 PATH: `%ANDROID_HOME%\platform-tools`

4. **接受许可证**
   ```powershell
   flutter doctor --android-licenses
   ```

### 3. 常见问题

#### 问题 1：cmdline-tools component is missing

**原因：** Android Studio 默认不安装 Command-line Tools

**解决：** 通过 Android Studio 的 SDK Manager 安装（见上面步骤）

#### 问题 2：ANDROID_HOME not set

**原因：** 环境变量未配置

**解决：** 手动设置 `ANDROID_HOME` 环境变量指向 Android SDK 路径

#### 问题 3：在 WSL 中无法构建 Windows 应用

**原因：** Flutter 的 `build windows` 命令只能在 Windows 主机上运行

**解决：** 
- 在 Windows PowerShell/CMD 中运行编译命令
- 或使用 Windows 版本的 Flutter SDK

## 最佳实践建议

### 1. 环境配置文档化

- 记录每个工具的安装路径
- 记录环境变量的设置
- 记录遇到的问题和解决方案

### 2. 使用官方安装方式

- Flutter: 从官网下载 SDK
- Android Studio: 从官网下载安装包
- 避免使用第三方包管理器（除非非常熟悉）

### 3. 验证环境配置

安装完成后运行：
```powershell
flutter doctor -v
```

检查所有工具链是否正常。

### 4. 保持环境简洁

- 只安装必要的工具
- 避免安装多个版本的同一工具
- 定期清理不需要的组件

### 5. 版本管理

- 记录使用的工具版本
- 使用 FVM 管理 Flutter 版本（如果需要多版本）
- 保持 Android SDK 工具更新

## 已删除的过时脚本

以下自动化设置脚本已被删除，因为手动安装更可靠：

- `scripts/fix_android_toolchain.ps1` / `.bat` - Android 工具链修复脚本
- `scripts/setup_windows_flutter.ps1` - Windows Flutter 设置脚本
- `scripts/setup_fvm.ps1` / `.bat` - FVM 设置脚本
- `scripts/setup_wsl2_flutter.sh` - WSL2 Flutter 设置脚本
- `scripts/setup_wsl2_dependencies.sh` - WSL2 依赖设置脚本
- `scripts/setup_docker.ps1` / `.sh` / `wsl2.sh` - Docker 设置脚本
- `scripts/quick_start.ps1` - 快速启动脚本

## 保留的核心脚本

以下脚本保留，因为它们提供的是运行时功能，而非环境配置：

- `scripts/deploy.*` - 部署脚本（构建、安装、运行）
- `scripts/version.*` - 版本管理脚本
- `scripts/collect_logs.*` - 日志收集脚本
- `scripts/commit.*` - 提交脚本
- `scripts/*workflow*` - GitHub Actions 工作流管理脚本

## 总结

1. **环境配置应该手动完成**，确保每一步都理解并验证
2. **自动化脚本适合运行时任务**，不适合一次性环境配置
3. **文档比脚本更重要**，清晰的文档能帮助开发者快速配置环境
4. **保持简单**，避免过度自动化导致的问题

## 参考资源

- [Flutter 官方安装指南](https://docs.flutter.dev/get-started/install/windows)
- [Android Studio 安装指南](https://developer.android.com/studio/install)
- [Android SDK Command-line Tools](https://developer.android.com/studio#command-line-tools-only)




