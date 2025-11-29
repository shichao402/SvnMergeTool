# 配置说明

## 概述

应用配置文件 `source_urls.json` 包含预配置的 SVN 源 URL 和应用设置。

## 配置结构

```json
{
  "version": "1.0.0",
  "description": "SVN 源 URL 配置文件",
  "source_urls": [
    {
      "name": "项目名称",
      "url": "https://svn.example.com/repos/project/trunk",
      "description": "描述信息（可选）",
      "enabled": true
    }
  ],
  "settings": {
    "auto_load_history": true,
    "max_history_items": 10,
    "default_max_retries": 5,
    "auto_load_logs_on_startup": false,
    "svn_log_limit": 200
  }
}
```

## 字段说明

### source_urls

预配置的 SVN 源 URL 列表。

- `name`: 显示名称
- `url`: SVN URL
- `description`: 描述信息（可选）
- `enabled`: 是否启用（true/false）

### settings

应用设置。

- `auto_load_history`: 是否自动加载历史记录
- `max_history_items`: 最大历史记录数量
- `default_max_retries`: 默认最大重试次数
- `auto_load_logs_on_startup`: 启动时是否自动加载日志
- `svn_log_limit`: SVN 日志获取的默认条数限制（默认 200）

## 配置文件加载机制

### 加载顺序

应用按以下顺序尝试加载配置：

1. **优先从 assets 加载**（打包在应用内）
   - 路径：`assets/config/source_urls.json`
   - 特点：只读，打包后无法修改
   - 用途：提供默认配置

2. **从外部文件加载**（可修改）
   - 开发环境：`项目根目录/config/source_urls.json`
   - 打包环境：`可执行文件所在目录/config/source_urls.json`
   - 特点：可读写，用户可以修改
   - 用途：用户自定义配置

### 配置目录查找逻辑

#### 开发环境

1. 从可执行文件目录向上查找
2. 找到包含 `pubspec.yaml` 和 `config/` 的目录
3. 使用该目录下的 `config/` 目录

#### 打包环境

**macOS:**
- 优先：`.app/Contents/Resources/config/`
- 备用：`.app/Contents/MacOS/config/`

**Windows/Linux:**
- 可执行文件所在目录的 `config/` 子目录

## 配置保存

应用可以通过 UI 或代码保存配置：

```dart
final configService = ConfigService();
final config = await configService.getConfig();
// 修改 config...
await configService.saveConfig(config);
```

保存位置：
- 开发环境：`项目根目录/config/source_urls.json`
- 打包环境：`可执行文件所在目录/config/source_urls.json`

## 如何使用

1. 编辑 `source_urls.json` 文件
2. 添加或修改 `source_urls` 列表中的 URL
3. 根据需要调整 `settings` 中的设置
4. 重启应用使配置生效

## 部署相关

### 开发环境

在开发环境中，应用会从项目根目录的 `config/source_urls.json` 加载配置：

```
项目根目录/
  ├── config/
  │   └── source_urls.json  ← 开发环境使用此文件
  ├── assets/
  │   └── config/
  │       └── source_urls.json  ← 默认配置（打包时使用）
  └── lib/
```

**加载优先级：**
1. 优先从 `assets/config/source_urls.json` 加载（打包在应用内）
2. 如果失败，从 `config/source_urls.json` 加载（开发环境）

### 打包环境

在打包后的应用中，配置文件位置取决于平台：

#### macOS
```
应用.app/
  └── Contents/
      ├── MacOS/
      │   └── SvnMergeTool  ← 可执行文件
      └── Resources/
          └── config/
              └── source_urls.json  ← 配置文件位置
```

#### Windows
```
应用目录/
  ├── SvnMergeTool.exe  ← 可执行文件
  └── config/
      └── source_urls.json  ← 配置文件位置
```

#### Linux
```
应用目录/
  ├── SvnMergeTool  ← 可执行文件
  └── config/
      └── source_urls.json  ← 配置文件位置
```

**加载优先级：**
1. 优先从 `assets/config/source_urls.json` 加载（打包在应用内）
2. 如果失败，从可执行文件所在目录的 `config/source_urls.json` 加载

### 配置文件跟随发布

#### 自动打包（assets/config/）

`assets/config/source_urls.json` 会通过 `pubspec.yaml` 自动打包到应用内：

```yaml
flutter:
  assets:
    - assets/config/source_urls.json
```

这个文件会：
- ✅ 自动包含在应用包中
- ✅ 只读（打包后无法修改）
- ✅ 作为默认配置使用

#### 手动复制（config/）

`config/source_urls.json` 需要手动复制到构建输出目录，以便用户可以修改。

**构建脚本会自动执行：**

部署脚本（`scripts/deploy.sh` 或 `scripts/deploy.bat`）会自动复制配置文件到构建输出目录。

### 配置文件修改

#### 开发环境

直接编辑 `config/source_urls.json`，重启应用即可生效。

#### 打包环境

1. 找到应用所在目录
2. 编辑 `config/source_urls.json`
3. 重启应用

**注意：** 如果 `config/source_urls.json` 不存在，应用会使用 `assets/config/source_urls.json` 中的默认配置。

### 最佳实践

1. **开发时**：使用 `config/source_urls.json` 进行配置
2. **打包时**：确保 `assets/config/source_urls.json` 包含合理的默认配置
3. **发布时**：构建脚本应该复制 `config/source_urls.json` 到构建输出
4. **用户使用**：用户可以修改打包后的 `config/source_urls.json` 来自定义配置

## 常见问题

### Q: 修改配置后不生效？
A: 需要重启应用，配置在启动时加载。

### Q: 打包后找不到配置文件？
A: 确保构建脚本已复制 `config/` 目录到构建输出。部署脚本会自动处理。

### Q: 如何重置为默认配置？
A: 删除 `config/source_urls.json`，应用会使用 `assets/config/source_urls.json` 中的默认配置。

### Q: 配置文件会被 Git 提交吗？
A: 是的，`config/source_urls.json` 会被提交（见 `.gitignore` 注释）。建议使用模板配置，不包含敏感信息。

## 注意事项

- JSON 文件必须符合标准格式，注意逗号和引号
- URL 必须是有效的 SVN 地址
- 修改配置文件后需要重启应用
- 建议备份原配置文件后再修改

