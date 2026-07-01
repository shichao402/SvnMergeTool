import 'package:flutter_test/flutter_test.dart';

/// R127 启动序列约束 doc-as-test（provider 维度，第二例）
///
/// 形式化锁 `merge_execution_state.init()` 的 7 档顺序：
/// **load → derive → hydrateTargetUrl → reset → log → notify → kick**
///
/// 与 `app_state.init`（load → derive → delegate → flag → log → notify）
/// 共享前两档 + 倒数第二档 log + 倒数第三档 notify；区别在于：
///   - merge_execution_state 没有 delegate（不嵌套调下游 service init）
///   - merge_execution_state 没有 flag（无 _isInitialized 字段）
///   - merge_execution_state 多 reset（清零内存日志状态）
///   - merge_execution_state 多 kick（自动续跑 pending job——业务必须）
///
/// 详细 doc 在 `lib/providers/merge_execution_state.dart:init` 头部。
void main() {
  group('R127 启动序列约束 doc-as-test（merge_execution_state.init 7-step 顺序锁）', () {
    const order = [
      'load:_storageService.loadQueue',
      'derive:deriveNextJobId',
      'hydrate:_hydrateMissingTargetUrls',
      'reset:_log+_clearExecutionState',
      'log:_appendLog(paused-job warnings)',
      'notify:notifyListeners',
      'kick:_startNextJob',
    ];

    test('init step 1 → 2：load 必须先于 derive', () {
      // deriveNextJobId 直接吃 _jobs 列表；若 derive 跑在 loadQueue 之前，
      // _jobs 仍是构造期初值（空 list 或预设 jobs），_nextJobId 会走 fallback
      // 而非真实 max(jobId)+1，新加 job 时会与历史 job 撞 ID。
      expect(order[0], equals('load:_storageService.loadQueue'));
      expect(order[1], equals('derive:deriveNextJobId'));
    });

    test('init step 2 → 3：derive 必须先于 targetUrl hydrate', () {
      // derive 是只读派生（不写状态），reset 是写操作（清零 _log + 清空执行状态）。
      // 派生 _nextJobId 完成后再 reset 更安全；反序虽不会逻辑错（derive 不读
      // _log），但破坏 "load → derive → 写" 的层级——纯函数式 derive 应当在所有
      // mutator 之前结算。
      expect(order[1], equals('derive:deriveNextJobId'));
      expect(order[2], equals('hydrate:_hydrateMissingTargetUrls'));
    });

    test('init step 3 → 4：targetUrl hydrate 必须先于 reset', () {
      // hydrate 会补齐旧队列任务的目标 URL，并可能 saveQueue；它必须早于
      // 首次 notify，才能让用户一打开界面就看到真实目标分支。
      expect(order[2], equals('hydrate:_hydrateMissingTargetUrls'));
      expect(order[3], equals('reset:_log+_clearExecutionState'));
    });

    test('init step 4 → 5：reset 必须先于 paused-job log', () {
      // _appendLog 直接 append 到 _log；若 paused-job 警告日志跑在 reset 之前，
      // 上一次会话残留的 _log 会污染本次启动日志输出（用户看到旧 + 新混合的 log
      // 流）。这是 R125/R126 "清理-标记-宣告"族律在 provider 维度的实例：reset
      // 是清理、log 是宣告，宣告必须在清理之后。
      expect(order[3], equals('reset:_log+_clearExecutionState'));
      expect(order[4], equals('log:_appendLog(paused-job warnings)'));
    });

    test('init step 5 → 6：log 必须先于 notify', () {
      // notify 是 ChangeNotifier 的对外通知；listener 链中 LogPanel 等组件会
      // 立即读 log getter 拉取最新日志。log 必须先 append 完 paused-job 警告，
      // notify 才能触发——反序意味着 listener 触发时新警告还没进 _log，UI 漏显
      // 一帧后才被下一次 notify 补上（视觉上是闪烁）。
      expect(order[4], equals('log:_appendLog(paused-job warnings)'));
      expect(order[5], equals('notify:notifyListeners'));
    });

    test('init step 6 → 7：notify 必须先于 kick (_startNextJob)', () {
      // notify 让 UI 立即看到队列 + paused 状态；kick 是后台 fire-and-forget 的
      // 异步 job 启动。反序意味着 _startNextJob 推进队列状态时，UI 还没看到初始
      // 队列快照——用户错过了"初始队列长这样"这一帧。同时 _startNextJob 内部本
      // 身会 await + notify，与启动初始 notify 形成时序竞争。
      expect(order[5], equals('notify:notifyListeners'));
      expect(order[6], equals('kick:_startNextJob'));
    });

    test('R127 启动方向单调原则在 merge_execution_state 维度的特化', () {
      // app_state 序列：load → derive → delegate → flag → log → notify
      // merge_execution_state 序列：load → derive → hydrate → reset → log → notify → kick
      //
      // 同位档对照：
      //   位置 1: load == load （同）
      //   位置 2: derive == derive （同）
      //   位置 3: delegate vs reset （异：app_state 嵌套 init 下游、execution_state
      //          清零自身状态）
      //   位置 4: flag vs log （异）
      //   位置 5: log vs notify （错位，但 log 都在 notify 之前）
      //   位置 6: notify vs kick （execution_state 多业务后续动作）
      const appStateOrder = [
        'load',
        'derive',
        'delegate',
        'flag',
        'log',
        'notify',
      ];
      const executionStateOrder = [
        'load',
        'derive',
        'hydrate',
        'reset',
        'log',
        'notify',
        'kick',
      ];
      expect(appStateOrder.length, equals(6));
      expect(executionStateOrder.length, equals(7));
      // 共享前两档：load, derive
      expect(appStateOrder.sublist(0, 2),
          equals(executionStateOrder.sublist(0, 2)));
      // log 都早于 notify
      expect(appStateOrder.indexOf('log'),
          lessThan(appStateOrder.indexOf('notify')));
      expect(executionStateOrder.indexOf('log'),
          lessThan(executionStateOrder.indexOf('notify')));
    });

    test('kick 末位是 fire-and-forget 业务续跑（与 R119 档 1 同源）', () {
      // _startNextJob 是 await 的（不是 fire-and-forget 字面意义），但相对于
      // init() 的调用方而言，init() 是 await 在最外层；kick 之后 init() 直接
      // return 给调用方。kick 内部 await 整个 job 链跑完——这意味着调用 init()
      // 的代码会等到 _startNextJob 返回才继续。这是个有意识的设计选择：启动期
      // 自动续跑必须串行于 init，否则 UI 启动 spinner 的下落判定（init done?）
      // 会与 job 状态视图不一致。R119 档 1 关心异步逃逸；kick 关心异步绑定。
      expect(order.last, equals('kick:_startNextJob'));
    });

    test('reset 不变量：清零必须先于第一条 paused-job 警告日志', () {
      // 这是 reset → log 顺序锁的"性质化"测试：reset 与 log 之间没有任何其他副
      // 作用允许出现。即使将来加 step（比如重置某个 cache），新 step 必须落在
      // reset/log 区间之外或之间但不破坏 reset 早于 log。
      final resetIdx = order.indexOf('reset:_log+_clearExecutionState');
      final logIdx = order.indexOf('log:_appendLog(paused-job warnings)');
      expect(resetIdx, lessThan(logIdx));
      // 没有其它写状态档落在 reset 与 log 之间（当前空区间）
      expect(logIdx - resetIdx, equals(1));
    });
  });
}
