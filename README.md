# SVN 合并助手

一个面向桌面场景的 SVN 合并助手，目标是降低日常分支合并的操作量，并把准备、更新、合并、提交放在一个稳定可视的执行界面里。

## 当前定位

当前版本已经收敛为固定四步执行方式，只保留服务 SVN 合并的内置能力，不再提供通用流程编排、脚本节点或自定义流程编辑。

固定步骤为：`准备 -> 更新 -> 合并 -> 提交`

提交阶段支持针对 `out-of-date` 的有限重试；执行过程中支持在冲突、失败等需要人工处理的场景下暂停，并支持继续、跳过当前 revision、终止任务，以及查看步骤执行状态和日志。应用异常中断后，未完成任务会恢复为暂停状态，等待人工确认后继续。

## 主要能力

- 浏览并筛选 SVN 日志，选择待合并 revision
- 使用任务队列串行执行多个合并任务
- 在执行阶段可视化展示固定四步与当前步骤状态
- 对 `out-of-date` 提交失败进行按任务配置的重试
- 在冲突、失败等需要人工处理的场景下暂停并等待处理
- 使用本地缓存提升日志读取和过滤速度

## 开发使用

1. 安装 Flutter 桌面开发环境
2. 运行 `flutter pub get`
3. 启动应用：`flutter run -d macos`、`flutter run -d windows` 或对应桌面目标
4. 常规校验：`flutter analyze`、`flutter test`

## 配置与文档

- [配置说明](Documents/configuration.md)
- [脚本说明](Documents/scripts.md)
- [版本管理](Documents/development/version-management.md)
- [文档目录](Documents/README.md)
