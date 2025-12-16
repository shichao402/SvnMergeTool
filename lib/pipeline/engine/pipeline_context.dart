import 'dart:convert';

import '../models/stage_result.dart';

/// Pipeline 执行上下文
/// 负责管理变量传递和模板解析
class PipelineContext {
  /// 阶段执行结果（key = stage id）
  final Map<String, StageResult> stageResults;

  /// 用户输入的变量（key = stage id）
  final Map<String, String> userInputs;

  /// 环境变量
  final Map<String, String> env;

  /// 任务参数（如 sourceUrl, targetWc 等）
  final Map<String, dynamic> jobParams;

  PipelineContext({
    Map<String, StageResult>? stageResults,
    Map<String, String>? userInputs,
    Map<String, String>? env,
    Map<String, dynamic>? jobParams,
  })  : stageResults = stageResults ?? {},
        userInputs = userInputs ?? {},
        env = env ?? {},
        jobParams = jobParams ?? {};

  /// 更新阶段结果
  void updateStageResult(StageResult result) {
    stageResults[result.stageId] = result;
    // 如果有用户输入，也保存到 userInputs
    if (result.userInput != null) {
      userInputs[result.stageId] = result.userInput!;
    }
  }

  /// 设置任务参数
  void setJobParam(String key, dynamic value) {
    jobParams[key] = value;
  }

  /// 解析变量引用
  /// 支持的格式：
  /// - ${stages.<stage_id>.output} - 阶段输出
  /// - ${stages.<stage_id>.output.<key>} - JSON 输出的字段
  /// - ${stages.<stage_id>.exitCode} - 退出码
  /// - ${input.<stage_id>} - 用户输入
  /// - ${env.<name>} - 环境变量
  /// - ${job.<param>} - 任务参数
  String resolve(String template) {
    final pattern = RegExp(r'\$\{([^}]+)\}');
    return template.replaceAllMapped(pattern, (match) {
      final expr = match.group(1)!;
      final value = _resolveExpression(expr);
      return value?.toString() ?? '';
    });
  }

  /// 解析单个表达式
  dynamic _resolveExpression(String expr) {
    final parts = expr.split('.');

    if (parts.isEmpty) return null;

    switch (parts[0]) {
      case 'stages':
        return _resolveStagesExpr(parts.sublist(1));
      case 'input':
        return _resolveInputExpr(parts.sublist(1));
      case 'env':
        return _resolveEnvExpr(parts.sublist(1));
      case 'job':
        return _resolveJobExpr(parts.sublist(1));
      default:
        return null;
    }
  }

  /// 解析 stages.xxx 表达式
  dynamic _resolveStagesExpr(List<String> parts) {
    if (parts.isEmpty) return null;

    final stageId = parts[0];
    final result = stageResults[stageId];
    if (result == null) return null;

    if (parts.length == 1) {
      return result.output;
    }

    final field = parts[1];
    switch (field) {
      case 'output':
        if (parts.length == 2) {
          return result.output;
        }
        // 访问 JSON 字段
        final output = result.parsedOutput;
        if (output is Map) {
          return _getNestedValue(output, parts.sublist(2));
        }
        return null;
      case 'exitCode':
        return result.exitCode;
      case 'stdout':
        return result.stdout;
      case 'stderr':
        return result.stderr;
      case 'duration':
        return result.duration.inMilliseconds;
      default:
        return null;
    }
  }

  /// 解析 input.xxx 表达式
  dynamic _resolveInputExpr(List<String> parts) {
    if (parts.isEmpty) return null;
    return userInputs[parts[0]];
  }

  /// 解析 env.xxx 表达式
  dynamic _resolveEnvExpr(List<String> parts) {
    if (parts.isEmpty) return null;
    return env[parts[0]];
  }

  /// 解析 job.xxx 表达式
  dynamic _resolveJobExpr(List<String> parts) {
    if (parts.isEmpty) return null;
    return _getNestedValue(jobParams, parts);
  }

  /// 获取嵌套值
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

  /// 解析 JSON 字符串
  static dynamic parseJson(String jsonStr) {
    try {
      return json.decode(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// 复制上下文
  PipelineContext copy() {
    return PipelineContext(
      stageResults: Map.from(stageResults),
      userInputs: Map.from(userInputs),
      env: Map.from(env),
      jobParams: Map.from(jobParams),
    );
  }

  /// 清空上下文
  void clear() {
    stageResults.clear();
    userInputs.clear();
    // env 和 jobParams 不清空，它们是初始化时设置的
  }
}
