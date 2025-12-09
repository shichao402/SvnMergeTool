/// 统一日志服务
///
/// 提供统一的日志输出接口，包含：
/// - 统一的日志格式（时间戳 + 级别 + 消息）
/// - 日志级别控制（debug, info, warn, error）
/// - 日志持久化到文件（logs/app.log）
/// - 开发/生产环境区分
/// - 自动日志清理（保留最近10个文件，单个<10MB，总大小<50MB）

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 日志级别
enum LogLevel {
  debug,  // 调试信息
  info,   // 一般信息
  warn,   // 警告
  error,  // 错误
}

/// 统一日志服务
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  
  factory LoggerService() => _instance;
  
  LoggerService._internal();

  /// 当前日志级别（生产环境可以设置为 info 或 warn）
  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// 是否启用日志（可以在运行时动态控制）
  bool enabled = true;

  /// 日志标签（模块名）
  String _tag = 'APP';

  /// 日志文件路径
  String? _logFilePath;

  /// 日志文件对象
  IOSink? _logFileSink;

  /// 是否已初始化
  bool _initialized = false;

  /// 日志写入队列（确保顺序写入）
  final List<String> _writeQueue = [];
  
  /// 是否正在写入
  bool _isWriting = false;

  /// 最大日志文件数量
  static const int maxLogFiles = 10;

  /// 单个日志文件最大大小（10MB）
  static const int maxLogFileSize = 10 * 1024 * 1024;

  /// 所有日志文件总大小限制（50MB）
  static const int maxTotalLogSize = 50 * 1024 * 1024;

  /// 设置日志标签
  void setTag(String tag) {
    _tag = tag;
  }

  /// 获取程序所在目录
  Directory _getExecutableDirectory() {
    // Platform.resolvedExecutable 返回当前运行的可执行文件的完整路径
    // 例如：D:\workspace\GitHub\SvnMergeTool\build\windows\x64\runner\Debug\SvnMergeTool.exe
    final exePath = Platform.resolvedExecutable;
    final exeDir = Directory(path.dirname(exePath));
    return exeDir;
  }

  /// 初始化日志文件
  Future<void> _initLogFile() async {
    if (_initialized) return;

    try {
      // 获取程序所在目录或应用支持目录
      Directory logDir;
      
      // 获取程序所在目录
      final exeDir = _getExecutableDirectory();
      final exeLogDir = Directory(path.join(exeDir.path, 'logs'));
      
      // 策略1：使用程序所在目录下的 logs 目录（打包环境）
      // 策略2：如果程序在 flutter 开发环境中运行，使用项目根目录
      // 策略3：使用应用支持目录（fallback）
      
      // 检查是否在开发环境（flutter run）
      final currentDir = Directory.current;
      final isDevEnvironment = await File(path.join(currentDir.path, 'pubspec.yaml')).exists();
      
      if (isDevEnvironment) {
        // 开发环境：使用项目根目录下的 logs 目录
        logDir = Directory(path.join(currentDir.path, 'logs'));
      } else if (await exeDir.exists()) {
        // 打包环境：使用程序所在目录下的 logs 目录
        logDir = exeLogDir;
      } else {
        // Fallback：使用应用支持目录
        final appDir = await getApplicationSupportDirectory();
        logDir = Directory(path.join(appDir.path, 'SvnMergeTool', 'logs'));
      }

      // 确保日志目录存在
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      // 生成日志文件名（带时间戳）
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final logFileName = 'app_$timestamp.log';
      _logFilePath = path.join(logDir.path, logFileName);

      // 打开日志文件（追加模式）
      final logFile = File(_logFilePath!);
      _logFileSink = logFile.openWrite(mode: FileMode.append);

      _initialized = true;

      // 清理旧日志文件
      await _cleanupOldLogs(logDir);
    } catch (e, stackTrace) {
      // 如果文件日志初始化失败，不影响控制台日志输出
      // 注意：这里使用 debugPrint 是必要的，因为日志服务本身需要输出错误
      // 这是基础设施层的特殊情况
      debugPrint('日志文件初始化失败: $e\n$stackTrace');
    }
  }

  /// 清理旧日志文件
  Future<void> _cleanupOldLogs(Directory logDir) async {
    try {
      final logFiles = <File>[];
      int totalSize = 0;

      // 收集所有日志文件
      await for (final entity in logDir.list()) {
        if (entity is File && entity.path.contains('app_') && entity.path.endsWith('.log')) {
          final stat = await entity.stat();
          logFiles.add(entity);
          totalSize += stat.size;
        }
      }

      // 按修改时间排序（最新的在前）
      // 先获取所有文件的统计信息
      final fileStats = <File, FileStat>{};
      for (final file in logFiles) {
        fileStats[file] = await file.stat();
      }
      logFiles.sort((a, b) {
        final aStat = fileStats[a]!;
        final bStat = fileStats[b]!;
        return bStat.modified.compareTo(aStat.modified);
      });

      // 删除超出数量限制的文件
      while (logFiles.length > maxLogFiles) {
        final file = logFiles.removeLast();
        final stat = await file.stat();
        totalSize -= stat.size;
        await file.delete();
      }

      // 如果总大小超限，删除最旧的文件
      while (totalSize > maxTotalLogSize && logFiles.isNotEmpty) {
        final file = logFiles.removeLast();
        final stat = await file.stat();
        totalSize -= stat.size;
        await file.delete();
      }

      // 检查并删除超大文件
      for (final file in List.from(logFiles)) {
        final stat = await file.stat();
        if (stat.size > maxLogFileSize) {
          await file.delete();
          logFiles.remove(file);
          totalSize -= stat.size as int;
        }
      }
    } catch (e, stackTrace) {
      // 注意：这里使用 debugPrint 是必要的，因为日志服务本身需要输出错误
      debugPrint('清理旧日志文件失败: $e\n$stackTrace');
    }
  }

  /// 写入日志到文件（使用队列确保顺序写入）
  void _enqueueWrite(String message) {
    _writeQueue.add(message);
    _processWriteQueue();
  }

  /// 处理写入队列
  Future<void> _processWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty) return;
    
    _isWriting = true;
    
    try {
      if (!_initialized) {
        await _initLogFile();
      }

      while (_writeQueue.isNotEmpty && _logFileSink != null) {
        final message = _writeQueue.removeAt(0);
        try {
          _logFileSink!.writeln(message);
        } catch (e) {
          // 写入失败，不影响后续写入
          debugPrint('写入日志失败: $e');
        }
      }
      
      // 批量 flush
      if (_logFileSink != null) {
        await _logFileSink!.flush();
      }
    } catch (e, stackTrace) {
      debugPrint('处理日志队列失败: $e\n$stackTrace');
    } finally {
      _isWriting = false;
      
      // 如果队列中还有新的日志，继续处理
      if (_writeQueue.isNotEmpty) {
        // 使用 scheduleMicrotask 避免递归调用栈溢出
        scheduleMicrotask(() => _processWriteQueue());
      }
    }
  }

  /// 写入日志到文件（兼容旧接口）
  Future<void> _writeToFile(String message) async {
    _enqueueWrite(message);
  }

  /// 关闭日志文件
  Future<void> close() async {
    // 等待队列处理完成
    while (_writeQueue.isNotEmpty || _isWriting) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await _logFileSink?.flush();
    await _logFileSink?.close();
    _logFileSink = null;
    _initialized = false;
  }

  /// 格式化日志消息
  String _format(LogLevel level, String message, [String? tag]) {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    
    final levelStr = level.name.toUpperCase().padRight(5);
    final tagStr = (tag ?? _tag).padRight(8);
    
    return '[$timestamp] [$levelStr] [$tagStr] $message';
  }

  /// 判断是否应该输出日志
  bool _shouldLog(LogLevel level) {
    return enabled && level.index >= minLevel.index;
  }

  /// 输出日志
  void _log(LogLevel level, String message, [String? tag]) {
    if (_shouldLog(level)) {
      final formatted = _format(level, message, tag);
      
      // 输出到控制台
      debugPrint(formatted);
      
      // 异步写入文件（不阻塞主线程）
      _writeToFile(formatted).catchError((e) {
        // 静默处理文件写入错误，不影响应用运行
      });
    }
  }

  /// Debug 日志（开发调试用）
  void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  /// Info 日志（一般信息）
  void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  /// Warning 日志（警告信息）
  void warn(String message, [String? tag]) {
    _log(LogLevel.warn, message, tag);
  }

  /// Error 日志（错误信息）
  void error(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, tag);
    
    String? errorDetail;
    if (error != null) {
      errorDetail = '  └─ Error: $error';
      if (kDebugMode) {
        debugPrint(errorDetail);
      }
      // 写入文件
      if (errorDetail != null) {
        _writeToFile(errorDetail).catchError((e) {});
      }
    }
    
    if (stackTrace != null) {
      final stackDetail = '  └─ StackTrace:\n$stackTrace';
      if (kDebugMode) {
        debugPrint(stackDetail);
      }
      // 写入文件
      _writeToFile(stackDetail).catchError((e) {});
    }
  }

  /// 创建带标签的日志记录器
  TaggedLogger tagged(String tag) {
    return TaggedLogger._(this, tag);
  }
}

/// 带标签的日志记录器
class TaggedLogger {
  final LoggerService _logger;
  final String _tag;

  TaggedLogger._(this._logger, this._tag);

  void debug(String message, [StackTrace? stackTrace]) {
    _logger.debug(message, _tag);
    if (stackTrace != null) {
      _logger.debug('Stack trace:\n$stackTrace', _tag);
    }
  }
  void info(String message) => _logger.info(message, _tag);
  void warn(String message) => _logger.warn(message, _tag);
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.error(message, _tag, error, stackTrace);
  }
}

/// 全局日志实例（便捷访问）
final logger = LoggerService();

/// 预定义的模块日志记录器
class AppLogger {
  static final svn = logger.tagged('SVN');
  static final config = logger.tagged('CONFIG');
  static final credential = logger.tagged('CRED');
  static final storage = logger.tagged('STORAGE');
  static final plugin = logger.tagged('PLUGIN');
  static final merge = logger.tagged('MERGE');
  static final ui = logger.tagged('UI');
  static final app = logger.tagged('APP');
  static final preload = logger.tagged('PRELOAD');
}


