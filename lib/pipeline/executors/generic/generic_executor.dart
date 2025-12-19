import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/node_type_definition.dart';

/// 通用执行器
///
/// 将 JSON 配置转换为可执行的 NodeExecutor。
/// 支持 shell、poll、http 三种执行类型。
class GenericExecutor {
  /// 从配置创建执行器
  static NodeExecutor fromConfig(Map<String, dynamic> executorConfig) {
    final type = executorConfig['type'] as String?;

    return switch (type) {
      'shell' => _shellExecutor(executorConfig),
      'poll' => _pollExecutor(executorConfig),
      'http' => _httpExecutor(executorConfig),
      _ => throw ArgumentError('未知执行器类型: $type'),
    };
  }

  /// Shell 命令执行器
  static NodeExecutor _shellExecutor(Map<String, dynamic> executorConfig) {
    return ({
      required Map<String, dynamic> input,
      required Map<String, dynamic> config,
      required ExecutionContext context,
    }) async {
      final command = _resolveVariables(
        executorConfig['command'] as String,
        input,
        config,
        context,
      );
      final workDir = executorConfig['workDir'] != null
          ? _resolveVariables(executorConfig['workDir'] as String, input, config, context)
          : context.workDir;
      final timeout = executorConfig['timeout'] as int? ?? 300; // 默认 5 分钟

      context.info('执行命令: $command');
      context.debug('工作目录: $workDir');

      try {
        final result = await Process.run(
          'bash',
          ['-c', command],
          workingDirectory: workDir,
        ).timeout(Duration(seconds: timeout));

        final stdout = result.stdout.toString();
        final stderr = result.stderr.toString();
        final exitCode = result.exitCode;

        // 解析输出
        final outputData = _parseOutput(stdout, executorConfig['outputParser']);

        // 根据 portMapping 决定端口
        final port = _resolvePort(
          executorConfig['portMapping'],
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
        );

        final isSuccess = exitCode == 0 ||
            (executorConfig['successCondition'] != null &&
                _evaluateCondition(
                  executorConfig['successCondition'] as String,
                  {'exitCode': exitCode, 'stdout': stdout, 'stderr': stderr},
                ));

        return NodeOutput(
          port: port,
          data: {
            'exitCode': exitCode,
            'stdout': stdout,
            'stderr': stderr,
            ...outputData,
          },
          message: isSuccess ? '执行成功' : stderr,
          isSuccess: isSuccess,
        );
      } on TimeoutException {
        return NodeOutput.failure(message: '命令执行超时 ($timeout 秒)');
      } catch (e) {
        return NodeOutput.failure(message: e.toString());
      }
    };
  }

  /// 轮询执行器
  static NodeExecutor _pollExecutor(Map<String, dynamic> executorConfig) {
    return ({
      required Map<String, dynamic> input,
      required Map<String, dynamic> config,
      required ExecutionContext context,
    }) async {
      final command = _resolveVariables(
        executorConfig['command'] as String,
        input,
        config,
        context,
      );
      final intervalStr = executorConfig['interval']?.toString() ?? '30';
      final timeoutStr = executorConfig['timeout']?.toString() ?? '60';
      final interval = int.tryParse(
            _resolveVariables(intervalStr, input, config, context),
          ) ??
          30;
      final timeout = int.tryParse(
            _resolveVariables(timeoutStr, input, config, context),
          ) ??
          60;
      final conditions = executorConfig['conditions'] as Map<String, dynamic>? ?? {};
      final onTimeoutPort = executorConfig['onTimeout'] as String? ?? 'timeout';

      context.info('开始轮询，间隔 ${interval}s，超时 ${timeout}min');

      final deadline = DateTime.now().add(Duration(minutes: timeout));

      while (DateTime.now().isBefore(deadline)) {
        // 检查取消
        if (context.isCancelled) {
          return NodeOutput.cancelled();
        }

        // 检查暂停
        await context.checkPause();

        // 执行命令
        final result = await Process.run('bash', ['-c', command]);
        final stdout = result.stdout.toString();

        context.debug('轮询结果: $stdout');

        // 检查各个条件
        for (final entry in conditions.entries) {
          if (_evaluateCondition(entry.value as String, {'output': stdout, 'stdout': stdout})) {
            context.info('条件满足: ${entry.key}');
            return NodeOutput.port(
              entry.key,
              data: {'stdout': stdout},
              message: '条件满足: ${entry.key}',
            );
          }
        }

        // 计算剩余时间
        final remaining = deadline.difference(DateTime.now());
        context.info('等待中... (${remaining.inMinutes} 分钟后超时)');

        // 等待下一次轮询
        await Future.delayed(Duration(seconds: interval));
      }

      context.warning('轮询超时');
      return NodeOutput.port(
        onTimeoutPort,
        message: '轮询超时 ($timeout 分钟)',
        isSuccess: false,
      );
    };
  }

  /// HTTP 请求执行器
  static NodeExecutor _httpExecutor(Map<String, dynamic> executorConfig) {
    return ({
      required Map<String, dynamic> input,
      required Map<String, dynamic> config,
      required ExecutionContext context,
    }) async {
      final url = _resolveVariables(
        executorConfig['url'] as String,
        input,
        config,
        context,
      );
      final method = (executorConfig['method'] as String? ?? 'GET').toUpperCase();
      final headers = (executorConfig['headers'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, _resolveVariables(v.toString(), input, config, context)),
      );
      final body = executorConfig['body'] != null
          ? _resolveVariables(
              executorConfig['body'] is String ? executorConfig['body'] : jsonEncode(executorConfig['body']),
              input,
              config,
              context,
            )
          : null;
      final timeout = executorConfig['timeout'] as int? ?? 30;

      context.info('HTTP $method $url');

      try {
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: timeout);

        final request = await client.openUrl(method, Uri.parse(url));

        // 设置 headers
        headers?.forEach((key, value) {
          request.headers.set(key, value);
        });

        // 设置 body
        if (body != null && (method == 'POST' || method == 'PUT' || method == 'PATCH')) {
          request.headers.contentType = ContentType.json;
          request.write(body);
        }

        final response = await request.close().timeout(Duration(seconds: timeout));
        final responseBody = await response.transform(utf8.decoder).join();

        client.close();

        final statusCode = response.statusCode;
        final isSuccess = statusCode >= 200 && statusCode < 400;

        // 尝试解析 JSON
        dynamic parsedBody;
        try {
          parsedBody = jsonDecode(responseBody);
        } catch (_) {
          parsedBody = responseBody;
        }

        // 根据 portMapping 决定端口
        final port = _resolvePort(
          executorConfig['portMapping'],
          exitCode: statusCode,
          stdout: responseBody,
          stderr: '',
        );

        return NodeOutput(
          port: port,
          data: {
            'statusCode': statusCode,
            'body': parsedBody,
            'rawBody': responseBody,
          },
          message: isSuccess ? 'HTTP $statusCode' : 'HTTP $statusCode: $responseBody',
          isSuccess: isSuccess,
        );
      } on TimeoutException {
        return NodeOutput.failure(message: 'HTTP 请求超时 ($timeout 秒)');
      } catch (e) {
        return NodeOutput.failure(message: e.toString());
      }
    };
  }

  /// 变量替换
  ///
  /// 支持: ${input.xxx}, ${config.xxx}, ${var.xxx}, ${job.xxx}
  static String _resolveVariables(
    String template,
    Map<String, dynamic> input,
    Map<String, dynamic> config,
    ExecutionContext context,
  ) {
    return template
        .replaceAllMapped(
          RegExp(r'\$\{input\.(\w+)\}'),
          (m) => input[m.group(1)]?.toString() ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$\{config\.(\w+)\}'),
          (m) => config[m.group(1)]?.toString() ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$\{params\.(\w+)\}'),
          (m) => config[m.group(1)]?.toString() ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$\{var\.(\w+)\}'),
          (m) => context.getVariable(m.group(1)!)?.toString() ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$\{job\.(\w+)\}'),
          (m) => _getJobField(context, m.group(1)!) ?? '',
        );
  }

  static String? _getJobField(ExecutionContext context, String field) {
    final job = context.job;
    return switch (field) {
      'jobId' => job.jobId.toString(),
      'sourceUrl' => job.sourceUrl,
      'targetWc' => job.targetWc,
      'currentRevision' => job.currentRevision?.toString(),
      'revisions' => job.revisions.join(','),
      'completedIndex' => job.completedIndex.toString(),
      _ => null,
    };
  }

  /// 解析输出
  static Map<String, dynamic> _parseOutput(
    String stdout,
    Map<String, dynamic>? outputParser,
  ) {
    if (outputParser == null) return {};

    final result = <String, dynamic>{};

    for (final entry in outputParser.entries) {
      final key = entry.key;
      final pattern = entry.value as String;

      if (pattern.startsWith('regex:')) {
        final regex = RegExp(pattern.substring(6));
        final match = regex.firstMatch(stdout);
        if (match != null) {
          result[key] = match.groupCount > 0 ? match.group(1) : match.group(0);
        }
      } else if (pattern.startsWith('json:')) {
        final jsonPath = pattern.substring(5);
        try {
          final json = jsonDecode(stdout);
          result[key] = _getJsonPath(json, jsonPath);
        } catch (_) {}
      } else {
        // 直接正则匹配
        final match = RegExp(pattern).firstMatch(stdout);
        if (match != null) {
          result[key] = match.groupCount > 0 ? match.group(1) : match.group(0);
        }
      }
    }

    return result;
  }

  static dynamic _getJsonPath(dynamic json, String path) {
    final parts = path.split('.');
    dynamic current = json;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final index = int.tryParse(part);
        if (index != null && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  /// 根据映射规则决定端口
  static String _resolvePort(
    Map<String, dynamic>? mapping, {
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    if (mapping == null) {
      return exitCode == 0 ? 'success' : 'failure';
    }

    // 检查 exitCode 映射
    if (mapping.containsKey('exitCode')) {
      final exitCodeMap = mapping['exitCode'] as Map<String, dynamic>;
      final key = exitCode.toString();
      if (exitCodeMap.containsKey(key)) return exitCodeMap[key] as String;
      if (exitCodeMap.containsKey('*')) return exitCodeMap['*'] as String;
    }

    // 检查 stdout 映射
    if (mapping.containsKey('stdout')) {
      final stdoutMap = mapping['stdout'] as Map<String, dynamic>;
      for (final entry in stdoutMap.entries) {
        if (_evaluateCondition(entry.key, {'output': stdout, 'stdout': stdout})) {
          return entry.value as String;
        }
      }
    }

    // 检查 statusCode 映射（HTTP 用）
    if (mapping.containsKey('statusCode')) {
      final statusCodeMap = mapping['statusCode'] as Map<String, dynamic>;
      final key = exitCode.toString();
      if (statusCodeMap.containsKey(key)) return statusCodeMap[key] as String;
      // 检查范围
      for (final entry in statusCodeMap.entries) {
        if (entry.key.contains('-')) {
          final parts = entry.key.split('-');
          final min = int.tryParse(parts[0]) ?? 0;
          final max = int.tryParse(parts[1]) ?? 999;
          if (exitCode >= min && exitCode <= max) {
            return entry.value as String;
          }
        }
      }
      if (statusCodeMap.containsKey('*')) return statusCodeMap['*'] as String;
    }

    return exitCode == 0 ? 'success' : 'failure';
  }

  /// 简单条件表达式求值
  static bool _evaluateCondition(String condition, Map<String, dynamic> vars) {
    // 通配符
    if (condition == '*') return true;

    // contains:xxx
    if (condition.startsWith('contains:')) {
      final needle = condition.substring(9);
      final output = vars['output']?.toString() ?? vars['stdout']?.toString() ?? '';
      return output.contains(needle);
    }

    // regex:xxx
    if (condition.startsWith('regex:')) {
      final pattern = condition.substring(6);
      final output = vars['output']?.toString() ?? vars['stdout']?.toString() ?? '';
      return RegExp(pattern).hasMatch(output);
    }

    // equals:xxx
    if (condition.startsWith('equals:')) {
      final expected = condition.substring(7);
      final output = vars['output']?.toString() ?? vars['stdout']?.toString() ?? '';
      return output.trim() == expected;
    }

    // output.contains('xxx')
    final containsMatch = RegExp(r"(\w+)\.contains\('([^']+)'\)").firstMatch(condition);
    if (containsMatch != null) {
      final varName = containsMatch.group(1)!;
      final needle = containsMatch.group(2)!;
      return vars[varName]?.toString().contains(needle) ?? false;
    }

    // exitCode == 0
    if (condition.contains('==')) {
      final parts = condition.split('==').map((s) => s.trim()).toList();
      final left = vars[parts[0]]?.toString() ?? parts[0];
      final right = parts[1];
      return left == right;
    }

    // exitCode != 0
    if (condition.contains('!=')) {
      final parts = condition.split('!=').map((s) => s.trim()).toList();
      final left = vars[parts[0]]?.toString() ?? parts[0];
      final right = parts[1];
      return left != right;
    }

    return false;
  }
}
