/// SVN 工作副本操作管理器
///
/// 采用门面模式 (Facade Pattern) + 互斥锁模式 (Mutex Pattern)
///
/// 设计原则：
/// - 单一职责原则 (SRP)：只负责工作副本操作的调度和锁管理
/// - 门面模式：提供统一的接口来访问所有工作副本操作
/// - 互斥锁模式：确保同一工作副本同一时间只有一个操作在执行
///
/// 使用方式：
/// ```dart
/// final wcManager = WorkingCopyManager();
///
/// // 执行 update 操作（自动加锁/解锁）
/// await wcManager.update(targetWc);
///
/// // 执行 revert 操作
/// await wcManager.revert(targetWc);
///
/// // 检查是否正在操作中
/// if (wcManager.isLocked(targetWc)) {
///   print('工作副本正在操作中...');
/// }
/// ```
///
/// 注意事项：
/// - 所有对工作副本的操作都必须通过此管理器
/// - 禁止直接调用 SvnService 的工作副本操作方法
/// - 操作会自动排队，后续操作需要等待前一个完成

/// **R143 Stream / StreamController / StreamSubscription 配对协议审计**
///
/// 维度：dart:async Stream 表面（与 R142 时间轴正交，与 R136 取消信号正交）
///
/// **lib 全集（仅 1 个 StreamController，0 个 listen）**：
/// | # | 文件:行                                | 角色          | broadcast | sink 站点                        | close 站点 |
/// |---|---------------------------------------|---------------|-----------|----------------------------------|-----------|
/// | A | working_copy_manager.dart:291         | producer 单点 | broadcast | acquire:366, release:390         | dispose:566 |
///
/// **listen / StreamSubscription / StreamBuilder 全集**：
/// - lib/.listen( 站点：**0 个**（即站点 A 的 `statusStream` 暴露给消费者，但 lib 内
///   无任何 `.listen(`/`StreamBuilder` 消费 —— consumer 全在 widget 树外，由调用方
///   自管订阅生命周期）。本协议只锁 producer 端 schema。
/// - StreamSubscription 字段：**0 个**（无需 cancel 配对验证）。
/// - StreamSink / EventSink 直接使用：**0 个**（仅 `IOSink` 在 logger，属 dart:io
///   sink，不在 dart:async Stream 协议范围）。
/// - Stream.periodic / Stream.fromFuture / Stream.fromIterable：**0 个**（R142 已锁）。
///
/// **三档配对协议（按 producer 端 lifecycle 切分）**：
/// - 档 1：sync producer（`StreamController()` 单订阅，无 broadcast，sink/close
///   配对受 single-listener 约束）—— **lib 0 个**。
/// - 档 2：broadcast producer（`StreamController.broadcast()`，多订阅；close 不
///   保证订阅者收到 close event）—— **lib 1 个**：站点 A。
/// - 档 3：cold stream producer（`Stream.fromIterable` / generator `async*`，无
///   显式 controller，订阅时才计算）—— **lib 0 个**。
///
/// **B 系四律（broadcast producer 子协议）**：
/// - B1 Owner 单点律：StreamController 必须由唯一 owner 持有 —— `WorkingCopyManager`
///   是单例 service，`_statusController` 是 final private 字段，无第二处构造。
/// - B2 Sink 内聚律：`controller.add(x)` 调用必须**全部在 owner 类内**，禁止把
///   controller 暴露给外部 push event —— 仅 `_acquireLock`/`_releaseLock` 两站点
///   add，外部只见 `Stream<...> get statusStream` 只读 view。
/// - B3 Close-once 律：`StreamController.close()` 在 `dispose()` 单点调用，dispose
///   走 R121 档 3（fire-and-forget void）；幂等靠 `StreamController` 内部
///   `_state.isClosed` 自检（重复 dispose 不抛错）。
/// - B4 Schema 单值律：本档 broadcast 流的 event payload 类型 `WcLockInfo?` —— null
///   表示"已释放"，非 null 表示"已获取/状态变更"；档 2 broadcast 不允许携带 error
///   event（`addError` 0 站点），异常路径走 throw + 日志，不灌进 stream。
///
/// **R121 ↔ R143 正交叠加**：站点 A `dispose()` 同时是 R121 档 3（资源释放协议
/// fire-and-forget）+ R143 档 2（broadcast producer lifecycle）—— 同站点双协议
/// 不同档位号在 R142 已形式化，本轮第 2 次实例（同站点 R121-3 / R143-2）。
///
/// **R136 ↔ R143 正交叠加**：R136 取消信号协议中的 `_cancelRequestedJobId` 用
/// "标志位 + watcher polling" 实现取消语义（doc 见 merge_execution_state.dart:1493
/// "不另起 Completer / Stream / CancellationToken"）；R143 这里印证了 lib 没把
/// Stream 当作取消通道用 —— 唯一 broadcast stream 只承载状态变更广播，与取消正交。
///
/// **故意不做**：
/// 1. 不抽 `WcLockStatusBroadcaster` helper —— 单点 controller 抽 helper 反而模糊
///    owner 边界，B1 owner 单点律恰好阻止此抽取。
/// 2. 不审计 `StreamSink<T>` 抽象 —— lib 仅 `IOSink`，已在 R140 logger sink 通道
///    协议覆盖，与 dart:async Stream 协议是不同抽象层。
/// 3. 不为 statusStream 加 buffer/replay —— 当前 broadcast 缺省（订阅前的 event
///    丢弃）是 widget tree 期望（订阅方初次 attach 应从 `getStatus()` 主动拉一次
///    状态，再靠 stream 增量通知）。
/// 4. 不强制 `StreamController` 改 single-subscription —— 多 widget 同时订阅锁
///    状态是 UI 树的合理需求（多 panel 都关心 wc 锁），强制 single 会引入 fan-out
///    封装层。
///
/// **N-tuple invariance 模板第 23 次复用 / 第 7 次维度切换**（首次"Stream producer
/// lifecycle"维度切换；前 6 次：错误/等待/释放/触发/取消/量+通道+类型+时间轴）。
/// **doc-only audit R85+ N+20 次复用**。
/// **`_stripComments` helper 第 13 次复用**（test 端）。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'logger_service.dart';
import 'svn_service.dart';
import 'mergeinfo_cache_service.dart';

/// 把工作副本路径规范化为锁表所用的 key。
///
/// 规则（与 Windows 大小写不敏感语义保持一致）：
/// 1. 全部转小写。
/// 2. 反斜杠统一替换为正斜杠。
/// 3. 末尾连续的斜杠全部去掉。
///
/// 注意：本函数不做绝对/相对路径解析，也不去掉中间的 `..` / `.`。
/// 这两点都按"上层调用方传进来的就是合法路径"假设处理，避免依赖
/// `path` 包导致测试需要平台环境。
@visibleForTesting
String normalizeWorkingCopyPath(String path) {
  return path
      .toLowerCase()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
}

/// 解析操作的可读标签：优先 `description`，回落到 `operationType.label`。
///
/// **消除 working_copy_manager.dart 内部 3 处完全相同的 `description ?? operationType.label`**：
/// - [WcLockInfo.toString] (line 140)：渲染锁详情字符串
/// - [WorkingCopyManager._acquireLock] (line 224)：日志 "已获取工作副本锁"
/// - [describeWcOperation] (本文件 line 63)：lockInfo 非空分支
///
/// `main_screen_v3.dart` 中 `describeLockOperation` 也走同样逻辑，但目前
/// 不强制其依赖此函数——保留独立副本以避免 UI 层循环依赖到 service 层。
/// 如果未来发现两边出现行为漂移，可以让 main_screen 也委托过来。
@visibleForTesting
String resolveOperationLabel({
  String? description,
  required WcOperationType operationType,
}) {
  return description ?? operationType.label;
}

/// 把当前锁住工作副本的操作翻译为可读描述。
///
/// 与 `main_screen_v3.dart` 中的 `describeLockOperation` 同义，复制到这里以
/// 让锁内部日志（"等待中..."）不再反向依赖 UI 层。优先级：
/// `description` > `operationType.label` > `'当前操作'`（lockInfo 为 null）。
@visibleForTesting
String describeWcOperation(WcLockInfo? lockInfo) {
  if (lockInfo == null) return '当前操作';
  return resolveOperationLabel(
    description: lockInfo.description,
    operationType: lockInfo.operationType,
  );
}

/// 判断 revert 之后是否应该刷新 mergeinfo 缓存。
///
/// **契约**（消除 [WorkingCopyManager.revert] 中 4 段 `&&` 的复合条件）：
/// - `exitCode == 0`：revert 必须成功，失败时仓库 mergeinfo 没动，刷新是浪费
/// - `refreshMergeInfo == true`：调用方显式开关，默认 true 但允许调用方在 dryRun
///   或批量 revert 场景关掉
/// - `sourceUrl != null && sourceUrl.isNotEmpty`：缺源 URL 时 mergeinfo 无法定位
///   要清除哪条缓存——历史行为是静默跳过，不当作错误
///
/// **不做**的事：
/// - 不读 `targetWc`（缓存 key 是 `sourceUrl`，targetWc 仅作为 SVN 调用上下文）
/// - 不 trim `sourceUrl`（与 [isMergeInfoArgsValid] 同步保留"仅空白视作有效"语义）
@visibleForTesting
bool shouldRefreshMergeInfoAfterRevert({
  required int exitCode,
  required bool refreshMergeInfo,
  required String? sourceUrl,
}) {
  return exitCode == 0 &&
      refreshMergeInfo &&
      sourceUrl != null &&
      sourceUrl.isNotEmpty;
}

/// 把 [WcLockInfo] 渲染成调试字符串。
///
/// 把 `elapsed` 作为外部输入而不是从 `DateTime.now()` 现算，让函数纯净
/// 可测。生产代码里 `WcLockInfo.toString()` 仍然走当前耗时。
@visibleForTesting
String formatWcLockInfo({
  required String workingCopy,
  required String label,
  required Duration elapsed,
}) {
  return 'WcLockInfo($workingCopy, $label, elapsed: ${elapsed.inSeconds}s)';
}

/// 渲染"工作副本被另一个操作占用、当前线程进入等待"的日志行。
///
/// **契约**：固定模板 `'工作副本 $workingCopy 正在执行$currentOperation，等待中...'`。
/// 行首**不带缩进**——这是 svn 子系统下的顶层提示，与 `[SVN 命令执行]` 等
/// 入口日志同级别。
///
/// **不**对入参做任何防御：
/// - `workingCopy` 为空串会渲染成 `'工作副本  正在执行...'`（双空格），方便
///   暴露上游"传空路径"这种 bug，比静默兜底为"未知"更利于排查。
/// - `currentOperation` 同理；调用点都来自 `describeWcOperation(...)`，已经
///   在内部对 `null lockInfo` 兜底成了 `'当前操作'`，本函数不重复防御。
@visibleForTesting
String formatWcLockWaitingLine({
  required String workingCopy,
  required String currentOperation,
}) {
  return '工作副本 $workingCopy 正在执行$currentOperation，等待中...';
}

/// 渲染"已获取工作副本锁"的日志行。
///
/// **契约**：固定模板 `'已获取工作副本锁: $workingCopy ($operationLabel)'`，
/// 与 [formatWcLockReleasedLine] 形成"获取/释放"对仗。
///
/// `operationLabel` 由调用方通过 [resolveOperationLabel] 预处理（优先
/// `description`、回落 `operationType.label`），本函数只做模板拼接。
@visibleForTesting
String formatWcLockAcquiredLine({
  required String workingCopy,
  required String operationLabel,
}) {
  return '已获取工作副本锁: $workingCopy ($operationLabel)';
}

/// 渲染"释放工作副本锁"的日志行（带耗时）。
///
/// **契约**：固定模板 `'释放工作副本锁: $workingCopy (耗时: ${seconds}s)'`，
/// 单位**恒为秒**，**不**做"超过 60s 自动转分钟"的自适应——日志走机读路径，
/// 固定单位最稳。
///
/// `elapsed` 作为参数注入而不是从 `DateTime.now()` 现算，与
/// [formatWcLockInfo] 同样保持纯函数可测。`elapsed.inSeconds` 会向下截断
/// （`Duration` 的语义），调用方需要小数级精度时应在外部预先格式化。
///
/// **`elapsed == null`**：渲染成 `'(耗时: nulls)'`——这条路径只会在 `_lockInfos`
/// 与 `_locks` 出现键不一致的异常态触发；旧代码的 `lockInfo?.elapsed.inSeconds`
/// 同样会得到 `null`，模板字面 `'nulls'` 在日志里突兀地刺眼，反而能促使开发
/// 者去查"为什么 lockInfo 没了"，比兜底成 `'0s'` 静默更利于排查。
///
/// **不**对负值 `elapsed` 做防御：`Duration` 允许负值但生产代码里
/// `DateTime.now().difference(startTime)` 不会出现负值，传负值是上游 bug
/// 应当暴露。**单测显式锁定**负值透传渲染。
@visibleForTesting
String formatWcLockReleasedLine({
  required String workingCopy,
  required Duration? elapsed,
}) {
  return '释放工作副本锁: $workingCopy (耗时: ${elapsed?.inSeconds}s)';
}

/// 渲染"刷新 mergeinfo 缓存失败"的 warn 日志行。
///
/// **契约**：固定模板 `'刷新 mergeinfo 缓存失败: $error'`。
/// `error` 走 `Object.toString()`——异常对象、字符串、null 全部经 `$`
/// 内插转字符串，**不**做类型分流。
///
/// **设计意图**：把 `catch (e)` 块里 1 行 `warn(...)` 的字面格式锁死，
/// 避免有人"美化"成"刷新 mergeinfo 缓存失败（异常类型: ...）"或加堆栈
/// 详情——堆栈走专门的 `error(... , e, stackTrace)` API，warn 走纯文本。
@visibleForTesting
String formatMergeInfoRefreshFailureLine(Object error) {
  return '刷新 mergeinfo 缓存失败: $error';
}

/// 操作类型枚举
enum WcOperationType {
  update,
  switchBranch,
  revert,
  cleanup,
  merge,
  commit,
  status,
  info,
}

extension WcOperationTypeX on WcOperationType {
  String get label {
    switch (this) {
      case WcOperationType.update:
        return '更新';
      case WcOperationType.switchBranch:
        return '切换';
      case WcOperationType.revert:
        return '还原';
      case WcOperationType.cleanup:
        return '清理';
      case WcOperationType.merge:
        return '合并';
      case WcOperationType.commit:
        return '提交';
      case WcOperationType.status:
        return '状态检查';
      case WcOperationType.info:
        return '信息查询';
    }
  }
}

/// 操作状态
enum WcOperationStatus {
  idle, // 空闲
  running, // 运行中
  waiting, // 等待中（队列中）
}

/// 工作副本锁信息
class WcLockInfo {
  final String workingCopy;
  final WcOperationType operationType;
  final DateTime startTime;
  final String? description;

  WcLockInfo({
    required this.workingCopy,
    required this.operationType,
    required this.startTime,
    this.description,
  });

  Duration get elapsed => DateTime.now().difference(startTime);

  @override
  String toString() => formatWcLockInfo(
        workingCopy: workingCopy,
        label: resolveOperationLabel(
          description: description,
          operationType: operationType,
        ),
        elapsed: elapsed,
      );
}

/// 工作副本操作管理器
///
/// 单例模式，全局唯一实例
class WorkingCopyManager {
  /// 单例实例
  static final WorkingCopyManager _instance = WorkingCopyManager._internal();
  factory WorkingCopyManager() => _instance;
  WorkingCopyManager._internal();

  /// 测试钩子：子类构造 fake。
  @visibleForTesting
  WorkingCopyManager.forTesting();

  /// SVN 服务
  final SvnService _svnService = SvnService();

  /// MergeInfo 缓存服务
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();

  /// 工作副本锁映射
  /// key: 工作副本路径（规范化后）
  /// value: Completer，用于等待锁释放
  final Map<String, Completer<void>> _locks = {};

  /// 当前锁信息
  final Map<String, WcLockInfo> _lockInfos = {};

  /// 操作状态变化通知
  final _statusController = StreamController<WcLockInfo?>.broadcast();

  /// 状态变化流
  Stream<WcLockInfo?> get statusStream => _statusController.stream;

  /// 规范化工作副本路径
  String _normalizePath(String path) => normalizeWorkingCopyPath(path);

  /// 检查工作副本是否被锁定
  bool isLocked(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    return _locks.containsKey(normalized);
  }

  /// 获取当前锁信息
  WcLockInfo? getLockInfo(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    return _lockInfos[normalized];
  }

  /// 获取所有锁信息
  List<WcLockInfo> get allLockInfos => _lockInfos.values.toList();

  /// 获取当前操作状态
  WcOperationStatus getStatus(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    if (_locks.containsKey(normalized)) {
      return WcOperationStatus.running;
    }
    return WcOperationStatus.idle;
  }

  /// 获取锁（内部方法）
  ///
  /// 如果工作副本已被锁定，等待锁释放
  ///
  /// **R120 等待协议档 1：信号驱动等待（Completer.future）**
  /// 等价于 R98 throw 三档 / R119 then/catchError 三档 在等待 channel 的对应——
  /// 档 1 = 由信号源精确通知唤醒（无 polling 开销 / 无虚假唤醒）。
  /// `_releaseLock` 在锁释放时 `complete()` 一次，所有 await `future` 的等待者
  /// 同时被调度。**循环 while 而非 if 的原因**：当多个等待者排队时，唤醒后下一个
  /// 等待者可能再次抢到 _locks 已被新持有者占据的状态，需要继续等待新 Completer。
  /// 不可改成 `if` —— 改 `if` 会让第二个等待者跳过 `await` 直接进入"创建新锁"分支
  /// 与正在持有锁的进程产生竞争。
  Future<void> _acquireLock(String workingCopy, WcOperationType operationType,
      {String? description}) async {
    final normalized = _normalizePath(workingCopy);

    // 如果已有锁，等待释放
    while (_locks.containsKey(normalized)) {
      final currentOperation = describeWcOperation(_lockInfos[normalized]);
      AppLogger.svn.info(formatWcLockWaitingLine(
        workingCopy: workingCopy,
        currentOperation: currentOperation,
      ));
      await _locks[normalized]!.future;
    }

    // 创建新锁
    _locks[normalized] = Completer<void>();
    _lockInfos[normalized] = WcLockInfo(
      workingCopy: workingCopy,
      operationType: operationType,
      startTime: DateTime.now(),
      description: description,
    );

    final operationLabel = resolveOperationLabel(
      description: description,
      operationType: operationType,
    );
    AppLogger.svn.info(formatWcLockAcquiredLine(
      workingCopy: workingCopy,
      operationLabel: operationLabel,
    ));
    _statusController.add(_lockInfos[normalized]);
  }

  /// 释放锁（内部方法）
  void _releaseLock(String workingCopy) {
    final normalized = _normalizePath(workingCopy);

    if (_locks.containsKey(normalized)) {
      final lockInfo = _lockInfos[normalized];
      AppLogger.svn.info(formatWcLockReleasedLine(
        workingCopy: workingCopy,
        elapsed: lockInfo?.elapsed,
      ));

      _locks[normalized]!.complete();
      // R124 mutator 二档判据：`_locks.remove(normalized)` + `_lockInfos.remove(...)`
      // 都是 Map.remove **档 2**——key 由 `_normalizePath(workingCopy)` lookup 决
      // 定（不同平台路径分隔符归一化），不是常量。两个 Map 同时 remove 同一 key
      // 是"双结构同步释放"模式（R103 == 字段对称的对偶——R103 锁字段间相等性、
      // R124 锁两 Map key 同生命周期）；任何未来"美化"成只 remove 一个 Map 会让
      // _lockInfos 中残留 stale lock 引用导致 LockInfo 内存泄漏。
      _locks.remove(normalized);
      _lockInfos.remove(normalized);

      _statusController.add(null);
    }
  }

  /// 执行带锁的操作（内部方法）
  Future<T> _withLock<T>(
    String workingCopy,
    WcOperationType operationType,
    Future<T> Function() operation, {
    String? description,
  }) async {
    await _acquireLock(workingCopy, operationType, description: description);
    try {
      return await operation();
    } finally {
      _releaseLock(workingCopy);
    }
  }

  // ==================== 公开的操作方法 ====================

  /// SVN Update
  ///
  /// 更新工作副本到最新版本
  Future<SvnProcessResult> update(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.update,
      () => _svnService.update(workingCopy,
          username: username, password: password),
      description: '更新工作副本',
    );
  }

  /// SVN Switch
  ///
  /// 切换工作副本到指定仓库 URL。
  Future<SvnProcessResult> switchToUrl(
    String workingCopy,
    String url, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.switchBranch,
      () => _svnService.switchToUrl(
        workingCopy,
        url,
        username: username,
        password: password,
      ),
      description: '切换工作副本',
    );
  }

  /// SVN Revert
  ///
  /// 还原工作副本的本地修改
  /// [refreshMergeInfo] 是否在 revert 后刷新 mergeinfo 缓存（默认 true）
  Future<SvnProcessResult> revert(
    String workingCopy, {
    bool recursive = true,
    String? sourceUrl,
    bool refreshMergeInfo = true,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.revert,
      () async {
        final result =
            await _svnService.revert(workingCopy, recursive: recursive);

        // Revert 成功后刷新 mergeinfo 缓存
        if (shouldRefreshMergeInfoAfterRevert(
          exitCode: result.exitCode,
          refreshMergeInfo: refreshMergeInfo,
          sourceUrl: sourceUrl,
        )) {
          AppLogger.svn.info('还原后刷新 mergeinfo 缓存...');
          try {
            await _mergeInfoService.getMergedRevisions(
              sourceUrl!,
              workingCopy,
              fullRefresh: true,
            );
            AppLogger.svn.info('Mergeinfo 缓存已刷新');
          } catch (e) {
            AppLogger.svn.warn(formatMergeInfoRefreshFailureLine(e));
          }
        }

        return result;
      },
      description: '还原工作副本',
    );
  }

  /// SVN Cleanup
  ///
  /// 清理工作副本（解锁、清理未完成的操作等）
  Future<SvnProcessResult> cleanup(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.cleanup,
      () => _svnService.cleanup(workingCopy,
          username: username, password: password),
      description: '清理工作副本',
    );
  }

  /// SVN Merge
  ///
  /// 合并指定 revision 到工作副本
  Future<void> merge(
    String sourceUrl,
    int revision,
    String workingCopy, {
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.merge,
      () => _svnService.merge(
        sourceUrl,
        revision,
        workingCopy,
        dryRun: dryRun,
        username: username,
        password: password,
      ),
      description: '合并 r$revision',
    );
  }

  /// SVN Commit
  ///
  /// 提交工作副本的修改
  Future<SvnProcessResult> commit(
    String workingCopy,
    String message, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.commit,
      () => _svnService.commit(workingCopy, message,
          username: username, password: password),
      description: '提交改动',
    );
  }

  /// 释放所有资源
  ///
  /// **R121 资源释放协议档 3：fire-and-forget 同步签名型**
  /// 签名 `void dispose()` 而非 `Future<void> dispose() async` —— `StreamController.close()`
  /// 返回 `Future<void>`，**故意不 await、不返回**。**为什么 fire-and-forget**：
  /// (1) 本类作为单例 service 被 widget 树外部持有，dispose 通常发生在 app shutdown
  /// 路径，async cleanup 在 framework dispose hook 里被丢弃；(2) StreamController
  /// 的 close 内部对当前 buffered events 是否被消费做了 best-effort，调用方 await
  /// 也无法获得"所有订阅者已收到"的强保证。**对称释放语义最弱**：caller 完全无法
  /// 确认订阅者已收到 close event ——这是档 3 区别于档 1（强落盘）/档 2（同步
  /// handle 释放）的明确边界。**幂等机制**：`StreamController.close()` 内部对
  /// "已 closed" 状态自检 —— 重复调用返回同一 future、不抛错。**为什么不补 await**：
  /// 改成 `Future<void> dispose() async => await _statusController.close();` 会
  /// 破坏与 Flutter `Disposable` mixin 的 `void dispose()` 契约（widget tree 不
  /// 接受 async dispose），档位识别比"看起来更对称"重要——这是 R121 三档**签名
  /// 决定档位**的核心规则。
  void dispose() {
    _statusController.close();
  }
}
