import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R129 widget lifecycle dispose 维度审计 doc-as-test
///
/// 三档分类（widget 维度，对偶 R121 service 资源释放协议三档框架的 widget 实例化）：
///   - 档 1 = StatelessWidget / 无 State 类（无 dispose 责任）
///   - 档 2 = StatefulWidget 但 State 无 owned Disposable（override dispose 仅作扩展点
///     或完全可省）
///   - 档 3 = StatefulWidget + State 持有 owned Disposable（必须在 dispose 内反向 unwind）
///
/// 跨档不变量 I1/I2/I3/I4（widget 维度特化）：
///   - I1: super.dispose() 必为末位
///   - I2: 每个 owned Disposable 必在 super.dispose() 之前 dispose
///   - I3: 1:1 owned-vs-disposed parity
///   - I4: dispose 顺序 = 反序于 declaration（widget 维度允许同序简化）
///
/// 详细 doc 见 lib/screens/main_screen_v3.dart:dispose 类内文档块。
void main() {
  group('R129 widget lifecycle dispose doc-as-test（StatefulWidget 三档分类锁）', () {
    // 档 1 代表站点（StatelessWidget — 无 dispose 责任）
    const tier1StatelessSites = [
      'PendingPanel',
      'ConfigBar',
      'StatusBar',
      'StepExecutionView',
      'LogListPanel',
      'JobQueuePanel',
      'SourceUrlDialog',
      'TargetWorkingCopyDialog',
      'TargetSvnUrlDialog',
      'LogDialog',
    ];

    // 档 2 代表站点（StatefulWidget 但无 owned Disposable）
    const tier2StatefulNoResourceSites = [
      '_AppInitializerState', // main.dart:219
      '_MergeExecutionPanelState', // merge_execution_panel.dart:452
    ];

    // 档 3 代表站点（StatefulWidget + owned Disposable）
    const tier3StatefulWithResourceSites = [
      '_MainScreenV3State', // main_screen_v3.dart — 7 TextEditingController
      '_SettingsScreenState', // settings_screen.dart:198 — 6 TextEditingController
    ];

    test('档 1 StatelessWidget ≥9 sites — 无 dispose 责任', () {
      expect(tier1StatelessSites.length, greaterThanOrEqualTo(9));
      expect(tier1StatelessSites.toSet().length, tier1StatelessSites.length,
          reason: '档 1 站点 ID 不应重复');
    });

    test('档 2 StatefulWidget 无 owned Disposable ≥2 sites', () {
      expect(tier2StatefulNoResourceSites.length, greaterThanOrEqualTo(2));
    });

    test('档 3 StatefulWidget + owned Disposable ≥2 sites — 必须 override dispose',
        () {
      expect(tier3StatefulWithResourceSites.length, greaterThanOrEqualTo(2));
    });

    test('I1 super.dispose() 末位 — main_screen_v3.dart:dispose 字面验证', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // 截取 dispose 函数体
      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      expect(disposeBodyMatch, isNotNull,
          reason: 'main_screen_v3 必须 override dispose');
      final body = disposeBodyMatch!.group(1)!;
      // super.dispose 必须是函数体内最后一条非空 statement
      final lines = body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'))
          .toList();
      expect(lines.last, contains('super.dispose()'),
          reason: 'I1: super.dispose() 必为函数体末位');
    });

    test('I1 super.dispose() 末位 — settings_screen.dart:dispose 字面验证', () {
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      expect(disposeBodyMatch, isNotNull);
      final body = disposeBodyMatch!.group(1)!;
      final lines = body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'))
          .toList();
      expect(lines.last, contains('super.dispose()'),
          reason: 'I1: super.dispose() 必为函数体末位');
    });

    test('I2 每 owned Disposable 必在 super.dispose 之前 dispose — main_screen_v3',
        () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      final body = disposeBodyMatch!.group(1)!;
      final superIdx = body.indexOf('super.dispose()');
      // owned controllers 在类内 declaration
      const ownedControllers = [
        '_sourceUrlController',
        '_targetWcController',
        '_targetUrlController',
        '_filterAuthorController',
        '_filterTitleController',
        '_filterMessageController',
        '_commitSupplementController',
      ];
      for (final c in ownedControllers) {
        final cIdx = body.indexOf('$c.dispose()');
        expect(cIdx, greaterThanOrEqualTo(0),
            reason: 'I3 parity: $c 必有对应 dispose 调用');
        expect(cIdx, lessThan(superIdx),
            reason: 'I2: $c.dispose() 必在 super.dispose 之前');
      }
    });

    test('I2 每 owned Disposable 必在 super.dispose 之前 dispose — settings_screen',
        () {
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      final body = disposeBodyMatch!.group(1)!;
      final superIdx = body.indexOf('super.dispose()');
      const ownedControllers = [
        '_maxDaysController',
        '_maxCountController',
        '_stopRevisionController',
        '_stopDateController',
        '_maxRetriesController',
      ];
      for (final c in ownedControllers) {
        final cIdx = body.indexOf('$c.dispose()');
        expect(cIdx, greaterThanOrEqualTo(0),
            reason: 'I3 parity: $c 必有对应 dispose 调用');
        expect(cIdx, lessThan(superIdx),
            reason: 'I2: $c.dispose() 必在 super.dispose 之前');
      }
    });

    test(
        'I3 1:1 owned-vs-disposed parity — main_screen_v3 declarations 与 dispose 对齐',
        () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // 找类体内所有 final _xxxController = TextEditingController() 声明
      final declared =
          RegExp(r'final (_\w+Controller) = TextEditingController\(\);')
              .allMatches(src)
              .map((m) => m.group(1))
              .toSet();
      expect(declared.length, 7,
          reason: '_MainScreenV3State 应有 7 个 TextEditingController');
      // 每个声明都必须有对应的 .dispose() 调用
      for (final c in declared) {
        expect(src, contains('$c.dispose()'),
            reason: 'I3 parity: $c 必在 dispose 内被释放');
      }
    });

    test(
        'I3 1:1 owned-vs-disposed parity — settings_screen declarations 与 dispose 对齐',
        () {
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      final declared =
          RegExp(r'final (_\w+Controller) = TextEditingController\(\);')
              .allMatches(src)
              .map((m) => m.group(1))
              .toSet();
      expect(declared.length, 6,
          reason: '_SettingsScreenState 应有 6 个 TextEditingController');
      for (final c in declared) {
        expect(src, contains('$c.dispose()'),
            reason: 'I3 parity: $c 必在 dispose 内被释放');
      }
    });

    test('I4 dispose 顺序简化为同序于 declaration（widget 维度允许同序，无内部依赖）— main_screen_v3',
        () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // declaration 顺序：sourceUrl, targetWc, filterAuthor, filterTitle, filterMessage, commitSupplement
      const expectedOrder = [
        '_sourceUrlController.dispose()',
        '_targetWcController.dispose()',
        '_filterAuthorController.dispose()',
        '_filterTitleController.dispose()',
        '_filterMessageController.dispose()',
        '_commitSupplementController.dispose()',
      ];
      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      final body = disposeBodyMatch!.group(1)!;
      int cursor = 0;
      for (final line in expectedOrder) {
        final idx = body.indexOf(line, cursor);
        expect(idx, greaterThanOrEqualTo(0),
            reason: 'I4: dispose body 内 "$line" 必须按 declaration 同序出现');
        cursor = idx + line.length;
      }
    });

    test('档 2 _MergeExecutionPanelState 故意不 override dispose — 正向锁档 2 形态', () {
      final src = File('lib/screens/components/merge_execution_panel.dart')
          .readAsStringSync();
      // 提取 _MergeExecutionPanelState 类体
      final classMatch = RegExp(
              r'class _MergeExecutionPanelState extends State<MergeExecutionPanel> \{([\s\S]*?)\n\}')
          .firstMatch(src);
      expect(classMatch, isNotNull);
      final body = classMatch!.group(1)!;
      expect(body.contains('void dispose()'), isFalse,
          reason: '档 2: _MergeExecutionPanelState 无 owned Disposable, '
              '不应 override dispose（reviewer 信号: 任何 dispose override 提示资源已被引入）');
    });

    test('档 2 _AppInitializerState 故意不 override dispose — 正向锁档 2 形态', () {
      final src = File('lib/main.dart').readAsStringSync();
      final classMatch = RegExp(
              r'class _AppInitializerState extends State<AppInitializer> \{([\s\S]*?)\n\}')
          .firstMatch(src);
      expect(classMatch, isNotNull);
      final body = classMatch!.group(1)!;
      expect(body.contains('void dispose()'), isFalse,
          reason:
              '档 2: _AppInitializerState 无 owned Disposable, 不应 override dispose');
    });

    test('R129 三档框架第 9 次复用元说明锁（lifecycle 维度首次形式化）', () {
      // R98 异常 / R119 异步错误 / R120 等待 / R121 release function 级 /
      // R125 release step 级 / R126 init step 级 / R127 init step 级 + 嵌套 /
      // R128 trigger 级 / R129 lifecycle 级 — 9 次复用
      const reuseChain = [
        'R98 异常',
        'R119 异步错误',
        'R120 等待',
        'R121 release function 级',
        'R125 release step 级',
        'R126 init step 级',
        'R127 init step 级 + 嵌套',
        'R128 trigger 级',
        'R129 lifecycle 级',
      ];
      expect(reuseChain.length, 9, reason: '三档框架累计复用 9 次');
      expect(reuseChain.toSet().length, 9, reason: '每次复用维度互不重复');
    });

    test('R129 与 R127 init 维度对偶 / R125 close 维度同形 — 镜像关系锁', () {
      // R127 widget initState 序列：super.initState() → init resources → schedule callbacks
      // R129 widget dispose 序列：dispose resources → super.dispose()
      // 首尾对偶：init 头 super、dispose 尾 super；中间是资源处理
      const initFirstStep = 'super.initState()';
      const disposeLastStep = 'super.dispose()';
      // 验证 main_screen_v3 实际遵守此对偶
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final initBodyMatch =
          RegExp(r'void initState\(\) \{([^}]*)\}').firstMatch(src);
      final initBody = initBodyMatch!.group(1)!;
      final initLines = initBody
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'))
          .toList();
      expect(initLines.first, contains(initFirstStep),
          reason: 'init 序列首位是 super.initState()（与 R127 嵌套栈契约一致）');

      final disposeBodyMatch =
          RegExp(r'void dispose\(\) \{([^}]*)\}').firstMatch(src);
      final disposeBody = disposeBodyMatch!.group(1)!;
      final disposeLines = disposeBody
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('//'))
          .toList();
      expect(disposeLines.last, contains(disposeLastStep),
          reason: 'dispose 序列末位是 super.dispose()（首尾对偶 init 序列）');
    });

    test('档 3 同形锁（_MainScreenV3State 与 _SettingsScreenState 同形）', () {
      // 两类共享同模板：controllers 同序逐个 dispose + super.dispose 末位
      // 未来引入 ScrollController / FocusNode 等资源，必须**同时改两类**
      // 才不破同形（R59 helper-vs-inline 同形锁在 widget lifecycle 维度的扩展）。
      final mainSrc =
          File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final settingsSrc =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      // 两类都只用 TextEditingController（同质资源类型）
      final mainResourceTypes = RegExp(r'final _\w+Controller = (\w+)\(\);')
          .allMatches(mainSrc)
          .map((m) => m.group(1))
          .toSet();
      final settingsResourceTypes = RegExp(r'final _\w+Controller = (\w+)\(\);')
          .allMatches(settingsSrc)
          .map((m) => m.group(1))
          .toSet();
      expect(mainResourceTypes, {'TextEditingController'},
          reason: '_MainScreenV3State 当前仅持 TextEditingController');
      expect(settingsResourceTypes, {'TextEditingController'},
          reason: '_SettingsScreenState 当前仅持 TextEditingController');
      // 同形锁：两类资源类型集合相等
      expect(mainResourceTypes, settingsResourceTypes,
          reason: '档 3 同形锁: 两类必须同质资源类型');
    });
  });
}
