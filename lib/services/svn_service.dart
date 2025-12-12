/// SVN 操作服务 - 统一封装所有 SVN 命令
///
/// 此类提供了所有 SVN 操作的统一入口，包括：
/// - 基础命令：log, merge, commit, update, revert, cleanup
/// - 高级操作：autoMergeAndCommit（自动重试）
/// - 错误处理：统一的错误处理和日志输出
///
/// **重要：SVN 鉴权管理**
/// - SVN 鉴权完全依赖 SVN 自身管理，本项目不存储用户名和密码
/// - SVN 使用独立的配置目录（--config-dir）缓存凭证
/// - 当需要认证时，SVN 会通过系统机制（如 Keychain）提示用户输入
/// - 本项目仅在需要时提供一次输入用户名密码的对话框（CredentialDialog）
/// - 凭证输入后直接传递给 SVN，SVN 会自动缓存，下次不再需要输入

import 'dart:convert';
import 'dart:io';
import 'package:process_run/shell.dart';
import 'logger_service.dart';
import 'svn_xml_parser.dart';

/// ProcessResult 的包装类，用于处理编码问题
/// 
/// 这是一个公开的类，供其他模块使用（如 WorkingCopyManager）
class SvnProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int pid;

  SvnProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.pid,
  });
  
  /// 是否成功
  bool get isSuccess => exitCode == 0;
}

class SvnService {
  /// 单例模式
  static final SvnService _instance = SvnService._internal();
  factory SvnService() => _instance;
  SvnService._internal();

  /// Shell 实例
  Shell? _shell;

  /// 日志回调
  Function(String)? onLog;

  /// 不支持 --xml 参数的 SVN 命令黑名单
  /// 
  /// 这些命令不支持 XML 输出，即使 useXml=true 也不会添加 --xml 参数
  /// 
  /// 注意：mergeinfo 命令在某些 SVN 版本中不支持 --xml，需要文本解析
  static const Set<String> _xmlBlacklist = {
    'merge',
    'commit',
    'update',
    'revert',
    'cleanup',
    'status',
    'mergeinfo',  // mergeinfo 不支持 --xml 参数
    'add',
    'delete',
    'move',
    'copy',
    'mkdir',
    'propset',
    'propget',
    'proplist',
    'propdel',
    'lock',
    'unlock',
    'switch',
    'export',
    'import',
    'checkout',
    'co',
  };

  /// 初始化服务
  Future<void> init() async {
    _shell = Shell(
      throwOnError: false,
      commandVerbose: false,
    );
  }

  /// 记录日志
  void _log(String message) {
    AppLogger.svn.info(message);
    onLog?.call(message);
  }

  /// 构建 SVN 命令参数（添加认证和配置）
  /// 
  /// [username] 和 [password] 参数是可选的，仅在需要临时传递凭证时使用
  /// 正常情况下不传递这些参数，让 SVN 使用自己的凭证缓存
  List<String> _buildSvnArgs(
    List<String> baseArgs, {
    String? username,
    String? password,
  }) {
    final args = <String>['svn'];
    
    // 添加认证参数（仅在需要临时传递凭证时）
    // 注意：正常情况下不传递，让 SVN 使用自己的凭证缓存
    if (username != null && username.isNotEmpty) {
      args.addAll(['--username', username]);
    }
    if (password != null && password.isNotEmpty) {
      args.addAll(['--password', password]);
    }
    
    // 使用系统默认的 SVN 配置目录（%APPDATA%/Subversion）
    // 这样可以复用用户在命令行中已经缓存的凭据
    // 注意：不再使用独立配置目录，避免凭据缓存问题
    args.add('--non-interactive');
    
    // 添加基础参数
    args.addAll(baseArgs);
    
    return args;
  }

  /// 执行 SVN 命令
  /// 
  /// [args] SVN 命令参数（不包含 'svn' 前缀）
  /// [useXml] 是否使用 --xml 参数（默认 false，某些命令不支持 XML）
  /// [workingDirectory] 工作目录
  /// [username] SVN 用户名
  /// [password] SVN 密码
  Future<SvnProcessResult> _runSvnCommand(
    List<String> args, {
    bool useXml = false,
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    // 如果需要 XML 输出，检查命令是否支持 XML
    final finalArgs = List<String>.from(args);
    if (useXml && !finalArgs.contains('--xml')) {
      // 获取命令名称（第一个参数）
      final command = args.isNotEmpty ? args[0] : '';
      
      // 检查命令是否在黑名单中
      if (_xmlBlacklist.contains(command)) {
        // 命令不支持 XML，忽略 useXml 参数
        _log('⚠ 命令 "$command" 不支持 --xml 参数，已忽略 useXml 设置');
      } else {
        // 在命令和 URL/路径之间插入 --xml
        // 通常格式是: command [options] [url/path]
        // 我们在 command 之后立即插入 --xml
        finalArgs.insert(1, '--xml');
      }
    }
    
    final fullArgs = _buildSvnArgs(finalArgs, username: username, password: password);
    
    // 隐藏密码的日志输出
    final displayArgs = finalArgs.join(' ');
    final authInfo = username != null ? ' --username $username --password ****' : '';
    final workingDirInfo = workingDirectory != null ? ' (工作目录: $workingDirectory)' : '';
    final xmlInfo = useXml ? ' [XML 输出]' : '';
    
    // 记录命令执行开始
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('[SVN 命令执行] svn $displayArgs$authInfo$xmlInfo$workingDirInfo');
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    final startTime = DateTime.now();
    
    // 使用 latin1 编码读取原始字节，避免 UTF-8 解码错误
    // Windows 上 SVN 可能输出 GBK 编码的中文
    final result = await Process.run(
      fullArgs[0],
      fullArgs.sublist(1),
      workingDirectory: workingDirectory,
      stdoutEncoding: latin1,
      stderrEncoding: latin1,
    );
    
    // 尝试将输出转换为 UTF-8，如果失败则保持原样
    String stdout;
    String stderr;
    try {
      // 先尝试 UTF-8 解码
      stdout = utf8.decode(latin1.encode(result.stdout.toString()), allowMalformed: true);
      stderr = utf8.decode(latin1.encode(result.stderr.toString()), allowMalformed: true);
    } catch (_) {
      // 如果失败，尝试 GBK 解码（Windows 中文环境）
      try {
        // 使用 systemEncoding（Windows 上通常是 GBK）
        stdout = result.stdout.toString();
        stderr = result.stderr.toString();
      } catch (_) {
        // 最后保底：直接使用原始输出
        stdout = result.stdout.toString();
        stderr = result.stderr.toString();
      }
    }
    
    // 创建一个包装结果
    final wrappedResult = SvnProcessResult(
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: stderr,
      pid: result.pid,
    );
    
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    
    final output = stdout + stderr;
    
    // 记录命令执行结果
    if (wrappedResult.exitCode == 0) {
      _log('✓ SVN 命令执行成功 (退出码: ${wrappedResult.exitCode}, 耗时: ${duration.inMilliseconds}ms)');
    } else {
      _log('✗ SVN 命令执行失败 (退出码: ${wrappedResult.exitCode}, 耗时: ${duration.inMilliseconds}ms)');
      // 失败时记录命令和错误输出，便于排查
      _log('  命令: svn $displayArgs');
      if (stderr.isNotEmpty) {
        _log('  错误: ${stderr.trim()}');
      }
      if (stdout.isNotEmpty) {
        final stdoutPreview = stdout.trim();
        if (stdoutPreview.length > 200) {
          _log('  输出: ${stdoutPreview.substring(0, 200)}...');
        } else {
          _log('  输出: $stdoutPreview');
        }
      }
    }
    
    // 记录输出内容（仅摘要，不记录详细内容）
    if (output.isNotEmpty) {
      final lines = output.split('\n').length;
      final size = output.length;
      if (useXml) {
        _log('(XML 输出: ${lines} 行, ${size} 字符)');
      } else {
        _log('(输出: ${lines} 行, ${size} 字符)');
      }
    } else {
      _log('(无输出内容)');
    }
    
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    if (wrappedResult.exitCode != 0) {
      throw SvnException(
        'SVN 命令执行失败 (退出码: ${wrappedResult.exitCode})',
        command: displayArgs,
        exitCode: wrappedResult.exitCode,
        output: output,
      );
    }
    
    return wrappedResult;
  }

  /// 查找分支点（用于 stopOnCopy 功能）
  /// 
  /// [branchUrl] 分支的 URL
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  /// 
  /// 返回分支点的 revision 号，如果未找到则返回 null
  /// 
  /// 注意：这是一个业务逻辑方法，专门用于查找分支点
  Future<int?> findBranchPoint(
    String branchUrl, {
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('【SvnService.findBranchPoint】查找分支点');
    _log('  分支 URL: $branchUrl');
    _log('  工作目录: ${workingDirectory ?? "未指定"}');
    
    // 执行 svn log --stop-on-copy -l 1 -r 1:HEAD
    final args = ['log', branchUrl, '--stop-on-copy', '-l', '1', '-r', '1:HEAD'];
    _log('  命令: svn ${args.join(' ')} --xml');
    
    final result = await _runSvnCommand(
      args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );
    
    final xmlOutput = result.stdout.toString();
    final entries = SvnXmlParser.parseLog(xmlOutput);
    
    int? branchPoint;
    if (entries.isNotEmpty) {
      branchPoint = entries.first.revision;
      _log('  ✓ 找到分支点: r$branchPoint');
    } else {
      _log('  ⚠ 未找到分支点');
    }
    
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return branchPoint;
  }

  /// 查找根尾（ROOT_TAIL）- 整个SVN路径的最早revision
  /// 
  /// [sourceUrl] 源 URL
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  /// 
  /// 返回根尾的 revision 号（通常是1），如果未找到则返回 null
  /// 
  /// 注意：通过 `svn log -r 1:HEAD`（不加stopOnCopy，不加limit）获取所有日志，
  /// 然后取最小的revision作为ROOT_TAIL
  /// 由于可能数据量很大，这里使用一个较大的limit（如10000）来获取足够的数据
  Future<int?> findRootTail(
    String sourceUrl, {
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('【SvnService.findRootTail】查找根尾（ROOT_TAIL）');
    _log('  源 URL: $sourceUrl');
    _log('  工作目录: ${workingDirectory ?? "未指定"}');
    
    // 执行 svn log -r 1:HEAD（不加stopOnCopy，使用 limit=1 获取第一条数据，即最早的数据）
    // 注意：SVN log 返回的是按时间倒序（最新的在前），所以需要取最后一个（最小的revision）
    final args = ['log', sourceUrl, '-r', '1:HEAD', '-l', '1'];
    _log('  命令: svn ${args.join(' ')} --xml');
    _log('  说明: 获取从r1到HEAD的日志，取最小的revision作为ROOT_TAIL');
    
    final result = await _runSvnCommand(
      args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );
    
    final xmlOutput = result.stdout.toString();
    final entries = SvnXmlParser.parseLog(xmlOutput);
    
    int? rootTail;
    if (entries.isNotEmpty) {
      // 获取最早的revision（最小的revision）
      rootTail = entries.map((e) => e.revision).reduce((a, b) => a < b ? a : b);
      _log('  ✓ 找到根尾（ROOT_TAIL）: r$rootTail');
    } else {
      _log('  ⚠ 未找到根尾，默认使用 r1');
      rootTail = 1; // 默认ROOT_TAIL是1
    }
    
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return rootTail;
  }

  /// 获取 SVN 日志
  /// 
  /// [url] SVN URL
  /// [limit] 返回的日志条数
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [startRevision] 起始版本号（可选，从指定版本开始读取）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  /// 
  /// 注意：
  /// - 这是一个底层方法，只负责执行 SVN 命令
  /// - 不包含任何业务逻辑（如分支点查找）
  /// - 如果需要查找分支点，请使用 findBranchPoint() 方法
  /// - [reverseOrder] 如果为 true，从 startRevision 向更旧的版本读取；否则向 HEAD 读取
  Future<String> log(
    String url, {
    int limit = 200,
    String? workingDirectory,
    int? startRevision,
    bool reverseOrder = false,
    String? username,
    String? password,
  }) async {
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('【SvnService.log】开始读取 SVN 日志');
    _log('  URL: $url');
    _log('  限制条数: $limit');
    _log('  startRevision: ${startRevision != null ? "r$startRevision" : "未指定（从最新开始）"}');
    _log('  workingDirectory: ${workingDirectory ?? "未指定"}');
    
    // 构建命令参数（使用 XML 输出）
    final args = ['log', url];
    
    if (startRevision != null) {
      if (reverseOrder) {
        // 从指定版本向更旧的版本读取（用于加载更多历史数据）
        args.addAll(['-r', '$startRevision:1', '-l', limit.toString()]);
        _log('  从 r$startRevision 向更旧版本读取');
      } else {
        // 从指定版本向 HEAD 读取
        args.addAll(['-r', '$startRevision:HEAD', '-l', limit.toString()]);
        _log('  从 r$startRevision 向 HEAD 读取');
      }
    } else {
      // 从最新开始读取（不限制版本范围）
      args.addAll(['-l', limit.toString()]);
      _log('  从最新开始读取 $limit 条日志（不限制版本范围）');
    }
    
    _log('  命令参数: ${args.join(' ')}');
    
    // 使用 XML 输出
    final result = await _runSvnCommand(
      args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );
    
    final xmlOutput = result.stdout.toString();
    _log('  ✓ SVN 日志读取完成');
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // 解析 XML 输出
    final entries = SvnXmlParser.parseLog(xmlOutput);
    _log('成功解析 ${entries.length} 条日志');
    _log('成功读取 SVN 日志');
    _log('=== SVN 日志读取完成 ===');
    
    // 返回 XML 输出（保持向后兼容）
    return xmlOutput;
  }

  /// 执行 SVN merge
  /// 
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// [targetWc] 目标工作副本路径
  /// [dryRun] 是否为预览模式
  Future<void> merge(
    String sourceUrl,
    int revision,
    String targetWc, {
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    _log('合并 r$revision 从 $sourceUrl 到 $targetWc...');
    
    final args = ['merge', '-c', revision.toString(), sourceUrl, '.'];
    if (dryRun) {
      args.insert(1, '--dry-run');
      _log('以 dry-run 模式执行 merge（不修改本地文件，仅预览）');
    }
    
    await _runSvnCommand(
      args,
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    _log('合并完成');
  }

  /// 执行 SVN commit
  Future<void> commit(
    String targetWc,
    String message, {
    String? username,
    String? password,
  }) async {
    _log('提交更改...');
    
    await _runSvnCommand(
      ['commit', '-m', message],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    _log('提交成功');
  }

  /// 执行 SVN update
  /// 
  /// 返回结果，可以检查 exitCode 判断是否成功
  Future<SvnProcessResult> update(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    _log('更新工作副本: $targetWc');
    
    final result = await _runSvnCommand(
      ['update'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    if (result.exitCode == 0) {
      _log('更新完成');
    } else {
      _log('更新失败: ${result.stderr}');
    }
    return result;
  }

  /// 执行 SVN revert
  /// 
  /// 返回结果，可以检查 exitCode 判断是否成功
  /// [recursive] 是否递归还原（默认 false）
  Future<SvnProcessResult> revert(
    String targetWc, {
    bool recursive = false,
    String? username,
    String? password,
  }) async {
    _log('还原本地修改: $targetWc (recursive: $recursive)');
    
    final args = recursive ? ['revert', '-R', '.'] : ['revert', '.'];
    final result = await _runSvnCommand(
      args,
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    if (result.exitCode == 0) {
      _log('还原完成');
    } else {
      _log('还原失败: ${result.stderr}');
    }
    return result;
  }

  /// 执行 SVN cleanup
  /// 
  /// 返回结果，可以检查 exitCode 判断是否成功
  Future<SvnProcessResult> cleanup(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    _log('清理工作副本: $targetWc');
    
    final result = await _runSvnCommand(
      ['cleanup'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    if (result.exitCode == 0) {
      _log('清理完成');
    } else {
      _log('清理失败: ${result.stderr}');
    }
    return result;
  }

  /// 检查工作副本是否有冲突
  Future<bool> hasConflicts(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final result = await _runSvnCommand(
      ['status'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );
    
    final output = result.stdout.toString();
    for (final line in output.split('\n')) {
      if (line.isNotEmpty && line[0] == 'C') {
        return true;
      }
    }
    
    return false;
  }

  /// 获取 SVN info
  /// 
  /// [path] 工作副本路径或 URL
  /// [item] 要获取的信息项（如 'url', 'revision' 等），如果为 null 则返回完整 XML
  Future<String> getInfo(
    String path, {
    String? item,
    String? username,
    String? password,
  }) async {
    AppLogger.svn.info('【SvnService.getInfo】获取 SVN 信息');
    AppLogger.svn.info('  路径: $path');
    AppLogger.svn.info('  项目: ${item ?? "全部"}');
    
    final args = ['info', path];
    if (item != null) {
      args.insert(1, '--show-item');
      args.insert(2, item);
    }
    
    final result = await _runSvnCommand(
      args,
      useXml: item == null, // 如果指定了 item，使用文本输出；否则使用 XML
      workingDirectory: path.startsWith('http') ? null : path,
      username: username,
      password: password,
    );
    
    final output = result.stdout.toString().trim();
    
    // 如果使用 XML，解析并提取 URL
    if (item == null) {
      final infoMap = SvnXmlParser.parseInfo(output);
      final url = infoMap['url'] ?? output;
      AppLogger.svn.info('  提取的 URL: $url');
      return url;
    }
    
    AppLogger.svn.info('  返回结果: $output');
    return output;
  }

  /// 确保本地目标工作副本存在
  /// 
  /// 返回该工作副本对应的远端 URL
  Future<String> ensureWorkingCopy(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final dir = Directory(targetWc);
    if (!await dir.exists()) {
      throw SvnException(
        '目标工作副本目录不存在或不是目录',
        command: 'check directory',
        output: targetWc,
      );
    }
    
    _log('使用已存在的目标工作副本目录：$targetWc');
    
    // 确认是工作副本，并拿到 URL
    final url = await getInfo(targetWc, username: username, password: password);
    return url;
  }

  /// 自动合并并提交（带重试机制）
  /// 
  /// 功能：
  /// 1. 确保工作副本存在
  /// 2. 循环：
  ///    - update
  ///    - merge
  ///    - 检查冲突
  ///    - commit（如果 out-of-date 则重试）
  Future<void> autoMergeAndCommit({
    required String sourceUrl,
    required int revision,
    required String targetWc,
    int maxRetries = 5,
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    final targetUrl = await ensureWorkingCopy(
      targetWc,
      username: username,
      password: password,
    );
    
    if (dryRun) {
      // dry-run 模式只做一次 merge 预览
      await update(targetWc, username: username, password: password);
      await merge(
        sourceUrl,
        revision,
        targetWc,
        dryRun: true,
        username: username,
        password: password,
      );
      _log('dry-run 结束，请检查上面的 merge 预览结果');
      return;
    }
    
    int attempt = 0;
    while (attempt <= maxRetries) {
      _log('合并+提交尝试次数：${attempt + 1}/${maxRetries + 1}');
      
      // 1) 更新
      await update(targetWc, username: username, password: password);
      
      // 2) merge
      await merge(
        sourceUrl,
        revision,
        targetWc,
        username: username,
        password: password,
      );
      
      // 3) 检查冲突
      if (await hasConflicts(targetWc, username: username, password: password)) {
        throw SvnException(
          '检测到合并冲突，请在本地解决冲突（svn resolve 等）后手动提交',
          command: 'merge',
        );
      }
      
      // 4) 提交
      try {
        final commitMsg = 'Auto-merge r$revision from $sourceUrl to $targetUrl';
        await commit(targetWc, commitMsg, username: username, password: password);
        _log('提交成功');
        return;
      } on SvnException catch (e) {
        final msg = e.output.toLowerCase();
        
        // 判断是否为 out-of-date 错误
        if (msg.contains('out-of-date') || msg.contains('out of date')) {
          attempt++;
          if (attempt > maxRetries) {
            _log('因为远端持续有新提交导致多次 out-of-date，已达到最大重试次数');
            rethrow;
          } else {
            _log('提交时检测到 out-of-date，将重新更新并重试合并+提交...');
            continue;
          }
        } else {
          // 其他错误直接抛出
          rethrow;
        }
      }
    }
  }

  /// 批量执行多个 revision 的合并
  /// 
  /// 这是一个便利方法，用于依次合并多个 revision
  Future<void> batchMerge({
    required String sourceUrl,
    required List<int> revisions,
    required String targetWc,
    int maxRetries = 5,
    String? username,
    String? password,
    Function(int current, int total)? onProgress,
  }) async {
    _log('开始批量合并 ${revisions.length} 个 revision...');
    
    for (int i = 0; i < revisions.length; i++) {
      final rev = revisions[i];
      _log('开始处理 revision r$rev (${i + 1}/${revisions.length})...');
      
      onProgress?.call(i + 1, revisions.length);
      
      await autoMergeAndCommit(
        sourceUrl: sourceUrl,
        revision: rev,
        targetWc: targetWc,
        maxRetries: maxRetries,
        username: username,
        password: password,
      );
      
      _log('r$rev 处理完成');
    }
    
    _log('所有 revision 已处理完成');
  }

  /// 检查 revision 是否已经合并到目标工作副本
  /// 
  /// 使用标准的 SVN mergeinfo 命令检查
  /// [sourceUrl] 源 URL
  /// [revision] 要检查的版本号
  /// [targetWc] 目标工作副本路径
  /// 
  /// 返回 true 表示已合并，false 表示未合并
  /// 
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<bool> isRevisionMerged({
    required String sourceUrl,
    required int revision,
    required String targetWc,
    String? username,
    String? password,
  }) async {
    try {
      _log('检查 revision r$revision 是否已合并到 $targetWc');
      // 使用 svn mergeinfo 命令检查（mergeinfo 不支持 --xml，使用文本输出）
      final result = await _runSvnCommand(
        ['mergeinfo', '--show-revs', 'merged', sourceUrl, targetWc],
        useXml: false,  // mergeinfo 不支持 XML
        workingDirectory: targetWc,
        username: username,
        password: password,
      );
      
      final output = result.stdout.toString();
      // 解析文本输出（格式：r12345 或 r12345\nr12346\n...）
      final revisionPattern = RegExp(r'r(\d+)');
      final matches = revisionPattern.allMatches(output);
      
      for (final match in matches) {
        final rev = int.tryParse(match.group(1)!);
        if (rev == revision) {
          _log('✓ revision r$revision 已合并到目标工作副本');
          return true;
        }
      }
      
      _log('✗ revision r$revision 未合并到目标工作副本');
      return false;
    } catch (e, stackTrace) {
      // 如果命令失败（例如工作副本不存在或不是工作副本），返回 false
      _log('⚠ 检查合并状态失败: $e，假设未合并');
      AppLogger.svn.error('检查合并状态异常', e, stackTrace);
      return false;
    }
  }

  /// 批量检查多个 revision 的合并状态
  /// 
  /// 返回一个 Map，key 是 revision，value 是是否已合并
  /// 
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<Map<int, bool>> checkMergedStatus({
    required String sourceUrl,
    required List<int> revisions,
    required String targetWc,
    String? username,
    String? password,
  }) async {
    final result = <int, bool>{};
    
    _log('批量检查 ${revisions.length} 个 revision 的合并状态');
    
    // 先获取所有已合并的 revision（mergeinfo 不支持 XML，使用文本输出）
    try {
      final mergeinfoResult = await _runSvnCommand(
        ['mergeinfo', '--show-revs', 'merged', sourceUrl, targetWc],
        useXml: false,  // mergeinfo 不支持 XML
        workingDirectory: targetWc,
        username: username,
        password: password,
      );
      
      final output = mergeinfoResult.stdout.toString();
      // 解析文本输出（格式：r12345 或 r12345\nr12346\n...）
      final revisionPattern = RegExp(r'r(\d+)');
      final mergedRevisions = revisionPattern
          .allMatches(output)
          .map((m) => int.tryParse(m.group(1)!))
          .where((r) => r != null)
          .cast<int>()
          .toSet();
      
      _log('已合并的 revision 数量: ${mergedRevisions.length}');
      
      // 检查每个 revision
      for (final rev in revisions) {
        result[rev] = mergedRevisions.contains(rev);
      }
    } catch (e, stackTrace) {
      // 如果命令失败，所有 revision 都标记为未合并
      _log('⚠ 批量检查合并状态失败: $e，假设所有 revision 都未合并');
      AppLogger.svn.error('批量检查合并状态异常', e, stackTrace);
      for (final rev in revisions) {
        result[rev] = false;
      }
    }
    
    return result;
  }

  /// 获取所有已合并的 revision
  /// 
  /// 返回一个 Set，包含所有已合并的 revision
  /// 
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<Set<int>> getAllMergedRevisions({
    required String sourceUrl,
    required String targetWc,
    String? username,
    String? password,
  }) async {
    _log('获取所有已合并的 revision: $sourceUrl -> $targetWc');
    
    try {
      final mergeinfoResult = await _runSvnCommand(
        ['mergeinfo', '--show-revs', 'merged', sourceUrl, targetWc],
        useXml: false,  // mergeinfo 不支持 XML
        workingDirectory: targetWc,
        username: username,
        password: password,
      );
      
      final output = mergeinfoResult.stdout.toString();
      // 解析文本输出（格式：r12345 或 r12345\nr12346\n...）
      final revisionPattern = RegExp(r'r(\d+)');
      final mergedRevisions = revisionPattern
          .allMatches(output)
          .map((m) => int.tryParse(m.group(1)!))
          .where((r) => r != null)
          .cast<int>()
          .toSet();
      
      _log('已合并的 revision 数量: ${mergedRevisions.length}');
      return mergedRevisions;
    } catch (e, stackTrace) {
      _log('⚠ 获取已合并的 revision 失败: $e');
      AppLogger.svn.error('获取已合并的 revision 异常', e, stackTrace);
      return {};
    }
  }

  /// 从本地工作副本读取 svn:mergeinfo 属性（快速，无网络请求）
  /// 
  /// 返回指定源 URL 已合并的 revision 集合
  /// 
  /// 这个方法比 getAllMergedRevisions 快得多，因为：
  /// 1. 只读取本地属性，不需要网络请求
  /// 2. 直接解析 mergeinfo 格式，不需要 SVN 服务器计算
  /// 
  /// [sourceUrl] 源 URL（用于匹配 mergeinfo 中的路径）
  /// [targetWc] 目标工作副本路径
  Future<Set<int>> getMergedRevisionsFromPropget({
    required String sourceUrl,
    required String targetWc,
  }) async {
    _log('从本地属性读取 mergeinfo: $targetWc');
    
    try {
      // 使用 svn propget 读取本地 mergeinfo 属性
      final result = await _runSvnCommand(
        ['propget', 'svn:mergeinfo', targetWc],
        useXml: false,
        workingDirectory: targetWc,
      );
      
      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        _log('本地 mergeinfo 属性为空');
        return {};
      }
      
      // 解析 mergeinfo 格式
      // 格式: /path/to/source:rev1,rev2-rev3,rev4
      // 例如: /trunk:584436-599500,599502,599747
      final mergedRevisions = <int>{};
      
      // 从 sourceUrl 提取路径部分用于匹配
      // 例如: http://svn.example.com/repo/trunk -> /trunk
      final sourceUri = Uri.parse(sourceUrl);
      final sourcePath = sourceUri.path;
      
      // 解析每一行 mergeinfo
      for (final line in output.split('\n')) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        // 格式: /path:revisions
        final colonIndex = trimmedLine.lastIndexOf(':');
        if (colonIndex == -1) continue;
        
        final path = trimmedLine.substring(0, colonIndex);
        final revisionsStr = trimmedLine.substring(colonIndex + 1);
        
        // 检查路径是否匹配源 URL
        // 支持部分匹配（例如 /trunk 匹配 /OSGame/Client_proj/trunk）
        if (!sourcePath.endsWith(path) && !path.endsWith(sourcePath.split('/').last)) {
          // 尝试更宽松的匹配：检查路径的最后一部分
          final sourceLastPart = sourcePath.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
          final pathLastPart = path.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
          if (sourceLastPart != pathLastPart) {
            continue;
          }
        }
        
        // 解析 revision 范围
        // 格式: rev1,rev2-rev3,rev4
        for (final part in revisionsStr.split(',')) {
          final trimmedPart = part.trim();
          if (trimmedPart.isEmpty) continue;
          
          if (trimmedPart.contains('-')) {
            // 范围格式: start-end
            final rangeParts = trimmedPart.split('-');
            if (rangeParts.length == 2) {
              final start = int.tryParse(rangeParts[0].trim());
              final end = int.tryParse(rangeParts[1].trim());
              if (start != null && end != null) {
                for (var rev = start; rev <= end; rev++) {
                  mergedRevisions.add(rev);
                }
              }
            }
          } else {
            // 单个 revision
            final rev = int.tryParse(trimmedPart);
            if (rev != null) {
              mergedRevisions.add(rev);
            }
          }
        }
      }
      
      _log('从本地属性解析到 ${mergedRevisions.length} 个已合并的 revision');
      return mergedRevisions;
    } catch (e, stackTrace) {
      _log('⚠ 从本地属性读取 mergeinfo 失败: $e');
      AppLogger.svn.error('从本地属性读取 mergeinfo 异常', e, stackTrace);
      return {};
    }
  }

  /// 获取 revision 涉及的文件列表
  /// 
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// 
  /// 返回文件路径列表（相对于仓库根目录）
  Future<List<String>> getRevisionFiles({
    required String sourceUrl,
    required int revision,
    String? username,
    String? password,
  }) async {
    try {
      _log('获取 revision r$revision 涉及的文件列表');
      // 使用 svn log --verbose --xml 获取文件列表
      final result = await _runSvnCommand(
        ['log', '-r', revision.toString(), '--verbose', sourceUrl],
        useXml: true,
        username: username,
        password: password,
      );
      
      final xmlOutput = result.stdout.toString();
      // 解析 XML 输出
      final files = SvnXmlParser.parseLogFiles(xmlOutput);
      
      _log('revision r$revision 涉及 ${files.length} 个文件');
      return files;
    } catch (e, stackTrace) {
      _log('❌ 获取文件列表失败: $e');
      AppLogger.svn.error('获取文件列表异常', e, stackTrace);
      return [];
    }
  }
}

/// SVN 异常类
class SvnException implements Exception {
  final String message;
  final String? command;
  final int? exitCode;
  final String output;

  SvnException(
    this.message, {
    this.command,
    this.exitCode,
    this.output = '',
  });

  @override
  String toString() {
    final buffer = StringBuffer('SvnException: $message');
    if (command != null) {
      buffer.write('\nCommand: $command');
    }
    if (exitCode != null) {
      buffer.write('\nExit code: $exitCode');
    }
    if (output.isNotEmpty) {
      buffer.write('\nOutput: $output');
    }
    return buffer.toString();
  }

  /// 检查是否需要认证
  bool get needsAuth {
    final lower = output.toLowerCase();
    return lower.contains('authorization failed') ||
        lower.contains('authentication') ||
        lower.contains('could not authenticate') ||
        lower.contains('no more credentials');
  }
}

