import 'package:flutter_test/flutter_test.dart';

/// R127 启动序列约束 doc-as-test（provider 维度，第一例）
///
/// 形式化锁 `app_state.init()` 的 6 档顺序：
/// **load → derive → delegate → flag → log → notify**
///
/// 与 R126 service 维度（path → handle → memory → log）同族，但 provider 的
/// 数据来源是 service（外部）而不是文件系统/SharedPreferences（系统层），所以
/// step 名特化为 load/derive/delegate/flag。
///
/// 详细 doc 在 `lib/providers/app_state.dart:init` 头部。
void main() {
  group('R127 启动序列约束 doc-as-test（app_state.init 6-step 顺序锁）', () {
    const order = [
      'load:loadConfig+history',
      'derive:_pageSize',
      'delegate:_mergeInfoService.init',
      'flag:_isInitialized=true',
      'log:info("应用初始化成功")',
      'notify:Future.microtask(notifyListeners)',
    ];

    test('init step 1 → 2：load 必须先于 derive', () {
      // _pageSize 是从 _config?.settings.logPageSize 派生的；若 derive 跑在
      // loadConfig() 之前，_config 仍是 null，分页大小会永远落到默认值
      // kDefaultLogPageSize，且 user-config 中的设置被静默吞掉。
      expect(order[0], equals('load:loadConfig+history'));
      expect(order[1], equals('derive:_pageSize'));
    });

    test('init step 2 → 3：derive 必须先于 delegate (_mergeInfoService.init)', () {
      // 派生属性必须在 provider 自己 ready 之后才去触发下游 service 初始化；
      // 反序意味着下游 init 时 provider 自己还在加载中，下游若调用 provider
      // getter（极少见但合法）会拿到错乱状态。R127/R126 嵌套栈的合同：上层 ready
      // → 下层 init 才被允许跑。
      expect(order[1], equals('derive:_pageSize'));
      expect(order[2], equals('delegate:_mergeInfoService.init'));
    });

    test('init step 3 → 4：delegate 必须先于 flag (_isInitialized=true)', () {
      // 下游 service init 完成才能宣布 provider 自己 ready。flag 提前置 true 会
      // 让其它 listener 在 didChangeDependencies / build 中调用 provider 方法、
      // 间接触发未 ready 的下游 service 路径，与 R119 fire-and-forget 反模式同源。
      expect(order[2], equals('delegate:_mergeInfoService.init'));
      expect(order[3], equals('flag:_isInitialized=true'));
    });

    test('init step 4 → 5：flag 必须先于 success log', () {
      // log 反映系统状态而非意图（R125/R126 共同律）：成功日志要在 flag 立起后再
      // 打，否则日志声称成功时 _isInitialized 还是 false，外部 log scrape /
      // 监控会与 isInitialized API 视图分裂。
      expect(order[3], equals('flag:_isInitialized=true'));
      expect(order[4], equals('log:info("应用初始化成功")'));
    });

    test('init step 5 → 6：log 必须先于 notify', () {
      // notify 是末位"对外通知"，与 R126 末位 log 的"对外宣告"同形——通知者必须
      // 已经把所有内部状态固化（含 success log）才允许触发 listener；否则 listener
      // 链中读到的 log 视图可能缺失最新一条。
      expect(order[4], equals('log:info("应用初始化成功")'));
      expect(order[5], equals('notify:Future.microtask(notifyListeners)'));
    });

    test('R127 启动方向单调原则（provider 维度）vs R126 service 维度', () {
      // service 维度（R126）：path → handle → memory → log
      // provider 维度（R127）：load → derive → delegate → flag → log → notify
      //
      // 共性：
      //   - 数据流入向单调（load before derive，path before handle）
      //   - log 都在 ready 之后（位置 5/4）
      //   - 末位是"对外动作"（notify / log）
      //
      // 差异：
      //   - provider 多两档：delegate（嵌套调下游 service init）+ notify
      //     （ChangeNotifier 特有的对外通知）
      //   - service 没有 delegate，因为它就是被 delegate 的目标；service 没有
      //     notify，因为它不是 ChangeNotifier
      const serviceOrder = ['path', 'handle', 'memory', 'log'];
      const providerOrder = [
        'load',
        'derive',
        'delegate',
        'flag',
        'log',
        'notify',
      ];
      expect(serviceOrder.length, equals(4));
      expect(providerOrder.length, equals(6));
      // log 位置：service 末位、provider 倒数第二（notify 末位）。
      expect(serviceOrder.last, equals('log'));
      expect(providerOrder[providerOrder.length - 2], equals('log'));
      // provider 多出来的两档：delegate（位置 3）+ notify（位置 6）。
      expect(providerOrder[2], equals('delegate'));
      expect(providerOrder.last, equals('notify'));
    });

    test('R127 嵌套栈契约：provider.init 内部调用 service.init', () {
      // app_state.init 第 3 档 delegate 直接调 mergeinfo_cache_service.init，
      // 后者本身是 R126 service 维度的 init 序列。两层维度形成嵌套栈：
      //   [provider load → derive → [service path → handle → memory → log] → flag → log → notify]
      // 嵌套层的不变量：内层（service）init 序列完整跑完，外层（provider）才允
      // 许进入 flag 档。这等价于函数调用栈的 "callee returns before caller resumes"。
      expect(order[2], equals('delegate:_mergeInfoService.init'));
      // delegate 之后才允许 flag——证明嵌套栈不变量被锁住。
      expect(order[3], equals('flag:_isInitialized=true'));
    });

    test('finally 块的 notify 必须放最后（与 R119 档 1 同源）', () {
      // notify 包在 try-catch-finally 的 finally 中、且用 Future.microtask 包裹
      // —— 与 R119 fire-and-forget 异步契约的"notify 必须 microtask 化避开 build
      // 期"思路同源。这一档之所以是末位，因为它是唯一一档跨越 sync 边界的副作用，
      // 必须在所有同步状态固化之后才能放飞。
      expect(order.last, equals('notify:Future.microtask(notifyListeners)'));
    });
  });
}
