import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/stage_config.dart';
import '../models/stage_result.dart';
import '../models/stage_status.dart';
import 'stage_data.dart';

/// 图执行器状态
enum GraphExecutorStatus {
  /// 空闲
  idle,
  /// 运行中
  running,
  /// 暂停（等待用户输入）
  paused,
  /// 已完成
  completed,
  /// 失败
  failed,
  /// 已取消
  cancelled,
}

/// 轻量级图执行器
/// 
/// 基于 vyuh_node_flow 的 NodeGraph 执行流程，
/// 通过 Connection 定义的连接关系决定执行顺序和分支。
class GraphExecutor {
  /// 执行器注册表
  final StageExecutorRegistry registry;

  /// 执行上下文
  final PipelineContext context;

  /// 日志回调
  final void Function(String message)? onLog;

  /// 状态变化回调
  final void Function(GraphExecutorStatus status)? onStatusChange;

  /// 需要用户输入时的回调
  /// 返回用户输入的值，返回 null 表示取消
  final Future<String?> Function(Node<StageData> node)? onNeedUserInput;

  // ==================== 运行时状态 ====================

  /// 当前状态
  final Observable<GraphExecutorStatus> _status = Observable(GraphExecutorStatus.idle);
  GraphExecutorStatus get status => _status.value;

  /// 当前执行的节点
  final Observable<Node<StageData>?> _currentNode = Observable(null);
  Node<StageData>? get currentNode => _currentNode.value;

  /// 是否已取消
  bool _cancelled = false;

  /// 暂停 Completer（用于等待用户输入）
  Completer<String?>? _pauseCompleter;

  GraphExecutor({
    required this.registry,
    required this.context,
    this.onLog,
    this.onStatusChange,
    this.onNeedUserInput,
  });

  /// 执行图
  /// 
  /// [controller] NodeFlowController，包含节点和连接
  /// [startNodeId] 起始节点 ID，如果为 null 则自动查找入度为 0 的节点
  Future<bool> execute(
    NodeFlowController<StageData> controller, {
    String? startNodeId,
  }) async {
    _cancelled = false;
    _setStatus(GraphExecutorStatus.running);

    try {
      // 重置所有节点状态
      _resetAllNodes(controller);

      // 找到起始节点
      var currentNode = startNodeId != null
          ? controller.nodes[startNodeId]
          : _findStartNode(controller);

      if (currentNode == null) {
        _log('错误：找不到起始节点');
        _setStatus(GraphExecutorStatus.failed);
        return false;
      }

      // 执行循环
      while (currentNode != null && !_cancelled) {
        runInAction(() => _currentNode.value = currentNode);

        final data = currentNode.data;
        if (data == null) {
          _log('错误：节点数据为空');
          currentNode = _getNextNode(controller, currentNode.id, 'success');
          continue;
        }

        // 检查节点是否启用
        if (!data.enabled) {
          _log('跳过禁用的节点: ${data.name}');
          data.status = StageStatus.skipped;
          currentNode = _getNextNode(controller, currentNode.id, 'success');
          continue;
        }

        // 执行节点
        final result = await _executeNode(currentNode);

        if (_cancelled) {
          _setStatus(GraphExecutorStatus.cancelled);
          return false;
        }

        // 根据执行结果选择下一个节点
        if (result.needsPause) {
          // 需要暂停等待用户输入
          _setStatus(GraphExecutorStatus.paused);
          data.status = StageStatus.paused;

          final userInput = await _waitForUserInput(currentNode);
          if (userInput == null) {
            // 用户取消
            _setStatus(GraphExecutorStatus.cancelled);
            return false;
          }

          // 保存用户输入
          data.userInput = userInput;
          context.userInputs[currentNode.id] = userInput;

          // 继续执行
          _setStatus(GraphExecutorStatus.running);
          data.status = StageStatus.completed;
          currentNode = _getNextNode(controller, currentNode.id, 'success');
        } else if (result.success) {
          data.status = StageStatus.completed;
          currentNode = _getNextNode(controller, currentNode.id, 'success');
        } else {
          data.status = StageStatus.failed;
          data.errorMessage = result.error;

          // 查找失败分支
          final failureNode = _getNextNode(controller, currentNode.id, 'failure');
          if (failureNode != null) {
            // 有失败分支，继续执行
            _log('执行失败分支: ${failureNode.data?.name ?? failureNode.id}');
            currentNode = failureNode;
          } else {
            // 没有失败分支，流程失败
            _setStatus(GraphExecutorStatus.failed);
            return false;
          }
        }
      }

      if (_cancelled) {
        _setStatus(GraphExecutorStatus.cancelled);
        return false;
      }

      _setStatus(GraphExecutorStatus.completed);
      return true;
    } catch (e, stack) {
      _log('执行异常: $e\n$stack');
      _setStatus(GraphExecutorStatus.failed);
      return false;
    } finally {
      runInAction(() => _currentNode.value = null);
    }
  }

  /// 取消执行
  void cancel() {
    _cancelled = true;
    _pauseCompleter?.complete(null);
  }

  /// 提供用户输入（用于恢复暂停的执行）
  void provideUserInput(String input) {
    _pauseCompleter?.complete(input);
  }

  // ==================== 私有方法 ====================

  void _setStatus(GraphExecutorStatus newStatus) {
    runInAction(() => _status.value = newStatus);
    onStatusChange?.call(newStatus);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GraphExecutor] $message');
    }
    onLog?.call(message);
  }

  /// 重置所有节点状态
  void _resetAllNodes(NodeFlowController<StageData> controller) {
    for (final node in controller.nodes.values) {
      node.data?.reset();
    }
  }

  /// 查找起始节点（入度为 0 的节点）
  Node<StageData>? _findStartNode(NodeFlowController<StageData> controller) {
    final targetNodeIds = controller.connections
        .map((c) => c.targetNodeId)
        .toSet();

    for (final node in controller.nodes.values) {
      if (!targetNodeIds.contains(node.id)) {
        return node;
      }
    }

    // 如果没有入度为 0 的节点，返回第一个
    return controller.nodes.isNotEmpty ? controller.nodes.values.first : null;
  }

  /// 获取下一个节点
  Node<StageData>? _getNextNode(
    NodeFlowController<StageData> controller,
    String nodeId,
    String portId,
  ) {
    // 查找匹配的连接
    Connection? connection;
    for (final c in controller.connections) {
      if (c.sourceNodeId == nodeId && c.sourcePortId == portId) {
        connection = c;
        break;
      }
    }

    if (connection == null) return null;

    // 查找目标节点
    return controller.nodes[connection.targetNodeId];
  }

  /// 执行单个节点
  Future<ExecutionResult> _executeNode(Node<StageData> node) async {
    final data = node.data;
    if (data == null) {
      return ExecutionResult.failure('节点数据为空');
    }
    
    _log('开始执行: ${data.name} (${data.type.name})');

    // 更新状态
    data.status = StageStatus.running;
    data.startTime = DateTime.now();
    data.progress = 0.0;

    try {
      // 获取执行器
      final executor = registry.get(data.type);
      if (executor == null) {
        return ExecutionResult.failure('未找到执行器: ${data.type.name}');
      }

      // 转换为旧的 StageConfig（临时兼容）
      final config = _toStageConfig(node);

      // 执行
      final result = await executor.execute(
        config,
        context,
        onLog: (msg) {
          _log('[${data.name}] $msg');
          data.output = '${data.output ?? ''}$msg\n';
        },
      );

      // 更新状态
      data.endTime = DateTime.now();
      data.progress = 1.0;

      // 保存结果到上下文
      if (result.success || !result.needsPause) {
        context.updateStageResult(StageResult(
          stageId: node.id,
          status: result.success ? StageStatus.completed : StageStatus.failed,
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
          parsedOutput: result.parsedOutput,
          error: result.error,
          userInput: result.userInput,
          startTime: data.startTime,
          endTime: data.endTime,
        ));
      }

      _log('执行完成: ${data.name}, 成功=${result.success}');
      return result;
    } catch (e, stack) {
      data.endTime = DateTime.now();
      data.errorMessage = e.toString();
      _log('执行异常: ${data.name}, $e\n$stack');
      return ExecutionResult.failure(e.toString());
    }
  }

  /// 等待用户输入
  Future<String?> _waitForUserInput(Node<StageData> node) async {
    if (onNeedUserInput != null) {
      return onNeedUserInput!(node);
    }

    // 使用 Completer 等待
    _pauseCompleter = Completer<String?>();
    return _pauseCompleter!.future;
  }

  /// 临时兼容：转换为旧的 StageConfig
  /// TODO: 后续直接让执行器使用 StageData
  StageConfig _toStageConfig(Node<StageData> node) {
    final data = node.data!;
    return StageConfig(
      id: node.id,
      type: data.type,
      name: data.name,
      enabled: data.enabled,
      script: data.scriptPath,
      scriptArgs: data.scriptArgs,
      commitMessageTemplate: data.commitMessageTemplate,
      reviewInput: data.reviewInput != null
          ? ReviewInputConfig(
              label: data.reviewInput!.label,
              hint: data.reviewInput!.prompt,
              validationRegex: data.reviewInput!.validationPattern,
              required: data.reviewInput!.required,
            )
          : null,
    );
  }
}

// 删除 _LegacyStageConfig，直接使用真正的 StageConfig
