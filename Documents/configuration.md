# 配置说明

## 概述

应用配置文件 `source_urls.json` 只负责两类内容：

- 预置的 SVN 源 URL 列表
- 日志加载相关的基础默认值

合并最大重试次数、预加载停止条件等运行时设置不在这个文件里，它们保存在本地偏好设置中，由应用设置界面维护。

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
    "svn_log_limit": 200,
    "log_page_size": 50
  }
}
```

## 字段说明

### source_urls

预配置的 SVN 源 URL 列表。

- `name`: 显示名称
- `url`: SVN 地址
- `description`: 描述信息，可选
- `enabled`: 是否启用

### settings

日志加载相关默认值。

- `svn_log_limit`: 每次向 SVN 拉取日志时的默认最大条数
- `log_page_size`: 界面日志列表每页显示条数

## 加载顺序

应用按以下顺序加载配置：

1. 用户配置目录中的 `source_urls.json`
2. 应用内置的 `assets/config/source_urls.json`

也就是说，用户配置存在时优先使用用户配置；不存在时回退到打包内置的预置配置。

## 运行时目录结构

应用运行时根目录由 Flutter 的 `getApplicationSupportDirectory()` 决定。当前代码统一使用以下结构：

- `config/source_urls.json`: 用户可编辑配置
- `logs/`: 应用日志目录，当前运行写入 `latest.log`，下次启动时归档为 `app_*.log`
- `queue.json`: 合并任务队列持久化文件
- `cache/`: SVN 日志缓存与文件列表缓存
- `mergeinfo_cache/`: mergeinfo 本地缓存

当前版本直接使用 `<app-support>` 根目录，不再兼容旧版的嵌套运行时目录。

## 用户配置目录

运行时可编辑配置文件位于：

- `<app-support>/config/source_urls.json`

其中 `<app-support>` 的实际值由平台和打包标识决定。常见情况下通常类似：

- macOS: `~/Library/Application Support/com.example.svnautomerge/`
- Windows: `%APPDATA%/SvnAutoMerge/`
- Linux: `~/.local/share/SvnAutoMerge/`

仓库中的 `config/source_urls.json` 主要作为模板文件保留，便于开发和整理默认示例，不是当前运行时的优先加载入口。

## 如何使用

1. 首次启动时可直接使用内置预置配置。
2. 需要自定义源 URL 时，在用户配置目录创建或修改 `source_urls.json`。
3. 可参考仓库内的 `config/source_urls.json` 作为模板。
4. 修改完成后重启应用使配置生效。

## 发布相关

### 内置预置配置

`assets/config/source_urls.json` 会通过 `pubspec.yaml` 打包进应用：

```yaml
flutter:
  assets:
    - assets/config/source_urls.json
```

这个文件的作用是：

- 作为应用首次启动时的兜底配置
- 提供一个稳定的默认示例
- 在用户配置缺失时仍保证应用可用

### 用户配置

真正可编辑、可长期维护的运行时配置位于用户配置目录，不建议把个人使用中的实际 SVN 地址直接写进仓库模板文件。

## 常见问题

### Q: 为什么我修改了仓库里的 `config/source_urls.json`，应用里没有生效？
A: 当前运行时优先读取用户配置目录，不直接读取仓库模板文件。请修改用户配置目录中的 `source_urls.json`。

### Q: 如何恢复到内置默认配置？
A: 删除用户配置目录中的 `source_urls.json`，应用会自动回退到 `assets/config/source_urls.json`。

### Q: 旧版本的队列和缓存目录还会继续使用吗？
A: 不会。当前版本只使用 `getApplicationSupportDirectory()` 根目录下的 `queue.json`、`cache/`、`mergeinfo_cache/`。

### Q: 这个配置文件会被 Git 提交吗？
A: 仓库里的模板文件会被提交；用户配置目录中的运行时配置不会随仓库提交。
