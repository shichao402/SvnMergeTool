import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// 脚本阶段执行器
/// 执行自定义脚本，捕获输出
class ScriptExecutor extends StageExecutor {
  Process? _currentProcess;
  bool _isCancelled = false;

  @override
  bool get supportsCancellation => true;

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentProcess?.kill(ProcessSignal.sigterm);
  }

  @override
  Future<ExecutionResult> execute(
    StageConfig config,
    PipelineContext context, {
    void Function(String message)? onLog,
  }) async {
    _isCancelled = false;

    final script = config.script;
    if (script == null || script.isEmpty) {
      return ExecutionResult.failure('缺少脚本路径');
    }

    // 解析脚本路径中的变量
    final resolvedScript = context.resolve(script);

    // 解析脚本参数
    final args = config.scriptArgs
            ?.map((arg) => context.resolve(arg))
            .toList() ??
        [];

    // 获取工作目录
    final workingDirectory =
        context.jobParams['targetWc'] as String? ?? Directory.current.path;

    try {
      onLog?.call('[INFO] 执行脚本: $resolvedScript ${args.join(' ')}');

      // 确定执行方式
      final executable = _getExecutable(resolvedScript);
      final execArgs = _getExecutableArgs(resolvedScript, args);

      // 启动进程
      _currentProcess = await Process.start(
        executable,
        execArgs,
        workingDirectory: workingDirectory,
        environment: _buildEnvironment(context),
        runInShell: Platform.isWindows,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // 收集输出
      final stdoutFuture = _currentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuffer.writeln(line);
        onLog?.call('[STDOUT] $line');
      }).asFuture();

      final stderrFuture = _currentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.writeln(line);
        onLog?.call('[STDERR] $line');
      }).asFuture();

      // 等待进程完成
      int exitCode;
      if (config.timeoutSeconds > 0) {
        exitCode = await _currentProcess!.exitCode.timeout(
          Duration(seconds: config.timeoutSeconds),
          onTimeout: () {
            _currentProcess?.kill(ProcessSignal.sigterm);
            throw TimeoutException('脚本执行超时');
          },
        );
      } else {
        exitCode = await _currentProcess!.exitCode;
      }

      // 等待输出收集完成
      await Future.wait([stdoutFuture, stderrFuture]);

      _currentProcess = null;

      if (_isCancelled) {
        return ExecutionResult.failure('脚本执行被取消');
      }

      final stdout = stdoutBuffer.toString().trim();
      final stderr = stderrBuffer.toString().trim();

      if (exitCode == 0) {
        // 解析输出
        dynamic parsedOutput;
        if (config.captureMode == CaptureMode.json) {
          parsedOutput = PipelineContext.parseJson(stdout);
          if (parsedOutput == null && stdout.isNotEmpty) {
            onLog?.call('[WARN] JSON 解析失败，将使用原始文本');
          }
        }

        onLog?.call('[INFO] 脚本执行成功 (exit code: $exitCode)');
        return ExecutionResult.success(
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
          parsedOutput: parsedOutput,
        );
      } else {
        onLog?.call('[ERROR] 脚本执行失败 (exit code: $exitCode)');
        return ExecutionResult.failure(
          stderr.isNotEmpty ? stderr : '脚本返回非零退出码: $exitCode',
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
        );
      }
    } on TimeoutException catch (e) {
      onLog?.call('[ERROR] ${e.message}');
      return ExecutionResult.failure(e.message ?? '脚本执行超时');
    } catch (e) {
      onLog?.call('[ERROR] 脚本执行异常: $e');
      return ExecutionResult.failure(e.toString());
    } finally {
      _currentProcess = null;
    }
  }

  /// 获取执行器
  String _getExecutable(String script) {
    if (Platform.isWindows) {
      if (script.endsWith('.bat') || script.endsWith('.cmd')) {
        return 'cmd';
      } else if (script.endsWith('.ps1')) {
        return 'powershell';
      } else if (script.endsWith('.py')) {
        return 'python';
      }
      return script;
    } else {
      if (script.endsWith('.py')) {
        return 'python3';
      } else if (script.endsWith('.sh')) {
        return 'bash';
      }
      return script;
    }
  }

  /// 获取执行器参数
  List<String> _getExecutableArgs(String script, List<String> args) {
    if (Platform.isWindows) {
      if (script.endsWith('.bat') || script.endsWith('.cmd')) {
        return ['/c', script, ...args];
      } else if (script.endsWith('.ps1')) {
        return ['-ExecutionPolicy', 'Bypass', '-File', script, ...args];
      } else if (script.endsWith('.py')) {
        return [script, ...args];
      }
      return args;
    } else {
      if (script.endsWith('.py')) {
        return [script, ...args];
      } else if (script.endsWith('.sh')) {
        return [script, ...args];
      }
      return args;
    }
  }

  /// 构建环境变量
  Map<String, String> _buildEnvironment(PipelineContext context) {
    final env = Map<String, String>.from(Platform.environment);

    // 添加上下文中的环境变量
    env.addAll(context.env);

    // 添加任务参数作为环境变量
    for (final entry in context.jobParams.entries) {
      if (entry.value is String) {
        env['PIPELINE_${entry.key.toUpperCase()}'] = entry.value as String;
      } else if (entry.value != null) {
        env['PIPELINE_${entry.key.toUpperCase()}'] = entry.value.toString();
      }
    }

    return env;
  }
}
