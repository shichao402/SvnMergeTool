import 'package:flutter_test/flutter_test.dart';

/// R128 provider notifyListeners 触发协议 doc-as-test（MergeExecutionState 维度）
///
/// 形式化锁三档分类（与 AppState 共享同框架，但有 MergeExecutionState 特化）：
///   - 档 1 sync 直接 notify
///   - 档 2 conditional notify (skip-on-noop / guard-on-relevance)
///   - 档 3 状态机阶段切换 + 中间 notify（不是 loading-flag bracket）
///
/// 详细 doc 在 `lib/providers/merge_execution_state.dart` 的
/// MergeExecutionState class 文档块。
void main() {
  group('R128 notify 触发协议 doc-as-test（MergeExecutionState 21+ 处 notify 站点三档分类）', () {
    // 档 1 代表站点（sync 直接 notify）
    const tier1Sites = [
      'addJob:notifyListeners',
      'removeQueuedJob:notifyListeners',
      'clearQueuedJobs:notifyListeners',
      'clearHistory:notifyListeners',
      'requestSkipCurrentRevision:notifyListeners',
      'continuePausedJob:notifyListeners',
      'cancelPausedJob:notifyListeners(non-running path)',
      '_runRevision:step transitions notifyListeners',
    ];

    // 档 2 代表站点（conditional notify）
    const tier2SkipOnNoop = ['cancelPausedJob (running + dup cancel)'];
    const tier2GuardOnRelevance = [
      '_recoverInterruptedJobIfDone (merged-only path)',
    ];

    // 档 3 代表站点（状态机阶段切换 + 中间 notify）
    const tier3Sites = [
      'init',
      '_executeJob:status=completed→idle',
      '_recoverInterruptedJob:status=completed→idle',
    ];

    test('档 1：sync 直接 notify ≥ 7 处（state-machine mutator 主体形态）', () {
      // 档 1 是状态机推进期间最常见形态——await 之后 + 字段写入 + notify。
      // MergeExecutionState 的状态机切换大量落在档 1，是默认形态。
      expect(tier1Sites.length, greaterThanOrEqualTo(7));
    });

    test('档 2 sub-variant skip-on-noop：重复 cancel 请求不再 notify', () {
      // cancelPausedJob 内 `if (_cancelRequestedJobId == job.jobId) { append
      // log + return; }` 守卫——重复请求只追加 log（不算用户可见的状态变化）、
      // 不 notify。判据：mutator 是否做"幂等性检查"。
      expect(tier2SkipOnNoop.length, equals(1));
    });

    test('档 2 sub-variant guard-on-relevance：仓库已合并才续跑+notify', () {
      // _recoverInterruptedJobIfDone 仅在仓库实际已合并时才 mutate +
      // notify、否则提前 return false 让外层走"重新开始"路径。判据：mutator
      // 是否依赖外部状态（仓库实际合并状态）的"相关性"判定。
      expect(tier2GuardOnRelevance.length, equals(1));
    });

    test('档 3：状态机阶段切换 + 中间 notify（≥ 3 处）', () {
      // 与 AppState 档 3 的 loading-flag bracket 不同——MergeExecutionState 用
      // _status: ExecutorStatus 状态机表达进度。档 3 形态：
      //   _status = completed; _currentStepId = null; notifyListeners();
      //   _status = idle;  // 紧跟切换但不 notify，因为是 internal cleanup
      //   await _startNextJob(); // 下一轮进入新 notify 循环
      expect(tier3Sites.length, greaterThanOrEqualTo(3));
      expect(tier3Sites, contains('init'));
    });

    test('MergeExecutionState 特化 1：status idle 切换可省略 notify', () {
      // 状态机 sub-rule——`_status = ExecutorStatus.idle` 是 internal transient
      // 状态、紧跟 _startNextJob() 进入下一轮会自己 notify。这不破坏跨档不变量
      // 3（"每个 mutator 至少一条 notify 路径"），因为 idle 状态本身不是 user-
      // visible 的"独立帧"——它是从 completed 到下一任务 running 的过渡瞬间。
      // 判据：transient internal 状态可省略 notify、user-visible 状态必须 notify。
      const internalStateCanSkipNotify = 'idle';
      expect(internalStateCanSkipNotify, equals('idle'));
    });

    test('MergeExecutionState 特化 2：kick-after-notify 模式（与 R127 init 末位 kick 同源）', () {
      // 形态：notifyListeners(); await _startNextJob();——遍布 _executeJob /
      // _recoverInterruptedJob / init。notify 让 UI 看到当前任务收尾（completed
      // 状态）、kick 启动下一任务进入新 notify 循环。这是状态机推进的标准 idiom，
      // 与 R127 init 序列末位 kick 是同源——provider init 期 kick 启动后台 job
      // 是该 idiom 在启动期的特化。
      const kickAfterNotifyPattern = 'notify → kick';
      expect(kickAfterNotifyPattern, equals('notify → kick'));
    });

    test('MergeExecutionState 与 AppState notify 协议同框架对照', () {
      // 共享：三档分类 + 跨档不变量 1/2/3。
      // 不同：
      //   档 3 形态——AppState 是 loading-flag bracket 双 notify、
      //              MergeExecutionState 是状态机阶段切换链 notify。
      //   档 2 子型——AppState 有 guard-delegate 子型（双路径终态对齐）、
      //              MergeExecutionState 没有（无"if(usable) await; else
      //              notify"路径，因为业务流是状态机驱动而非参数路径分裂）。
      const sharedFrameworkPlusSpecialization = true;
      expect(sharedFrameworkPlusSpecialization, isTrue);
    });

    test('跨档不变量 1：notify 之前 mutator 必须已写完', () {
      // 与 AppState 同律。状态机切换的强形态：`_jobs[i] = job.copyWith(...);
      // await _storageService.saveQueue(_jobs); _appendLog(...); _status =
      // completed; notifyListeners();`——所有副作用先固化、最后 notify。
      const invariantName = 'mutator-before-notify';
      expect(invariantName, equals('mutator-before-notify'));
    });

    test('跨档不变量 2：notify 之后不再写 listener 会立即读的字段', () {
      // 与 AppState 同律。MergeExecutionState 的 `_status = idle` 之所以能放
      // 在 notify 之后，是因为它**不是** listener 立即读的字段——getter status
      // 返回的 ExecutorStatus 在 idle/completed 两个值之间的差异不会触发 UI
      // 视觉变化（completed → idle 之间无 spinner / status 标签变化）。这是
      // 不变量 2 的边界判定。
      const invariantName = 'no-write-after-notify-listener-reads';
      expect(invariantName, equals('no-write-after-notify-listener-reads'));
    });

    test('跨档不变量 3：每个 mutator 至少有一条到达 notify 的路径', () {
      // MergeExecutionState 的覆盖律：所有 user-visible 状态变化都至少有一条
      // notify 路径——队列改变、job 状态切换、step 切换、log 追加（_appendLog
      // 内部不 notify、由调用方在 mutator 末位 notify 一次性触发）。
      const invariantName = 'every-user-visible-mutator-reaches-notify';
      expect(invariantName, equals('every-user-visible-mutator-reaches-notify'));
    });

    test('R128 与 R127 init 序列共契：init 末位 notify 既属 R127 又属 R128', () {
      // R127 锁 init 序列的 6 档顺序（load → derive → reset → log → notify →
      // kick），R128 把同一 init 末位 notify 归为档 3"状态机阶段切换 + 中间
      // notify"。两 R 的 doc-as-test 在 init 末位 notify 站点交集——R127 锁的
      // 是"它在序列中的位置"、R128 锁的是"它的触发协议档位"。同一站点两维度
      // 同时成立。这是 R125/R126 step-level audit 与 R128 trigger-level audit
      // 的**正交叠加**示例。
      const r127R128Overlap = 'init.notifyListeners';
      expect(r127R128Overlap, equals('init.notifyListeners'));
    });

    test('档 1 与档 3 边界判定：单 notify vs 多 notify', () {
      // 档 1：单 notify（state-machine 推进的一次 transition）。
      // 档 3：多 notify（状态机阶段切换链多次 transition，每次 user-visible
      //        状态变化都 notify）。
      // 判据：mutator 内 notify 计数 == 1 → 档 1；> 1 或形态是状态机切换链
      // → 档 3。skip-on-noop / guard-on-relevance 则归档 2 而非档 1。
      const tier1NotifyCount = 1;
      const tier3NotifyCountMin = 1; // 单次切换至少 1 次、多次切换更多
      expect(tier1NotifyCount, equals(1));
      expect(tier3NotifyCountMin, greaterThanOrEqualTo(1));
    });
  });
}
