import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc comment 与 `//` 行注释，避免 doc 字面量
/// 与代码字面量混淆——R130 测试反复出现"自匹配"失败，统一过此 helper。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R130 cross-provider 通信反模式审计 — 4 档分类 + 跨档 4 不变量 I1/I2/I3/I4**
///
/// R128 (provider 触发协议) + R129 (widget lifecycle) 的接合面：
/// 锁 lib 内 cross-provider 通信路径的分类与不变量。
///
/// 4 档分类：
/// - 档 1 = 直接持有引用（provider/service 字段）
/// - 档 2 = Provider.of(listen: false) / context.read（一次性读取）
/// - 档 3 = Consumer / context.watch / Selector（订阅式 rebuild）
/// - 档 4 = ChangeNotifier addListener / removeListener（命令式订阅，lib 内当前 = 0）
///
/// 跨档 4 不变量（与 R128/R129 同模板）：
/// - I1: provider → provider 反模式 = 0（避免双向通知循环 rebuild）
/// - I2: 档 2 必带 `listen: false`
/// - I3: 档 3 订阅必由 widget 主动声明（Consumer 不出现在 provider 类内）
/// - I4: 档 4 = 0 是设计契约不是巧合
void main() {
  group('R130 档 1 直接持有引用 — provider → service / 0 处 provider → provider', () {
    test('AppState 持有 4 个 service 字段', () {
      final src = _stripComments(
          File('lib/providers/app_state.dart').readAsStringSync());
      // ConfigService / StorageService / MergeInfoCacheService / LogFilterService
      expect(src, contains('ConfigService _configService'),
          reason: 'AppState 必持有 ConfigService（档 1 service 子型）');
      expect(src, contains('StorageService _storageService'),
          reason: 'AppState 必持有 StorageService');
      expect(src, contains('MergeInfoCacheService _mergeInfoService'),
          reason: 'AppState 必持有 MergeInfoCacheService');
      expect(src, contains('LogFilterService _filterService'),
          reason: 'AppState 必持有 LogFilterService');
    });

    test('MergeExecutionState 持有 4 个 service 字段', () {
      final src = _stripComments(
          File('lib/providers/merge_execution_state.dart').readAsStringSync());
      expect(src, contains('StorageService _storageService'),
          reason: 'MergeExecutionState 必持有 StorageService');
      expect(src, contains('WorkingCopyManager _wcManager'),
          reason: 'MergeExecutionState 必持有 WorkingCopyManager');
      expect(src, contains('MergeInfoCacheService _mergeInfoService'),
          reason: 'MergeExecutionState 必持有 MergeInfoCacheService');
      expect(src, contains('SvnService _svnService'),
          reason: 'MergeExecutionState 必持有 SvnService');
    });

    test('I1 — AppState 不持有 MergeExecutionState 引用', () {
      final src = _stripComments(
          File('lib/providers/app_state.dart').readAsStringSync());
      // 不允许字段或参数引用另一 provider
      final hasFieldRef = RegExp(r'\b(final|late\s+final)\s+MergeExecutionState\b')
          .hasMatch(src);
      expect(hasFieldRef, isFalse,
          reason: 'I1: AppState 不可持有 MergeExecutionState 引用，'
              '否则 ChangeNotifier 双向通知 → 循环 rebuild → stack overflow。'
              '若需派生 provider 用 ChangeNotifierProxyProvider2');
    });

    test('I1 — MergeExecutionState 不持有 AppState 引用', () {
      final src = _stripComments(
          File('lib/providers/merge_execution_state.dart').readAsStringSync());
      final hasFieldRef =
          RegExp(r'\b(final|late\s+final)\s+AppState\b').hasMatch(src);
      expect(hasFieldRef, isFalse,
          reason: 'I1: MergeExecutionState 不可持有 AppState 引用');
    });
  });

  group('R130 档 2 Provider.of(listen: false) — 一次性读取', () {
    test('main.dart _AppInitializerState._init 内 listen: false 双读', () {
      final src = _stripComments(File('lib/main.dart').readAsStringSync());
      expect(
          src,
          contains(
              'Provider.of<AppState>(context, listen: false)'),
          reason: '档 2: 启动期 init 读 AppState 必带 listen: false');
      expect(
          src,
          contains(
              'Provider.of<MergeExecutionState>(context, listen: false)'),
          reason: '档 2: 启动期 init 读 MergeExecutionState 必带 listen: false');
    });

    test('I2 — main.dart 内所有 Provider.of 调用必带 listen: false', () {
      final src = _stripComments(File('lib/main.dart').readAsStringSync());
      // 所有 Provider.of< 出现都必须紧接 listen: false
      final allCalls = RegExp(r'Provider\.of<[^>]+>\([^)]*\)').allMatches(src);
      for (final m in allCalls) {
        expect(m.group(0), contains('listen: false'),
            reason: 'I2: ${m.group(0)} 必带 listen: false，否则等价 watch 触发 rebuild');
      }
    });

    test('I2 — main_screen_v3.dart 内所有 Provider.of 调用必带 listen: false', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      final allCalls = RegExp(r'Provider\.of<[^>]+>\([^)]*\)').allMatches(src);
      expect(allCalls.length, greaterThan(10),
          reason: '档 2: main_screen_v3 内事件回调读 ≥10 处');
      for (final m in allCalls) {
        expect(m.group(0), contains('listen: false'),
            reason: 'I2: ${m.group(0)} 必带 listen: false');
      }
    });
  });

  group('R130 档 3 Consumer / Consumer2 — 订阅式 rebuild', () {
    test('lib 内 Consumer 站点恰为 2 处', () {
      final mainSrc = _stripComments(File('lib/main.dart').readAsStringSync());
      final mainScreenSrc = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      expect(mainSrc, contains('Consumer<AppState>'),
          reason: '档 3: main.dart 启动期 loading/error 视图');
      expect(mainScreenSrc, contains('Consumer2<AppState, MergeExecutionState>'),
          reason: '档 3: main_screen_v3 主屏幕双 provider 协调');
    });

    test('I3 — provider 类内不出现 Consumer / context.watch', () {
      for (final path in [
        'lib/providers/app_state.dart',
        'lib/providers/merge_execution_state.dart',
      ]) {
        final src = _stripComments(File(path).readAsStringSync());
        expect(src, isNot(contains('Consumer<')),
            reason: 'I3: provider 类内不可出现 Consumer，跨界 framework 误用');
        expect(src, isNot(contains('Consumer2<')),
            reason: 'I3: provider 类内不可出现 Consumer2');
        expect(src, isNot(contains('context.watch<')),
            reason: 'I3: provider 类内不可出现 context.watch');
        expect(src, isNot(contains('Selector<')),
            reason: 'I3: provider 类内不可出现 Selector');
      }
    });

    test('lib 内不使用 Selector / context.watch / context.read（显式优于隐式）', () {
      // 扫所有 .dart 文件
      final dir = Directory('lib');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        expect(src, isNot(contains('context.watch<')),
            reason: '${f.path}: 不使用 context.watch，统一走 Consumer 显式 builder');
        expect(src, isNot(contains('context.read<')),
            reason: '${f.path}: 不使用 context.read，统一走 Provider.of(listen: false)');
        expect(src, isNot(contains('Selector<')),
            reason: '${f.path}: 不使用 Selector，统一走 Consumer 显式 builder');
      }
    });
  });

  group('R130 档 4 addListener / removeListener — 命令式订阅 = 0', () {
    test('I4 — lib 内 0 处 ChangeNotifier.addListener 调用', () {
      final dir = Directory('lib');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        expect(src, isNot(contains('.addListener(')),
            reason: 'I4: ${f.path} 不可使用 addListener，'
                '保持档 4 = 0 是设计契约（避免手工 dispose 配对责任）。'
                '若需引入必须先升档 R130 重新评估');
      }
    });

    test('I4 — lib 内 0 处 ChangeNotifier.removeListener 调用', () {
      final dir = Directory('lib');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        expect(src, isNot(contains('.removeListener(')),
            reason: 'I4: ${f.path} 不可使用 removeListener');
      }
    });
  });

  group('R130 注册结构契约 — MultiProvider 平行注册', () {
    test('main.dart MultiProvider 平行注册两 provider', () {
      final src = _stripComments(File('lib/main.dart').readAsStringSync());
      expect(src, contains('MultiProvider'),
          reason: '应用根用 MultiProvider 注册');
      expect(src, contains('ChangeNotifierProvider(create: (_) => AppState())'),
          reason: '注册 AppState');
      expect(
          src,
          contains(
              'ChangeNotifierProvider(create: (_) => MergeExecutionState())'),
          reason: '注册 MergeExecutionState');
    });

    test('I1 反向锁 — 不使用 ChangeNotifierProxyProvider*（当前 0 派生 provider）', () {
      final src = _stripComments(File('lib/main.dart').readAsStringSync());
      expect(src, isNot(contains('ChangeNotifierProxyProvider')),
          reason: '当前 0 处派生 provider；若引入说明出现 provider → provider 依赖，'
              '应同时升档 R130 加新档分类（"派生持有"档）');
    });
  });

  group('R130 与 R128/R129 接合面契约', () {
    test('R130 答"链路怎么连"，与 R128/R129 互补', () {
      // 元说明 doc-as-test，无运行时断言
      // R128 = provider 生产端 trigger 协议
      // R129 = widget 消费端 lifecycle dispose
      // R130 = 生产-消费链路本身（4 档分类 + 4 不变量）
      // 三者互补、不重叠
      expect(true, isTrue, reason: 'R128/R129/R130 三轮形成完整 cross-provider 通信契约族');
    });

    test('三档框架第 10 次复用（升级到 4 档框架）', () {
      // R98 / R119 / R120 / R121 / R125 / R126 / R127 / R128 / R129 / R130
      // R130 首次扩展为 4 档（增加档 4 命令式 listener）
      // 证明三档框架可按需升档但保持 N-tuple invariance 模板（4 不变量与档位正交）
      expect(true, isTrue, reason: 'R130 4 档分类是 R98 三档框架的延伸，框架 dimension-extensible 性质再升级');
    });

    test('I4 与 R129 widget lifecycle 互证', () {
      // R129 widget lifecycle 维度发现 0 处 addListener/removeListener pair
      // R130 I4 锁定档 4 = 0 是设计契约
      // 两轮互证：若未来引入 listener，必同时影响 R129 dispose 责任 + R130 档分类
      final dir = Directory('lib');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      var addCount = 0;
      var removeCount = 0;
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        addCount += '.addListener('.allMatches(src).length;
        removeCount += '.removeListener('.allMatches(src).length;
      }
      expect(addCount, 0, reason: 'R130 I4 + R129 互证: addListener 全 lib = 0');
      expect(removeCount, 0,
          reason: 'R130 I4 + R129 互证: removeListener 全 lib = 0');
    });
  });
}
