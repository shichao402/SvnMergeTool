import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc comment 与 `//` 行注释，避免 doc 字面量
/// 与代码字面量混淆——R130 起统一防御 doc-as-test 反向自匹配。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R131 widget setState 时机 + mounted check 一致性审计 — 三档分类 +
/// 跨档不变量 I1/I2/I3**
///
/// 三档分类（widget 维度，对偶 R128 provider 触发协议）：
/// - 档 1 = sync 直接 setState（同步事件回调内紧跟 mutator，闭包内无 await）
/// - 档 2 = conditional / 嵌套 mounted-guarded setState（被宿主函数 guard）
/// - 档 3 = async-bracket setState（跨 await 边界，必须前置 mounted check）
///
/// 跨档不变量：
/// - I1: 档 3 站点 100% 配 mounted check（运行时硬契约）
/// - I2: lib 内非 widget 类 0 处 setState（provider/service 只能 notifyListeners）
/// - I3: 档 2/档 3 不可降档为档 1（哪怕看起来同步，闭包内有 await 即档 3）
void main() {
  group('R131 档 1 — sync 直接 setState（无 await）', () {
    test('main_screen_v3.dart 同步事件回调站点齐全', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // 同步 setState 站点都是 mutator-only / 集合 clear / 标志位赋值
      expect(src, contains('setState(() => _selectedRevisions.clear());'),
          reason: '_clearSelectedRevisions 档 1：同步清空选择');
      expect(src, contains('setState(() => _pendingSourceUrl = null);'),
          reason: '_clearPendingRevisions 档 3：confirm 后清 pendingSourceUrl，前置 mounted 守护');
    });

    test('settings_screen.dart 同步 SwitchListTile / CheckboxListTile setState 站点存在',
        () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      expect(src, contains('_preloadEnabled = value;'),
          reason: '档 1 onChanged 同步赋值');
      expect(src, contains('_stopOnBranchPoint = value ?? true;'),
          reason: '档 1 CheckboxListTile onChanged 同步赋值');
    });
  });

  group('R131 档 3 — async-bracket setState 必须前置 mounted check (I1)', () {
    test('main_screen_v3.dart 所有档 3 站点均配 mounted 守护', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());

      // 档 3 #1: _onProgressChanged 回调（preloadService.init().then）
      expect(
        RegExp(
          r'if\s*\(\s*!mounted\s*\)\s*return\s*;\s*\n\s*\n?\s*setState',
          multiLine: true,
        ).hasMatch(src),
        isTrue,
        reason: '档 3 站点 643 行：preloadService 进度回调，setState 前必带 mounted check',
      );

      // 档 3 #2: _loadPreloadSettings —— `if (mounted) { setState(...); }`
      expect(
        RegExp(r'if\s*\(\s*mounted\s*\)\s*\{\s*\n\s*setState')
            .hasMatch(src),
        isTrue,
        reason: '档 3 站点 699 行：getPreloadSettingsTyped await 后 if(mounted){setState}',
      );

      // 档 3 #3: _refreshLogCacheSummary —— await 后 mounted return + setState
      expect(src, contains('if (!mounted) return;'),
          reason: '档 3 站点 844 行：getLatestRangeEntryCount await 后 mounted check');

      // 档 3 #4: _openSettings —— `if (result != null && mounted)`
      expect(src, contains('result != null && mounted'),
          reason: '档 3 站点 1558 行：SettingsScreen.show await 后 mounted 短路');
    });

    test('R131 漏档修复 #1 — _syncLatestLogs 闭包补 mounted check', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // 必须能找到 syncFromHead 后紧跟 mounted check（修复前是 setState 紧贴 await）
      final pattern = RegExp(
        r'_logSyncService\.syncFromHead\([^)]*?\)[^;]*;\s*'
        r'(?:.|\n)*?if\s*\(\s*!mounted\s*\)\s*\{?\s*\n?\s*return',
        multiLine: true,
      );
      expect(pattern.hasMatch(src), isTrue,
          reason:
              'R131 漏档修复：_syncLatestLogs 闭包内 setState 前必须有 mounted check（与 _loadMoreLogs 对偶）');
    });

    test('R131 漏档修复 #2 — settings_screen.dart _pickDate 补 mounted check', () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      final pattern = RegExp(
        r'showDatePicker\([\s\S]*?\)\s*;\s*\n\s*\n?\s*if\s*\(\s*picked\s*!=\s*null\s*\)\s*\{\s*\n\s*if\s*\(\s*!mounted\s*\)\s*return',
      );
      expect(pattern.hasMatch(src), isTrue,
          reason:
              'R131 漏档修复：_pickDate 在 showDatePicker await 后 setState 前必须有 mounted check');
    });
  });

  group('R131 档 2 — conditional / 嵌套 mounted-guarded setState', () {
    test('_loadMoreLogs 闭包内 setState 由前置 1093 行 mounted check 守护', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // 闭包内必须含：if (!mounted) { return ... }，然后再两个 setState 分支
      final pattern = RegExp(
        r'if\s*\(\s*!mounted\s*\)\s*\{\s*\n\s*return\s+addedCount\s*;\s*\n\s*\}\s*\n'
        r'\s*\n?\s*if\s*\(\s*addedCount\s*==\s*0\s*\)\s*\{\s*\n\s*setState',
        multiLine: true,
      );
      expect(pattern.hasMatch(src), isTrue,
          reason:
              '_loadMoreLogs 档 2：mounted-guard 在前 / setState 双分支在后');
    });
  });

  group('R131 I2 — lib 内非 widget 类 0 处 setState', () {
    test('lib/providers/ 0 处 setState（与 R130 I4 接合面）', () {
      final dir = Directory('lib/providers');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        expect(src.contains('setState('), isFalse,
            reason: 'provider 类不可调 setState（${f.path}），只能 notifyListeners (R128)');
      }
    });

    test('lib/services/ 0 处 setState（service 完全无 widget 协议）', () {
      final dir = Directory('lib/services');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        expect(src.contains('setState('), isFalse,
            reason: 'service 不可调 setState（${f.path}），只是无状态/Disposable 单例');
      }
    });

    test('lib/models/ 0 处 setState', () {
      final dir = Directory('lib/models');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        expect(src.contains('setState('), isFalse,
            reason: 'model 纯数据/纯函数，不可 setState（${f.path}）');
      }
    });

    test('lib/execution/ 0 处 setState', () {
      final dir = Directory('lib/execution');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        expect(src.contains('setState('), isFalse,
            reason: 'execution 状态机/任务调度纯逻辑，不可 setState（${f.path}）');
      }
    });

    test('lib/widgets/ 0 处 setState（widgets 子库均为 StatelessWidget / 路由到 Consumer）',
        () {
      final dir = Directory('lib/widgets');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        expect(src.contains('setState('), isFalse,
            reason: 'widgets 子库无独立状态，rebuild 由父 State / Consumer 驱动（${f.path}）');
      }
    });
  });

  group('R131 setState 站点全集统计 — 三 widget 类锁定', () {
    test(
        'lib/ 内 setState 站点都集中在 main_screen_v3 / settings_screen / log_dialog 三个 State 类',
        () {
      final libDir = Directory('lib');
      final setStateFiles = <String>[];
      for (final f in libDir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('setState(')) {
          setStateFiles.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(setStateFiles.toSet(), {
        'lib/screens/main_screen_v3.dart',
        'lib/screens/settings_screen.dart',
        'lib/screens/components/dialogs/log_dialog.dart',
      },
          reason:
              'R131 锁：lib 内仅这三个文件含 setState；增加新 widget 也必须通过审计扩展。'
              'log_dialog 加入是因 P2 日志关键字搜索（StatefulWidget + 档 1 sync 直接 setState）。');
    });

    test('lib/ 内 mounted check 也集中在同样两个 State 类（+ log_dialog 内 context.mounted）',
        () {
      final libDir = Directory('lib');
      final mountedFiles = <String>[];
      for (final f in libDir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (RegExp(r'\bmounted\b').hasMatch(src)) {
          mountedFiles.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(mountedFiles.toSet(), {
        'lib/screens/main_screen_v3.dart',
        'lib/screens/settings_screen.dart',
        'lib/screens/components/dialogs/log_dialog.dart',
        'lib/screens/components/dialogs/config_dialog.dart',
      },
          reason:
              'R131 锁：mounted 出现位置仅这四个文件（log_dialog / config_dialog 用 context.mounted）');
    });
  });

  group('R131 接合面 — 与 R128/R129/R130 三角元说明', () {
    test('main_screen_v3.dart doc 内必含 R131 三档分类 + I1/I2/I3 不变量元说明', () {
      // 此 test 不剥注释——读 doc 字面量
      final src =
          File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src, contains('R131 widget setState 时机'),
          reason: 'doc-as-test：main_screen_v3.dart 必含 R131 标题元说明');
      expect(src, contains('档 1 = sync 直接 setState'),
          reason: 'doc-as-test：必含档 1 定义');
      expect(src, contains('档 2 = conditional'),
          reason: 'doc-as-test：必含档 2 定义');
      expect(src, contains('档 3 = async-bracket setState'),
          reason: 'doc-as-test：必含档 3 定义');
      expect(src, contains('I1: 档 3 站点 100% 配 mounted check'),
          reason: 'doc-as-test：必含 I1');
      expect(src, contains('I2: lib 内非 widget 类 0 处 setState'),
          reason: 'doc-as-test：必含 I2');
      expect(src, contains('I3: 档 2 / 档 3 不可降档为档 1'),
          reason: 'doc-as-test：必含 I3');
    });

    test('R131 与 R128 形成 trigger 协议对偶（生产端 vs 消费端时机）', () {
      final src =
          File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src, contains('与 R128 形成'),
          reason: 'R131 必须显式声明与 R128 的 trigger 协议对偶关系');
      expect(src, contains('R131 锁 widget setState 时机（消费端时机）'),
          reason: '消费端时机 = R131 与 R128 (生产端时机) 对偶定位');
    });

    test('R131 漏档收口元说明 — 延伸 R85-R89 漏迁巡检模式到 widget 维度', () {
      final src =
          File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src, contains('R131 漏档收口'),
          reason: 'doc-as-test：必含本轮漏档收口元说明');
      expect(src, contains('R85-R89 漏迁'),
          reason: 'R131 = 漏迁巡检模式 widget 化');
    });
  });
}
