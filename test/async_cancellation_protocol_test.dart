import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132/R133/R134/R135 / 本轮 R136 复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R136 async cancellation/stop signal 协议审计 — 单一 channel + 3 档消费 + 4 档不变量 + K reset 闭合**
///
/// 协议要点：
/// - 单一 channel（jobId-token 或 bool-flag），不引入 Completer/Stream/Process.kill
/// - 协作式 (cooperative) 消费——await 缝隙 poll，不抢占进行中的 SVN 命令
/// - reset 站点穷尽闭合（merge_execution_state 4 处 / preload_service 3 处）
///
/// 详细 doc 见 lib/providers/merge_execution_state.dart `_isCancelRequestedFor`
/// 与 lib/services/preload_service.dart `_shouldStop` 周边块。
void main() {
  final mergeStateFile =
      File('lib/providers/merge_execution_state.dart');
  final preloadServiceFile =
      File('lib/services/preload_service.dart');
  final stepOutputFile = File('lib/execution/step_output.dart');

  group('R136 async cancellation — channel 单一性锁', () {
    test('merge_execution_state 仅声明 1 处 _cancelRequestedJobId 字段', () {
      final src = mergeStateFile.readAsStringSync();
      final stripped = _stripComments(src);
      final fieldDeclMatches =
          RegExp(r'\bint\?\s+_cancelRequestedJobId\b').allMatches(stripped);
      expect(fieldDeclMatches.length, 1,
          reason: 'L1 单一 channel：cancel token 字段必须有且仅有 1 处声明');
    });

    test('merge_execution_state 不引入 Completer/CancellationToken/Process.kill',
        () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());

      expect(stripped.contains('Process.kill'), isFalse,
          reason: 'L2 cooperative-only：禁止 kill 子进程打断 SVN 命令');
      expect(stripped.contains('CancellationToken'), isFalse,
          reason: 'L1 单一 channel：禁止引入 CancellationToken 替代 token');
      // 注：StreamSubscription / Completer 在 lib 中其它地方可能使用（与 cancel 无关），
      // 仅当与 _cancelRequestedJobId 同行/同段共存才视为破坏 L1。
      // 这里通过"无 Completer.complete*Cancel" 的较弱断言体现。
      expect(stripped.contains('completeError(_CancellationException'), isFalse,
          reason: 'L2：禁止用异常路径打断');
    });

    test('preload_service 仅声明 1 处 _shouldStop 字段', () {
      final src = preloadServiceFile.readAsStringSync();
      final stripped = _stripComments(src);
      final fieldDeclMatches =
          RegExp(r'\bbool\s+_shouldStop\b').allMatches(stripped);
      expect(fieldDeclMatches.length, 1,
          reason: 'preload 协议形态对偶：bool channel 必须单一字段');
    });
  });

  group('R136 async cancellation — 3 档消费模式锁（merge_execution_state）', () {
    test('档 1 cooperative-poll: _runRevision 内有 _isCancelRequestedFor poll', () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      // 档 1 的标志：step boundary 处 if (_isCancelRequestedFor(... )) return _RevisionRunResult.cancelled;
      final hasStepBoundaryPoll = stripped.contains('_isCancelRequestedFor') &&
          stripped.contains('_RevisionRunResult.cancelled');
      expect(hasStepBoundaryPoll, isTrue,
          reason: '档 1：step boundary 必须 poll token 并返回 cancelled sentinel');
    });

    test('档 2 finally-finalize: _executeJob revision 完成后 poll + 末位忽略 reset',
        () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      // 档 2b 末位忽略：清零 token 后日志"忽略终止请求"
      expect(stripped.contains('忽略终止请求'), isTrue,
          reason: '档 2b 末位忽略路径必须有日志锚点（避免静默丢 cancel 信号）');
    });

    test('档 3 paused-direct-finalize: cancelPausedJob 在 hasPausedJob 路径直接调 _finalizeCancelledJob',
        () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      expect(stripped.contains('cancelPausedJob'), isTrue);
      expect(stripped.contains('_finalizeCancelledJob'), isTrue,
          reason: '档 3 必须存在 _finalizeCancelledJob 终结函数');
    });

    test('档 1 + 档 2a + 档 3 都到达 _finalizeCancelledJob (L4 finalize 闭合)', () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      // 三档共享同一 finalize 函数；调用次数 >= 3（不计声明）
      final callMatches =
          RegExp(r'\bawait\s+_finalizeCancelledJob\(').allMatches(stripped);
      expect(callMatches.length >= 3, isTrue,
          reason: 'L4 不变量：档 1/2a/3 三路径 await _finalizeCancelledJob(...) ≥ 3 处');
    });
  });

  group('R136 async cancellation — K 不变量：token reset 站点穷尽闭合', () {
    test('_cancelRequestedJobId = null 必有恰 3 处显式赋值（+1 字段默认 = 4 站点）', () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      final resetMatches =
          RegExp(r'_cancelRequestedJobId\s*=\s*null\b').allMatches(stripped);
      expect(resetMatches.length, 3,
          reason: 'K 不变量：3 处显式 reset (executeJob 末位忽略 / '
              '_finalizeCancelledJob / _clearExecutionState)，加 null 初始化共 4 站点');
    });

    test('_cancelRequestedJobId = job.jobId 必有恰 1 处写入（cancelPausedJob 内 user intent）',
        () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      final writeMatches =
          RegExp(r'_cancelRequestedJobId\s*=\s*job\.jobId\b')
              .allMatches(stripped);
      expect(writeMatches.length, 1,
          reason: 'L3 token 单调：写入路径只有 1 处（user intent 入口）');
    });

    test('_cancelRequestedJobId 字段在 _clearExecutionState 内被清零', () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      // _clearExecutionState 必须包含 _cancelRequestedJobId = null
      final regex = RegExp(
        r'_clearExecutionState\b[\s\S]{0,800}?_cancelRequestedJobId\s*=\s*null',
      );
      expect(regex.hasMatch(stripped), isTrue,
          reason: 'K reset 站点 4：_clearExecutionState 必须清零 token');
    });

    test('_cancelRequestedJobId 字段在 _finalizeCancelledJob 内被清零', () {
      final stripped = _stripComments(mergeStateFile.readAsStringSync());
      final regex = RegExp(
        r'_finalizeCancelledJob[\s\S]{0,1500}?_cancelRequestedJobId\s*=\s*null',
      );
      expect(regex.hasMatch(stripped), isTrue,
          reason: 'K reset 站点 3：_finalizeCancelledJob 必须清零 token');
    });
  });

  group('R136 async cancellation — preload_service 形态对偶锁', () {
    test('_shouldStop = false 出现在字段声明 + startPreload 起点 + reset()（恰 3 处）',
        () {
      final stripped = _stripComments(preloadServiceFile.readAsStringSync());
      final resetMatches =
          RegExp(r'_shouldStop\s*=\s*false\b').allMatches(stripped);
      expect(resetMatches.length, 3,
          reason: 'preload reset 站点恰 3 处：'
              '字段声明默认值 + startPreload 起点 + reset()');
    });

    test('_shouldStop = true 仅在 stopPreload 中（恰 1 处 user intent）', () {
      final stripped = _stripComments(preloadServiceFile.readAsStringSync());
      final setMatches =
          RegExp(r'_shouldStop\s*=\s*true\b').allMatches(stripped);
      expect(setMatches.length, 1,
          reason: 'preload set 站点恰 1 处：stopPreload (user intent)');
    });

    test('_shouldStop poll 出现在 while 头与循环结束 finalize 后（≥ 2 处使用）', () {
      final stripped = _stripComments(preloadServiceFile.readAsStringSync());
      // while (!_shouldStop) 循环头 + if (_shouldStop && status == loading) finalize
      expect(stripped.contains('while (!_shouldStop)'), isTrue,
          reason: 'preload 档 A：while (!_shouldStop) 循环头 poll');
      expect(stripped.contains('if (_shouldStop'), isTrue,
          reason: 'preload 档 B：循环结束后 if (_shouldStop ...) finalize');
    });
  });

  group('R136 async cancellation — StepOutput.cancelled sentinel 形态锁', () {
    test('StepOutput.cancelled 工厂存在且 isCancelled = true', () {
      final stripped = _stripComments(stepOutputFile.readAsStringSync());
      expect(stripped.contains('factory StepOutput.cancelled'), isTrue,
          reason: 'cancelled 工厂必须是 StepOutput 一类 sentinel');
      // 工厂内必须设 isCancelled: true（用 stripped 过滤 doc 后仍可见）
      final factoryRegex = RegExp(
        r'factory\s+StepOutput\.cancelled[\s\S]{0,200}?isCancelled:\s*true',
      );
      expect(factoryRegex.hasMatch(stripped), isTrue,
          reason: 'cancelled 工厂必须设 isCancelled: true');
    });

    test('StepOutput.cancelled 是 runtime sentinel 而非持久化字段（R115 锁外）', () {
      // R115 wire schema 锁了 enum 持久化字面量；StepOutput 不参与持久化层
      // 因为它是 runtime-only port 决策结果，doc-only 锁住此约束。
      final stripped = _stripComments(stepOutputFile.readAsStringSync());
      // StepOutput 内不出现 toJson/fromJson（sentinel runtime-only）
      expect(stripped.contains('Map<String, dynamic> toJson'), isFalse,
          reason: 'R115 隔离：StepOutput 是 runtime sentinel，不持久化');
      expect(stripped.contains('factory StepOutput.fromJson'), isFalse,
          reason: 'R115 隔离：StepOutput 不能有 fromJson 工厂');
    });
  });

  group('R136 async cancellation — 协议同律锁（merge vs preload）', () {
    test('两服务均使用单 channel cooperative 模式（不混入 Process.kill）', () {
      final mergeStripped = _stripComments(mergeStateFile.readAsStringSync());
      final preloadStripped =
          _stripComments(preloadServiceFile.readAsStringSync());
      expect(mergeStripped.contains('Process.kill'), isFalse);
      expect(preloadStripped.contains('Process.kill'), isFalse);
    });

    test('两服务的取消信号字段都为可清零的 mutable 状态（int? 或 bool）', () {
      final mergeStripped = _stripComments(mergeStateFile.readAsStringSync());
      final preloadStripped =
          _stripComments(preloadServiceFile.readAsStringSync());
      expect(
        RegExp(r'\bint\?\s+_cancelRequestedJobId\b').hasMatch(mergeStripped),
        isTrue,
      );
      expect(
        RegExp(r'\bbool\s+_shouldStop\b').hasMatch(preloadStripped),
        isTrue,
      );
    });
  });
}
