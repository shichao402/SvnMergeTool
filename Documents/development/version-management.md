# 版本管理说明

## 概述

项目使用统一的版本管理方式，所有版本号操作都以根目录的 `VERSION.yaml` 为单一数据源，再由脚本同步到 `pubspec.yaml`。

## 版本号格式

版本号格式为：`主版本号.次版本号.修订号+构建号`

示例：`1.0.7+13`

- `1.0.7`：对外版本号
- `13`：构建号

## 版本管理脚本

### macOS / Linux

```bash
./scripts/version.sh get app
./scripts/version.sh set app 1.0.7+13
./scripts/version.sh bump app patch
./scripts/version.sh sync app
```

### Windows

```batch
scripts\version.bat get app
scripts\version.bat set app 1.0.7+13
scripts\version.bat bump app patch
scripts\version.bat sync app
```

## 常见操作

获取当前版本：

```bash
./scripts/version.sh get app
```

设置明确版本：

```bash
./scripts/version.sh set app 1.0.7+13
```

递增 patch：

```bash
./scripts/version.sh bump app patch
```

同步到 `pubspec.yaml`：

```bash
./scripts/version.sh sync app
```

## 构建前同步

构建脚本会在构建前自动执行版本同步：

- `scripts/deploy.sh`
- `scripts/deploy.bat`
- `scripts/deploy.ps1`

因此日常开发通常不需要手动改 `pubspec.yaml` 里的版本字段。

## 代码中读取版本

运行时可通过 [version_service.dart](../../lib/services/version_service.dart) 读取版本信息。

```dart
import 'package:svn_auto_merge/services/version_service.dart';

final version = await versionService.getVersion();
final versionNumber = await versionService.getVersionNumber();
final buildNumber = await versionService.getBuildNumber();
```

## 当前发布约定

当前仓库仍保留 `.github/workflows/` 下的构建与发布流程，但它们属于发布基础设施，不再对应之前那套实验性 workflow 辅助脚本。

实际发布时建议：

1. 先用版本脚本确认或更新版本号。
2. 本地执行 `flutter analyze` 和 `flutter test`。
3. 需要桌面包时使用部署脚本完成本地构建验证。
4. 再按仓库现有的 GitHub Actions workflow 触发构建或发布。
