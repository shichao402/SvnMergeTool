# SVN 自动合并工具 (Flutter 版本)

一个跨平台的 SVN 自动合并桌面工具，支持自动重试提交、任务队列、插件扩展等功能。

## 文档

详细的文档请查看 [Documents/](Documents/) 目录：

- [配置说明](Documents/configuration.md) - 配置文件使用和部署说明
- [脚本说明](Documents/scripts.md) - 部署和日志收集脚本使用说明

## 快速开始

1. 配置 SVN 源 URL：编辑 `config/source_urls.json`
2. 部署应用：运行 `scripts/deploy.sh`（macOS/Linux）或 `scripts/deploy.bat`（Windows）
3. 查看日志：运行 `scripts/collect_logs.sh`（macOS/Linux）或 `scripts/collect_logs.bat`（Windows）

更多信息请参考 [文档目录](Documents/README.md)。
