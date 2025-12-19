import 'package:flutter/material.dart';

import '../../../services/working_copy_manager.dart';
import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 提交阶段执行器
///
/// 执行 svn commit，提交工作副本的修改。
class CommitExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final wcManager = WorkingCopyManager();
    final targetWc = context.job.targetWc;

    if (targetWc.isEmpty) {
      return NodeOutput.failure(message: '缺少目标工作副本路径');
    }

    // 构建提交信息
    final message = _buildCommitMessage(config, context);

    try {
      context.info('开始提交...');
      context.info('提交信息: $message');

      await wcManager.commit(targetWc, message);

      context.info('提交成功');
      return NodeOutput.success(
        data: {'message': message},
        message: '提交成功',
      );
    } catch (e) {
      final errorStr = e.toString();
      context.error('提交失败: $errorStr');

      // 检查是否是 out-of-date 错误
      if (_isOutOfDate(errorStr)) {
        return NodeOutput.port(
          'out_of_date',
          data: {'error': errorStr},
          message: '工作副本过期，需要更新',
          isSuccess: false,
        );
      }

      return NodeOutput.failure(message: errorStr);
    }
  }

  /// 构建提交信息
  static String _buildCommitMessage(
    Map<String, dynamic> config,
    ExecutionContext context,
  ) {
    // 如果有模板，使用模板
    final template = config['messageTemplate'] as String?;
    if (template != null && template.isNotEmpty) {
      return context.resolveTemplate(template, config: config);
    }

    // 默认提交信息
    final sourceUrl = context.job.sourceUrl;
    final revision = context.job.currentRevision;

    if (revision != null && revision > 0) {
      return '[Merge] r$revision from $sourceUrl';
    } else {
      return '[Merge] from $sourceUrl';
    }
  }

  /// 检查是否是 out-of-date 错误
  static bool _isOutOfDate(String output) {
    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('out-of-date') ||
        lowerOutput.contains('out of date');
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'commit',
        name: '提交',
        description: '提交工作副本的修改',
        icon: Icons.upload,
        color: Colors.purple,
        category: 'SVN 操作',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec.success,
          PortSpec(id: 'out_of_date', name: '过期', role: PortRole.error),
          PortSpec.failure,
        ],
        params: const [
          ParamSpec(
            key: 'messageTemplate',
            label: '提交信息模板',
            type: ParamType.text,
            description: '支持变量: \${job.sourceUrl}, \${job.currentRevision}',
            placeholder: '[Merge] r\${job.currentRevision} from \${job.sourceUrl}',
          ),
        ],
        executor: execute,
      );
}
