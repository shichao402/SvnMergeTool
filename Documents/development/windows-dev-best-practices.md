---
title: Windows Flutter 开发最佳实践
category: development
created: 2024-12-19
updated: 2026-05-23
author: 开发团队
status: approved
---

# Windows Flutter 开发最佳实践

## 当前结论

这个项目当前更适合采用“简单稳定”的桌面开发方式，不再推荐为它额外引入 FVM、自定义环境初始化脚本或一次性的自动化安装方案。

推荐顺序：

1. WSL2 + 手动安装 Flutter
2. Windows 原生 Flutter

GitHub Codespaces、Docker、FVM 都不是当前仓库的默认开发路径。

## 为什么这样选

Windows 上 Flutter 开发最常见的问题不是业务代码，而是环境复杂度本身：

- PATH、权限、SDK 路径容易混乱
- WSL、PowerShell、CMD 混用后排障成本高
- 多套 Flutter 管理方案并存时，问题会被放大

这个项目本身是桌面 SVN 合并助手，不需要为了环境管理再叠一层工具链复杂度。

## 推荐方案一：WSL2

适用场景：

- 主要在命令行里工作
- 希望开发环境更接近 Linux
- 希望避免 Windows 路径和权限问题

建议步骤：

1. 安装 WSL2 和 Ubuntu。
2. 在 WSL2 内手动安装 Flutter stable。
3. 把 Flutter 加入 `~/.bashrc` 的 PATH。
4. 在项目目录执行 `flutter doctor`、`flutter pub get`。
5. 用 `flutter run -d windows` 或 `./scripts/deploy.sh` 进行桌面调试。

示例：

```bash
sudo apt-get update
sudo apt-get install -y unzip curl git xz-utils zip libglu1-mesa

git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

cd /mnt/<drive>/<path>/SvnAutoMerge
flutter doctor
flutter pub get
flutter run -d windows
```

## 推荐方案二：Windows 原生 Flutter

适用场景：

- 主要在 Windows 桌面下工作
- 需要直接调试 Windows 桌面构建链
- 不想切到 WSL2

建议步骤：

1. 按 Flutter 官方文档安装 Windows 版 Flutter。
2. 使用不含空格和中文的安装路径，例如 `C:/tools/flutter`。
3. 配好 PATH 后运行 `flutter doctor`。
4. 在项目目录执行 `flutter pub get`、`flutter run -d windows`。

示例：

```powershell
flutter doctor
flutter pub get
flutter run -d windows
scripts\deploy.bat
```

## 日常命令

通用命令：

```bash
flutter pub get
flutter analyze
flutter test
```

启动应用：

```bash
flutter run -d windows
./scripts/deploy.sh
```

Windows 下：

```powershell
flutter run -d windows
scripts\deploy.bat
scripts\collect_logs.bat
scripts\version.bat get app
```

## 排障建议

### 1. 先确认只有一套 Flutter 在生效

优先检查：

```bash
which flutter
flutter --version
```

或在 Windows：

```powershell
where flutter
flutter --version
```

如果输出路径和预期不一致，先修正 PATH，再继续排障。

### 2. 避免中文和空格路径

建议项目、Flutter SDK、构建输出目录都使用纯英文路径。这样可以减少命令行、脚本和工具链兼容问题。

### 3. 不要依赖仓库里不存在的环境安装脚本

当前仓库保留的是运行和维护脚本：

- `scripts/deploy.*`
- `scripts/collect_logs.*`
- `scripts/version.*`
- `scripts/verify_build.*`

不再提供旧版的 FVM、WSL2 一键安装、GitHub Actions 辅助之类实验脚本。

### 4. 出问题时先跑最小检查集

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
```

如果这四步都正常，再去看具体的桌面运行或打包问题。

## 相关资源

- [Flutter Windows 安装指南](https://docs.flutter.dev/get-started/install/windows)
- [WSL2 安装指南](https://learn.microsoft.com/zh-cn/windows/wsl/install)
- [脚本说明](../scripts.md)
- [WSL2 设置指南](wsl2-setup-guide.md)
