import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R139 复用，R140 沿用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R140 AppLogger output sink 通道协议审计**
///
/// 协议要点（详见 lib/services/logger_service.dart 内 `class LoggerService`
/// 上方 R140 doc-block）：
/// - 2 sink 全集穷尽闭合：console（debugPrint）+ file（IOSink）
/// - S1 主路双写律：normal log path 双写 console + file
/// - S2 error 路径 fanout 律：message + errorDetail + stackTrace 三段双写
/// - S3 meta-error sink 单档收敛律：logger 自身错误仅走 console，禁递归 file
/// - S4 file sink 失败处置律：write-fail 静默吞 + console 兜底（R119 档 2）
///
/// 本测仅验证：1) sink 字面量结构存在；2) 双写主路存在；3) meta-error 4 处
/// 单档约束（catch 块内不调用 _writeToFile）；4) doc-block 关键字锚点。
void main() {
  final loggerSrc = File('lib/services/logger_service.dart').readAsStringSync();
  final loggerCode = _stripComments(loggerSrc);

  group('R140 group 1: 2 sink 全集穷尽闭合', () {
    test('console sink: debugPrint 至少 4 处（meta-error）+ 主路 1 处', () {
      final hits = RegExp(r'\bdebugPrint\(').allMatches(loggerCode).length;
      expect(hits, greaterThanOrEqualTo(5),
          reason: 'console sink 至少 5 处：S1 主路 1 + S2 段 2/3 各 1 + S3 meta-error 多处');
    });

    test('file sink: _logFileSink IOSink 字段存在', () {
      expect(loggerCode, contains('IOSink? _logFileSink'),
          reason: 'file sink 唯一字段');
    });

    test('file sink openWrite 模式: FileMode.write', () {
      expect(loggerCode, contains('openWrite(mode: FileMode.write)'));
    });

    test('file sink 异步队列: _writeQueue + _isWriting', () {
      expect(loggerCode, contains('_writeQueue'));
      expect(loggerCode, contains('_isWriting'));
    });

    test('不存在第 3 类 sink: 无 stdout./syslog/Sentry/HttpClient', () {
      // 容许 svn_service 里的 stdout（那是 Process.result.stdout，不是 logger sink）
      expect(loggerCode, isNot(contains('stdout.write')));
      expect(loggerCode, isNot(contains('stderr.write')));
      expect(loggerCode, isNot(contains('Sentry')));
      expect(loggerCode, isNot(contains('syslog')));
    });
  });

  group('R140 group 2: S1 主路双写律 (_log)', () {
    test('_log 真分支同时含 debugPrint(formatted) 与 _writeToFile(formatted)', () {
      // 提取 `void _log(...)` 函数体（粗粒度：到下一处 `void ` 或 `Future<void> `）
      final logFnIdx = loggerCode.indexOf('void _log(LogLevel level');
      expect(logFnIdx, greaterThan(0), reason: '_log 函数应存在');
      final logFnBody = loggerCode.substring(
          logFnIdx, logFnIdx + 600.clamp(0, loggerCode.length - logFnIdx));
      expect(logFnBody, contains('debugPrint(formatted)'),
          reason: 'S1 console 路');
      expect(logFnBody, contains('_writeToFile(formatted)'),
          reason: 'S1 file 路');
    });

    test('S1 file 路必须包裹 silentlyDiscardAsyncError', () {
      final logFnIdx = loggerCode.indexOf('void _log(LogLevel level');
      final logFnBody = loggerCode.substring(
          logFnIdx, logFnIdx + 600.clamp(0, loggerCode.length - logFnIdx));
      expect(logFnBody,
          contains('silentlyDiscardAsyncError(_writeToFile(formatted))'),
          reason: 'R119 档 2 fire-and-forget 静默策略');
    });
  });

  group('R140 group 3: S2 error 路径 fanout 律', () {
    test('error() 包含 errorDetail + stackDetail 三段输出', () {
      final errorFnIdx =
          loggerCode.indexOf('void error(String message,\n      [String? tag,');
      expect(errorFnIdx, greaterThan(0), reason: 'error() 函数应存在');
      final body = loggerCode.substring(
          errorFnIdx, errorFnIdx + 1000.clamp(0, loggerCode.length - errorFnIdx));
      expect(body, contains('errorDetail = formatErrorDetail(error)'));
      expect(body, contains('stackDetail = formatStackTraceDetail(stackTrace)'));
      expect(body, contains('silentlyDiscardAsyncError(_writeToFile(errorDetail))'));
      expect(body,
          contains('silentlyDiscardAsyncError(_writeToFile(stackDetail))'));
    });

    test('S2 段 2/3 console 路用 kDebugMode gate（不对称）', () {
      final errorFnIdx =
          loggerCode.indexOf('void error(String message,\n      [String? tag,');
      final body = loggerCode.substring(
          errorFnIdx, errorFnIdx + 1000.clamp(0, loggerCode.length - errorFnIdx));
      // kDebugMode block 内有 debugPrint(errorDetail) / debugPrint(stackDetail)
      expect(body, contains('if (kDebugMode)'),
          reason: 'release 下静默 errorDetail/stackDetail console 噪音');
    });
  });

  group('R140 group 4: S3 meta-error sink 单档收敛律', () {
    // 4 处 meta-error catch 块内 debugPrint，且**不**调用 _writeToFile
    test('S3-1: _initLogFile 失败 catch 内仅 debugPrint，不写 file', () {
      expect(loggerCode, contains("debugPrint('日志文件初始化失败:"));
    });

    test('S3-2: archive latest.log 失败 catch 内仅 debugPrint', () {
      expect(loggerCode, contains("debugPrint('归档 latest.log 失败"));
    });

    test('S3-3: _cleanupOldLogs 失败 catch 内仅 debugPrint', () {
      expect(loggerCode, contains("debugPrint('清理旧日志文件失败:"));
    });

    test('S3-4: _processWriteQueue 总 catch 内仅 debugPrint', () {
      expect(loggerCode, contains("debugPrint('处理日志队列失败:"));
    });

    test('S4: file sink writeln 失败 catch 内仅 debugPrint', () {
      expect(loggerCode, contains("debugPrint('写入日志失败:"));
    });

    test('meta-error 路径全集禁止递归 _writeToFile', () {
      // 解析所有"非 _log/_logXxx"的 catch 块；这里用粗粒度：扫描每处
      // debugPrint('日志文件...|归档...|清理旧...|处理日志队列...|写入日志失败...
      // 所在源码行号附近 ±5 行，确保**不**出现 _writeToFile。
      final lines = loggerCode.split('\n');
      final metaPatterns = <RegExp>[
        RegExp(r"debugPrint\('日志文件初始化失败:"),
        RegExp(r"debugPrint\('归档 latest\.log 失败"),
        RegExp(r"debugPrint\('清理旧日志文件失败:"),
        RegExp(r"debugPrint\('处理日志队列失败:"),
        RegExp(r"debugPrint\('写入日志失败:"),
      ];
      for (final pat in metaPatterns) {
        final idx = lines.indexWhere((l) => pat.hasMatch(l));
        expect(idx, greaterThanOrEqualTo(0), reason: '应找到 ${pat.pattern}');
        final lo = (idx - 5).clamp(0, lines.length);
        final hi = (idx + 5).clamp(0, lines.length);
        final near = lines.sublist(lo, hi).join('\n');
        expect(near, isNot(contains('_writeToFile(')),
            reason: 'meta-error catch 附近禁止再调 _writeToFile（防递归）');
      }
    });
  });

  group('R140 group 5: doc-block 锚点锁', () {
    test('R140 doc-block 关键字存在', () {
      expect(loggerSrc, contains('R140 AppLogger output sink 通道协议审计'));
      expect(loggerSrc, contains('S1 主路双写律'));
      expect(loggerSrc, contains('S2 error 路径 fanout 律'));
      expect(loggerSrc, contains('S3 meta-error sink 单档收敛律'));
      expect(loggerSrc, contains('S4 file sink 失败处置律'));
    });

    test('R138/R139 前序 doc-block 仍存在（不被 R140 替换）', () {
      expect(loggerSrc, contains('R138 AppLogger tag namespace'));
      expect(loggerSrc, contains('R139 AppLogger log level 维度协议审计'));
    });

    test('R140 二维基线 + 第三轴扩张提及', () {
      expect(loggerSrc, contains('域 × 量 × 通道'));
      expect(loggerSrc, contains('三档框架第 20 次复用'));
    });
  });
}
