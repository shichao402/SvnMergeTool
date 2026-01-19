import 'dart:async';

import '../../models/merge_job.dart';
import '../../services/svn_service.dart';
import 'node_output.dart';

/// 用户输入请求回调
typedef UserInputCallback = Future<String?> Function({
  required String prompt,
  String? label,
  String? defaultValue,
  String? validationPattern,
  String? validationMessage,
});

/// 日志回调
typedef LogCallback = void Function(String message, {LogLevel level});

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 执行上下文
///
/// 提供执行器访问：
/// - 当前任务信息
/// - SVN 服务
/// - 变量存储
/// - 用户输入请求
/// - 日志记录
/// - 取消检查
class ExecutionContext {
  /// 当前任务
  final MergeJob job;

  /// SVN 服务
  final SvnService svnService;

  /// 工作目录
  final String workDir;

  /// 变量存储（节点间数据传递）
  final Map<String, dynamic> _variables = {};

  /// 节点执行结果
  final Map<String, NodeOutput> _nodeResults = {};

  /// 用户输入回调
  final UserInputCallback? _userInputCallback;

  /// 日志回调
  final LogCallback? _logCallback;

  /// 取消标志
  bool _isCancelled = false;

  /// 暂停标志
  bool _isPaused = false;

  /// 暂停恢复 Completer
  Completer<void>? _pauseCompleter;

  /// 当前 revision 是否已被合并（由 merge 节点设置）
  bool _revisionMerged = false;

  ExecutionContext({
    required this.job,
    required this.svnService,
    required this.workDir,
    UserInputCallback? onUserInput,
    LogCallback? onLog,
  })  : _userInputCallback = onUserInput,
        _logCallback = onLog;

  // ==================== 状态检查 ====================

  /// 是否已取消
  bool get isCancelled => _isCancelled;

  /// 是否已暂停
  bool get isPaused => _isPaused;

  /// 当前 revision 是否已被合并
  bool get revisionMerged => _revisionMerged;

  /// 标记当前 revision 已被合并（由 merge 节点调用）
  void markRevisionMerged() {
    _revisionMerged = true;
  }

  /// 取消执行
  void cancel() {
    _isCancelled = true;
    // 如果正在暂停，也要恢复以便退出
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
  }

  /// 暂停执行
  void pause() {
    if (!_isPaused) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
    }
  }

  /// 恢复执行
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _pauseCompleter = null;
    }
  }

  /// 检查暂停状态，如果暂停则等待恢复
  Future<void> checkPause() async {
    if (_isPaused && _pauseCompleter != null) {
      await _pauseCompleter!.future;
    }
  }

  /// 检查取消状态，如果取消则抛出异常
  void checkCancelled() {
    if (_isCancelled) {
      throw ExecutionCancelledException();
    }
  }

  // ==================== 变量操作 ====================

  /// 设置变量
  void setVariable(String key, dynamic value) {
    _variables[key] = value;
  }

  /// 获取变量
  T? getVariable<T>(String key) {
    final value = _variables[key];
    if (value is T) return value;
    return null;
  }

  /// 检查变量是否存在
  bool hasVariable(String key) {
    return _variables.containsKey(key);
  }

  /// 获取所有变量
  Map<String, dynamic> get variables => Map.unmodifiable(_variables);

  // ==================== 节点结果 ====================

  /// 保存节点执行结果
  void setNodeResult(String nodeId, NodeOutput output) {
    _nodeResults[nodeId] = output;
  }

  /// 获取节点执行结果
  NodeOutput? getNodeResult(String nodeId) {
    return _nodeResults[nodeId];
  }

  /// 获取所有节点结果
  Map<String, NodeOutput> get nodeResults => Map.unmodifiable(_nodeResults);

  // ==================== 用户输入 ====================

  /// 请求用户输入
  Future<String?> requestUserInput({
    required String prompt,
    String? label,
    String? defaultValue,
    String? validationPattern,
    String? validationMessage,
  }) async {
    if (_userInputCallback == null) {
      throw StateError('未设置用户输入回调');
    }

    // 检查暂停和取消
    await checkPause();
    checkCancelled();

    return _userInputCallback(
      prompt: prompt,
      label: label,
      defaultValue: defaultValue,
      validationPattern: validationPattern,
      validationMessage: validationMessage,
    );
  }

  // ==================== 日志 ====================

  /// 记录日志
  void log(String message, {LogLevel level = LogLevel.info}) {
    _logCallback?.call(message, level: level);
  }

  /// 记录调试日志
  void debug(String message) => log(message, level: LogLevel.debug);

  /// 记录信息日志
  void info(String message) => log(message, level: LogLevel.info);

  /// 记录警告日志
  void warning(String message) => log(message, level: LogLevel.warning);

  /// 记录错误日志
  void error(String message) => log(message, level: LogLevel.error);

  // ==================== 模板解析 ====================

  /// 解析模板字符串
  ///
  /// 支持的变量：
  /// - ${var.xxx} - 上下文变量
  /// - ${node.xxx.yyy} - 节点输出数据
  /// - ${job.xxx} - 任务属性
  /// - ${config.xxx} - 当前节点配置
  String resolveTemplate(String template, {Map<String, dynamic>? config}) {
    final pattern = RegExp(r'\$\{([^}]+)\}');
    return template.replaceAllMapped(pattern, (match) {
      final expr = match.group(1)!;
      final value = _resolveExpression(expr, config: config);
      return value?.toString() ?? '';
    });
  }

  dynamic _resolveExpression(String expr, {Map<String, dynamic>? config}) {
    final parts = expr.split('.');
    if (parts.isEmpty) return null;

    switch (parts[0]) {
      case 'var':
        return _getNestedValue(_variables, parts.sublist(1));
      case 'node':
        if (parts.length < 2) return null;
        final nodeId = parts[1];
        final output = _nodeResults[nodeId];
        if (output == null) return null;
        if (parts.length == 2) return output.data;
        return _getNestedValue(output.data, parts.sublist(2));
      case 'job':
        return _resolveJobExpr(parts.sublist(1));
      case 'config':
        if (config == null) return null;
        return _getNestedValue(config, parts.sublist(1));
      default:
        return null;
    }
  }

  dynamic _resolveJobExpr(List<String> parts) {
    if (parts.isEmpty) return null;
    final jobMap = {
      'jobId': job.jobId,
      'sourceUrl': job.sourceUrl,
      'targetWc': job.targetWc,
      'currentRevision': job.currentRevision,
      'revisions': job.revisions,
      'completedIndex': job.completedIndex,
    };
    return _getNestedValue(jobMap, parts);
  }

  dynamic _getNestedValue(Map<dynamic, dynamic> map, List<String> keys) {
    dynamic current = map;
    for (final key in keys) {
      if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  // ==================== 重置 ====================

  /// 重置上下文（保留 job 和 svnService）
  void reset() {
    _variables.clear();
    _nodeResults.clear();
    _isCancelled = false;
    _isPaused = false;
    _pauseCompleter = null;
    _revisionMerged = false;
  }
}

/// 执行取消异常
class ExecutionCancelledException implements Exception {
  final String message;
  ExecutionCancelledException([this.message = '执行已取消']);

  @override
  String toString() => 'ExecutionCancelledException: $message';
}
