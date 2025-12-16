/// Pipeline 模块导出
/// 
/// 使用方式：
/// ```dart
/// import 'package:svn_auto_merge/pipeline/pipeline.dart';
/// 
/// // 使用全局实例
/// final pipeline = GlobalPipeline.instance;
/// 
/// // 或创建新实例
/// final pipeline = PipelineFacade()..initialize();
/// ```
library;

export 'engine/engine.dart';
export 'executors/executors.dart';
export 'models/models.dart';
export 'pipeline_facade.dart';
export 'widgets/widgets.dart';
