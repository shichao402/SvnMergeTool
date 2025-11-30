# 版本管理说明

## 概述

本项目使用统一的版本管理系统，所有版本号操作都基于 `VERSION.yaml` 文件。

## 版本号格式

版本号使用语义化版本号格式：`主版本号.次版本号.修订号+构建号`

**示例：** `1.0.7+13`
- `1.0.7` - 版本号（主版本.次版本.修订号）
- `+13` - 构建号

## 版本号管理

### VERSION.yaml 文件

版本号统一存储在项目根目录的 `VERSION.yaml` 文件中，作为单一数据源。

### 版本管理脚本

项目提供了跨平台的版本管理脚本：

**macOS/Linux:**
```bash
./scripts/version.sh get app          # 获取版本号
./scripts/version.sh set app 1.0.7+13 # 设置版本号
./scripts/version.sh bump app patch   # 递增修订号
./scripts/version.sh sync app         # 同步到 pubspec.yaml
```

**Windows:**
```batch
scripts\version.bat get app
scripts\version.bat set app 1.0.7+13
scripts\version.bat bump app patch
scripts\version.bat sync app
```

### 自动同步

构建脚本（`scripts/deploy.sh` 和 `scripts/deploy.bat`）会在构建前自动同步版本号到 `pubspec.yaml`。

## 版本服务

在代码中使用版本服务读取版本号：

```dart
import 'package:svn_merge_tool/services/version_service.dart';

final versionService = VersionService();
final version = await versionService.getVersion();           // "1.0.7+13"
final versionNumber = await versionService.getVersionNumber(); // "1.0.7"
final buildNumber = await versionService.getBuildNumber();     // 13
```

## CI/CD 集成

### 构建流程

1. 推送 `build*` 标签（如 `build1.0.7`）触发构建
2. 构建所有平台
3. 构建完成后自动递增构建号

### 发布流程

1. 手动触发 release workflow
2. 查找对应的构建产物
3. 创建 GitHub Release
4. 生成更新配置文件
5. 推送到 UpdateConfig Release

## 版本号更新建议

- **主版本号（Major）** - 不兼容的 API 更改、重大功能变更
- **次版本号（Minor）** - 向后兼容的功能添加、新功能
- **修订号（Patch）** - 向后兼容的 bug 修复、小改进
- **构建号（Build）** - 每次构建递增，用于区分同一版本的多次构建







