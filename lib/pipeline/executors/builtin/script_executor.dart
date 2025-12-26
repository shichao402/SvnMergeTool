import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// Script 节点执行器
///
/// 允许用户通过外部 Python 脚本实现自定义功能。
/// 脚本会接收以下参数：
/// - input: 上游节点输出的数据 (JSON)
/// - var: 流程变量 (JSON)
/// - job: 任务上下文 (JSON)
///
/// 脚本应输出 JSON 格式的结果到 stdout。
class ScriptExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final scriptPath = config['scriptPath'] as String? ?? '';
    final entryFunction = config['entryFunction'] as String? ?? 'main';
    final timeout = (config['timeout'] as num?)?.toInt() ?? 300;

    if (scriptPath.isEmpty) {
      context.error('未指定脚本路径');
      return NodeOutput.failure(message: '未指定脚本路径');
    }

    // 检查脚本文件是否存在
    final scriptFile = File(scriptPath);
    if (!await scriptFile.exists()) {
      context.error('脚本文件不存在: $scriptPath');
      return NodeOutput.failure(message: '脚本文件不存在: $scriptPath');
    }

    context.info('执行脚本: $scriptPath');
    context.debug('入口函数: $entryFunction');

    // 构建传递给脚本的数据
    final scriptInput = {
      'input': input,
      'var': context.variables,
      'job': _buildJobContext(context),
    };

    final inputJson = jsonEncode(scriptInput);
    context.debug('脚本输入: $inputJson');

    try {
      // 创建 Python 包装脚本来调用用户脚本
      final wrapperScript = _buildWrapperScript(scriptPath, entryFunction);

      final result = await Process.run(
        'python3',
        ['-c', wrapperScript],
        environment: {
          'SCRIPT_INPUT': inputJson,
        },
        workingDirectory: scriptFile.parent.path,
      ).timeout(Duration(seconds: timeout));

      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      final exitCode = result.exitCode;

      // 记录脚本输出（包括 print 语句）
      if (stdout.isNotEmpty) {
        context.debug('脚本 stdout:\n$stdout');
      }
      if (stderr.isNotEmpty) {
        context.warning('脚本 stderr:\n$stderr');
      }
      context.debug('脚本退出码: $exitCode');

      if (exitCode != 0) {
        context.error('脚本执行失败 (exit code: $exitCode)');
        context.error(stderr.isNotEmpty ? stderr : stdout);
        return NodeOutput.failure(
          message: stderr.isNotEmpty ? stderr : '脚本执行失败 (exit code: $exitCode)',
          data: {
            'exitCode': exitCode,
            'stdout': stdout,
            'stderr': stderr,
          },
        );
      }

      // 解析脚本输出
      final output = _parseScriptOutput(stdout, context);

      // 提取端口和数据
      final port = output['port'] as String? ?? 'success';
      final data = output['data'] as Map<String, dynamic>? ?? {};
      final message = output['message'] as String? ?? '脚本执行成功';
      final isSuccess = output['isSuccess'] as bool? ?? true;

      // 如果脚本设置了变量，更新到上下文
      final setVars = output['setVariables'] as Map<String, dynamic>?;
      if (setVars != null && setVars.isNotEmpty) {
        context.info('脚本设置了 ${setVars.length} 个变量');
        for (final entry in setVars.entries) {
          context.setVariable(entry.key, entry.value);
          context.debug('  ${entry.key} = ${entry.value}');
        }
      }

      context.info('脚本执行完成: $message');
      context.debug('输出端口: $port, 数据: $data');

      return NodeOutput(
        port: port,
        data: data,
        message: message,
        isSuccess: isSuccess,
      );
    } on ProcessException catch (e) {
      context.error('无法执行 Python: ${e.message}');
      return NodeOutput.failure(message: '无法执行 Python: ${e.message}');
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        context.error('脚本执行超时 ($timeout 秒)');
        return NodeOutput.failure(message: '脚本执行超时 ($timeout 秒)');
      }
      context.error('脚本执行异常: $e');
      return NodeOutput.failure(message: e.toString());
    }
  }

  /// 构建任务上下文
  static Map<String, dynamic> _buildJobContext(ExecutionContext context) {
    final job = context.job;
    return {
      'jobId': job.jobId,
      'sourceUrl': job.sourceUrl,
      'targetWc': job.targetWc,
      'currentRevision': job.currentRevision,
      'revisions': job.revisions,
      'completedIndex': job.completedIndex,
      'workDir': context.workDir,
    };
  }

  /// 构建 Python 包装脚本
  static String _buildWrapperScript(String scriptPath, String entryFunction) {
    // 转义路径中的特殊字符
    final escapedPath = scriptPath.replaceAll("'", "\\'");

    return '''
import os
import sys
import json
import importlib.util

# 获取输入数据
input_json = os.environ.get('SCRIPT_INPUT', '{}')
script_input = json.loads(input_json)

# 加载用户脚本
spec = importlib.util.spec_from_file_location("user_script", '$escapedPath')
user_module = importlib.util.module_from_spec(spec)
sys.modules["user_script"] = user_module
spec.loader.exec_module(user_module)

# 调用入口函数
entry_func = getattr(user_module, '$entryFunction', None)
if entry_func is None:
    print(json.dumps({
        'port': 'failure',
        'message': '入口函数 $entryFunction 不存在',
        'isSuccess': False
    }))
    sys.exit(0)

# 执行并获取结果
try:
    result = entry_func(
        input=script_input.get('input', {}),
        var=script_input.get('var', {}),
        job=script_input.get('job', {})
    )
    
    # 确保结果是字典
    if result is None:
        result = {'port': 'success', 'message': '执行完成'}
    elif not isinstance(result, dict):
        result = {'port': 'success', 'data': {'result': result}}
    
    # 输出 JSON 结果
    print(json.dumps(result, ensure_ascii=False, default=str))
except Exception as e:
    print(json.dumps({
        'port': 'failure',
        'message': str(e),
        'isSuccess': False
    }))
    sys.exit(1)
''';
  }

  /// 解析脚本输出
  static Map<String, dynamic> _parseScriptOutput(String stdout, ExecutionContext context) {
    if (stdout.isEmpty) {
      return {'port': 'success', 'message': '脚本执行完成（无输出）'};
    }

    // 尝试找到最后一行有效的 JSON
    final lines = stdout.split('\n').reversed;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          return jsonDecode(trimmed) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
      }
    }

    // 如果没有找到 JSON，将整个输出作为 message
    context.debug('脚本输出不是 JSON 格式，作为 message 处理');
    return {
      'port': 'success',
      'message': stdout,
      'data': {'rawOutput': stdout},
    };
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'script',
        name: 'Script',
        description: '执行外部 Python 脚本，实现自定义功能',
        icon: Icons.code,
        color: Colors.teal,
        category: '工具',
        inputs: const [PortSpec.defaultInput],
        outputs: const [PortSpec.success, PortSpec.failure],
        params: const [
          ParamSpec(
            key: 'scriptPath',
            label: '脚本路径',
            type: ParamType.path,
            required: true,
            description: 'Python 脚本的完整路径',
          ),
          ParamSpec(
            key: 'entryFunction',
            label: '入口函数',
            type: ParamType.string,
            defaultValue: 'main',
            description: '脚本中的入口函数名，函数签名: main(input, var, job) -> dict',
          ),
          ParamSpec(
            key: 'timeout',
            label: '超时时间',
            type: ParamType.int,
            defaultValue: 300,
            description: '脚本执行超时时间（秒）',
          ),
        ],
        executor: execute,
      );
}
