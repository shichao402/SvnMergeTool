import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc comment 与 `//` 行注释——R130 doc-as-test
/// 反向自匹配防御统一 helper。
String _stripComments(String src) {
  return src.split('\n').where((line) {
    final t = line.trimLeft();
    return !t.startsWith('///') && !t.startsWith('//');
  }).join('\n');
}

/// **R132 TextEditingController.text 写时机审计 — 三档分类 +
/// 跨档不变量 I1/I2/I3 + R129/R131/R132 widget owned-resource 三角接合面**
///
/// 三档分类（widget owned-resource .text= 维度，对偶 R131 setState 维度）：
/// - 档 1 = sync 直接 .text=（initState 同步路径 / 同步事件回调内紧跟 .text=）
/// - 档 2 = 嵌套 mounted-guarded .text=（受宿主函数 guard 的回调闭包内）
/// - 档 3 = async-bracket .text=（跨 await 边界，必须前置 mounted check）
///
/// 跨档不变量：
/// - I1: 档 3 站点 100% 配 mounted / context.mounted check（运行时硬契约）
/// - I2: 仅 widget 类持有 owned TextEditingController（provider/service/model 0 处）
/// - I3: StatefulWidget 用 `mounted`，StatelessWidget 用 `context.mounted`
void main() {
  group('R132 档 1 — sync 直接 .text=（无 await）', () {
    test('main_screen_v3.dart _initializeFields 同步路径 .text= 站点齐全', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // _initializeFields 在 initState 同步路径调用——档 1
      expect(
          src, contains('_sourceUrlController.text = appState.lastSourceUrl!;'),
          reason: '档 1 initState 同步路径赋值 lastSourceUrl');
      expect(
          src, contains('_targetWcController.text = appState.lastTargetWc!;'),
          reason: '档 1 initState 同步路径赋值 lastTargetWc');
    });

    test('settings_screen.dart _loadSettings 同步路径 .text= 站点齐全', () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      expect(
          src,
          contains(
              '_maxDaysController.text = formatPositiveIntForField(_maxDays);'),
          reason: '档 1 initState 同步路径赋值 maxDays');
      expect(
          src, contains('_maxRetriesController.text = _maxRetries.toString();'),
          reason: '档 1 initState 同步路径赋值 maxRetries');
    });

    test('config_dialog.dart 同步事件回调 .text= 站点存在', () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      // PopupMenuButton onSelected 是同步事件回调 —— 档 1
      // sourceUrl 站点经 stripUrlWhitespace 净化（对历史记录里残留的脏数据
      // 做防御 — controller.text 的 setter 不走 TextInputFormatter，故必须
      // 显式 strip）。targetWc 是路径，合法含空格，原样赋值。
      expect(src,
          contains('sourceUrlController.text = stripUrlWhitespace(value);'),
          reason:
              '档 1 PopupMenuButton.onSelected 同步赋值 sourceUrl（经 stripUrlWhitespace 净化）');
      expect(src, contains('targetWcController.text = value;'),
          reason: '档 1 PopupMenuButton.onSelected 同步赋值 targetWc（路径不剥空白）');
    });
  });

  group('R132 档 3 — async-bracket .text= 必带 mounted check', () {
    test('main_screen_v3.dart _loadAuthorFilterHistory 必有 mounted guard', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // R132 修复站点：await getLast*Filter() 后必须 if (!mounted) return
      // 然后才能写 _filter*Controller.text
      // 三个 last* 顺序 await 后单一 mounted guard，再写三个 controller。
      final m = RegExp(
        r'final lastAuthor = await storageService\.getLastAuthorFilter\(\);\s*\n\s*final lastTitle = await storageService\.getLastTitleFilter\(\);\s*\n\s*final lastMessage = await storageService\.getLastMessageFilter\(\);\s*\n\s*if \(!mounted\) return;\s*\n\s*if \(lastAuthor != null',
      );
      expect(m.hasMatch(src), isTrue,
          reason:
              'R132 漏档修复 #1：_loadAuthorFilterHistory 在 三个 await 后必须 if (!mounted) return 后才写 _filter*Controller.text');
    });

    test('config_dialog.dart _pickTargetWc 必有 context.mounted guard', () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      // R132 修复站点：StatelessWidget 用 context.mounted（无 mounted 字段可用）
      final m = RegExp(
        r'final result = await FilePicker\.platform\.getDirectoryPath\(\);\s*\n\s*if \(!context\.mounted\) return;',
      );
      expect(m.hasMatch(src), isTrue,
          reason:
              'R132 漏档修复 #2：StatelessWidget _pickTargetWc 在 await 后必须 if (!context.mounted) return');
    });

    test('settings_screen.dart _pickDate 闭包内 .text= 已由 R131 mounted guard 守护',
        () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      // R131 修复点同时覆盖 R132 维度：if (!mounted) return 守护后续 setState
      // 闭包内的 _stopDateController.text 写入。验证模式仍存在。
      final m = RegExp(
        r'if \(picked != null\) \{\s*\n\s*if \(!mounted\) return;\s*\n\s*setState\(\(\) \{[\s\S]*?_stopDateController\.text = _stopDate!;',
      );
      expect(m.hasMatch(src), isTrue,
          reason:
              'R131 修复同时锁 R132 维度：_pickDate 闭包内 .text= 受 if (!mounted) return 守护');
    });
  });

  group('R132 I2 — 仅 widget 持有 owned TextEditingController', () {
    test('lib/providers/ 0 处 TextEditingController 字段', () {
      final dir = Directory('lib/providers');
      var hits = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('TextEditingController')) hits++;
      }
      expect(hits, 0,
          reason: 'I2: provider 不应持有 TextEditingController（与 widget 解耦）');
    });

    test('lib/services/ 0 处 TextEditingController 字段', () {
      final dir = Directory('lib/services');
      var hits = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('TextEditingController')) hits++;
      }
      expect(hits, 0, reason: 'I2: service 不应持有 TextEditingController');
    });

    test('lib/models/ 0 处 TextEditingController 字段', () {
      final dir = Directory('lib/models');
      var hits = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('TextEditingController')) hits++;
      }
      expect(hits, 0, reason: 'I2: model 不应持有 TextEditingController');
    });

    test('lib/execution/ 0 处 TextEditingController 字段', () {
      final dir = Directory('lib/execution');
      if (!dir.existsSync()) return;
      var hits = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('TextEditingController')) hits++;
      }
      expect(hits, 0, reason: 'I2: execution 不应持有 TextEditingController');
    });
  });

  group('R132 I3 — mounted vs context.mounted 选型', () {
    test('main_screen_v3 (StatefulWidget) 全部用 mounted', () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      // StatefulWidget 优先用 `mounted` 字段（更可靠）；不应使用 context.mounted
      expect(src.contains('context.mounted'), isFalse,
          reason: 'StatefulWidget 应用 mounted 字段，禁止 context.mounted');
    });

    test('config_dialog (StatelessWidget) 用 context.mounted', () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      // StatelessWidget 无 mounted 字段，必须用 context.mounted
      expect(src.contains('context.mounted'), isTrue,
          reason: 'StatelessWidget 必须用 context.mounted（无 mounted 字段）');
    });

    test('settings_screen (StatefulWidget) 全部用 mounted', () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      expect(src.contains('context.mounted'), isFalse,
          reason: 'StatefulWidget 应用 mounted 字段，禁止 context.mounted');
    });
  });

  group('R132 站点全集锁 — TextEditingController 仅在 5 文件出现', () {
    test('lib/ 内 TextEditingController 仅出现在 5 文件', () {
      final dir = Directory('lib');
      final hits = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (src.contains('TextEditingController')) {
          hits.add(f.path.replaceAll(r'\', '/'));
        }
      }
      // 期望集合：5 文件
      // - lib/screens/main_screen_v3.dart（6 controller declaration + .text= 写，owner）
      // - lib/screens/settings_screen.dart（6 controller declaration + .text= 写，owner）
      // - lib/screens/components/dialogs/config_dialog.dart（接收外部注入 + .text= 写，borrower）
      // - lib/screens/components/log_list_panel.dart（接收外部注入 — 仅 .text 读，borrower）
      // - lib/screens/components/pending_panel.dart（接收 commitSupplementController 仅 .text 读，borrower）
      expect(
          hits.toSet(),
          {
            'lib/screens/main_screen_v3.dart',
            'lib/screens/settings_screen.dart',
            'lib/screens/components/dialogs/config_dialog.dart',
            'lib/screens/components/log_list_panel.dart',
            'lib/screens/components/pending_panel.dart',
          },
          reason: '全集锁：TextEditingController 仅在 5 文件出现 —— '
              '新增文件触发此测试需更新登记表');
    });
  });

  group('R132 接合面 — R129/R131/R132 widget owned-resource 三角', () {
    test('doc-as-test：三档分类元说明在 main_screen_v3 lib doc 中', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // 此组测试反查 lib doc 内 R132 三档分类 + I1/I2/I3 元说明文案存在
      expect(src.contains('R132 TextEditingController.text 写时机审计'), isTrue,
          reason: 'R132 lib doc 元说明应明文存在于 main_screen_v3');
      expect(src.contains('档 1 = sync 直接 .text='), isTrue, reason: '档 1 元说明');
      expect(src.contains('档 3 = async-bracket .text='), isTrue,
          reason: '档 3 元说明');
      expect(src.contains('I1: 档 3 `.text=` 站点 100% 配'), isTrue,
          reason: 'I1 元说明');
      expect(src.contains('I3: StatefulWidget 用 `mounted`'), isTrue,
          reason: 'I3 元说明');
    });

    test('R129/R131/R132 三角文案在 main_screen_v3 lib doc', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src.contains('widget owned-resource 三角'), isTrue,
          reason: 'R132 lib doc 应明确 R129/R131/R132 接合面三角');
      expect(src.contains('R85-R89 漏迁'), isTrue,
          reason: 'R132 漏档收口 = R85-R89 漏迁巡检模式 widget 维度二次延伸');
    });
  });
}
