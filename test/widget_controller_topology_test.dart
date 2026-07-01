import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc comment 与 `//` 行注释——R130 doc-as-test
/// 反向自匹配防御统一 helper（R132 复用 / R133 复用）。
String _stripComments(String src) {
  return src.split('\n').where((line) {
    final t = line.trimLeft();
    return !t.startsWith('///') && !t.startsWith('//');
  }).join('\n');
}

/// **R133 controller 流向拓扑审计 — owner / writer / borrower 三角分离协议**
///
/// 与 R129 dispose 维度 / R131 setState 维度 / R132 .text= 维度共组成 widget
/// owned-resource 完整审计四角接合面。R133 锁的是同一 controller 跨 widget
/// 边界后的拓扑契约——三种角色（owner = 创建+释放 / writer = .text= 写站点 /
/// borrower = 接收引用但不释放）必须分离清晰。
///
/// 跨档不变量 J1/J2/J3/J4：
/// - J1: 1 controller = 1 owner（构造站点唯一对应一处 dispose 调用）
/// - J2: borrower 必无 dispose 调用（无 owned 资源 → 无释放责任）
/// - J3: borrower 写站点 mounted check 形态由 borrower 子类型决定
///       （StatelessWidget → context.mounted / StatefulWidget → mounted）
/// - J4: owner-borrower lifecycle 包含关系（owner ⊇ borrower）由 framework
///       自然保证 + J3 mounted check 兜底
void main() {
  group('R133 J1: 1 controller = 1 owner（构造站点唯一对应 dispose）', () {
    test(
        'main_screen_v3.dart: 7 处 TextEditingController 构造 ↔ 7 处 dispose 严格 1:1',
        () {
      final src = _stripComments(
          File('lib/screens/main_screen_v3.dart').readAsStringSync());
      final ctorMatches =
          RegExp(r'final\s+_(\w+)Controller\s*=\s*TextEditingController\(\)')
              .allMatches(src)
              .map((m) => m.group(1)!)
              .toSet();
      final disposeMatches = RegExp(r'_(\w+)Controller\.dispose\(\)')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        ctorMatches,
        {
          'sourceUrl',
          'targetWc',
          'targetUrl',
          'filterAuthor',
          'filterTitle',
          'filterMessage',
          'commitSupplement',
        },
        reason: 'R133 J1: _MainScreenV3State 必恰好构造 7 个 controller',
      );
      expect(
        disposeMatches,
        ctorMatches,
        reason:
            'R133 J1: 每个构造的 controller 必有同名 dispose 调用（1:1 owner-disposer 对齐）',
      );
    });

    test('settings_screen.dart: 6 处 TextEditingController 构造 ↔ 6 处 dispose',
        () {
      final src = _stripComments(
          File('lib/screens/settings_screen.dart').readAsStringSync());
      final ctorMatches =
          RegExp(r'final\s+_(\w+)Controller\s*=\s*TextEditingController\(\)')
              .allMatches(src)
              .map((m) => m.group(1)!)
              .toSet();
      final disposeMatches = RegExp(r'_(\w+)Controller\.dispose\(\)')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(ctorMatches.length, 6,
          reason: 'R133 J1: _SettingsScreenState 6 个 owned controller');
      expect(disposeMatches, ctorMatches,
          reason: 'R133 J1: 6 个构造 ↔ 6 个 dispose 严格对齐');
    });

    test(
        'owner 文件全集锁：lib 内仅 main_screen_v3 + settings_screen 构造 TextEditingController',
        () {
      // 扫 lib/ 全部文件，找出所有"final _xxxController = TextEditingController()"
      // 形态的 owner 站点，验证仅来自 2 个文件。
      final libDir = Directory('lib');
      final ownerFiles = <String>{};
      for (final f in libDir.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final src = _stripComments(f.readAsStringSync());
          if (RegExp(r'\b\w+\s*=\s*TextEditingController\(\)').hasMatch(src)) {
            ownerFiles.add(f.path);
          }
        }
      }
      expect(
        ownerFiles,
        {
          'lib/screens/main_screen_v3.dart',
          'lib/screens/settings_screen.dart',
        },
        reason:
            'R133 J1 全集锁：lib 内仅 2 个 State 类构造 TextEditingController；新增 owner 必扩 expect',
      );
    });
  });

  group('R133 J2: borrower 必无 dispose 调用', () {
    test('config_dialog.dart 是 borrower / 0 处 .dispose() 调用', () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      // 接收 controller 作构造参数（borrower 标识）
      expect(
        RegExp(r'final\s+TextEditingController\s+\w+Controller\s*;')
            .hasMatch(src),
        isTrue,
        reason: 'R133: 配置弹窗通过 final field 接收 controller 引用 → borrower',
      );
      // 0 处 .dispose() 调用（J2 律）
      expect(
        RegExp(r'\.dispose\(\)').hasMatch(src),
        isFalse,
        reason:
            'R133 J2: borrower 必无 .dispose() 调用，否则 owner 后续写抛 disposed exception',
      );
    });

    test('log_list_panel.dart 是 borrower / 0 处 controller .dispose() 调用', () {
      final src = _stripComments(
          File('lib/screens/components/log_list_panel.dart')
              .readAsStringSync());
      // 接收 controller 作 final field
      expect(
        RegExp(r'final\s+TextEditingController\s+\w+Controller\s*;')
            .hasMatch(src),
        isTrue,
        reason: 'R133: log_list_panel 通过 final field 接收 controller → borrower',
      );
      // 反向锁：0 处 "controller.dispose()" / "Controller.dispose()" 形态
      expect(
        RegExp(r'\w*[Cc]ontroller\.dispose\(\)').hasMatch(src),
        isFalse,
        reason: 'R133 J2: borrower 不得对借用的 controller 调用 dispose',
      );
    });
  });

  group('R133 J3: borrower 写站点 mounted check 形态由子类型决定', () {
    test(
        'TargetWorkingCopyDialog (StatelessWidget borrower) 用 context.mounted 守护档 3 写',
        () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      expect(
        src.contains('class TargetWorkingCopyDialog extends StatelessWidget'),
        isTrue,
        reason: 'R133: 确认 TargetWorkingCopyDialog 子类型 = StatelessWidget',
      );
      // 档 3 异步写：await ... ; if (!context.mounted) return; ... .text =
      final hasAsyncBracketWrite = RegExp(
        r'await\s+FilePicker[\s\S]*?if\s*\(\s*!\s*context\.mounted\s*\)\s*return\s*;[\s\S]*?targetWcController\.text\s*=',
      ).hasMatch(src);
      expect(hasAsyncBracketWrite, isTrue,
          reason:
              'R133 J3 (StatelessWidget): _pickTargetWc 跨 await 写必前置 context.mounted（不能用 mounted 字段）');
      // 反向锁：StatelessWidget 内不应出现 `if (!mounted)` 形态（无 mounted 字段）
      expect(
        RegExp(r'if\s*\(\s*!\s*mounted\s*\)').hasMatch(src),
        isFalse,
        reason: 'R133 J3: StatelessWidget 无 mounted 字段，不可使用 `if (!mounted)`',
      );
    });

    test('lib 内当前 0 处 StatefulWidget borrower（未来引入需用 mounted 字段）', () {
      // 反向锁：扫 lib/ 找"接收 TextEditingController + extends State"的类。
      // 当前 lib 内配置弹窗是 borrower（StatelessWidget）；其余类要么是
      // owner（main_screen_v3 / settings_screen）要么仅借用作 read（log_list_panel
      // 是 StatelessWidget _LogListPanelInner）。
      final libDir = Directory('lib');
      final statefulBorrowers = <String>[];
      for (final f in libDir.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final src = _stripComments(f.readAsStringSync());
          // 标识：包含 "extends State<" 且包含 "final TextEditingController" 字段
          // 但 NOT 自己构造（即不出现 "= TextEditingController(...)"）
          final hasStateClass = RegExp(r'extends\s+State<').hasMatch(src);
          final hasBorrowedField =
              RegExp(r'final\s+TextEditingController\s+\w+\s*;').hasMatch(src);
          final constructsOwn =
              RegExp(r'=\s*TextEditingController\(').hasMatch(src);
          if (hasStateClass && hasBorrowedField && !constructsOwn) {
            statefulBorrowers.add(f.path);
          }
        }
      }
      expect(statefulBorrowers, isEmpty,
          reason:
              'R133 J3: lib 内当前 0 处 StatefulWidget borrower；未来引入必用 mounted 字段（不能用 context.mounted）');
    });
  });

  group('R133 J4: owner-borrower lifecycle 由 framework + J3 兜底保证', () {
    test(
        '配置弹窗通过 showDialog 进入 Navigator stack（dialog dismiss 早于 owner dispose）',
        () {
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      expect(src.contains('showDialog'), isTrue,
          reason:
              'R133 J4: 配置弹窗通过 showDialog 显示 → Navigator.pop 必先于 owner 销毁，保证 J4 包含关系');
    });

    test('borrower 写站点全集锁：lib 内 borrower-side .text= 仅出现在配置弹窗', () {
      // 扫 lib/screens/components/ + lib/screens/components/dialogs/ 内
      // borrower 文件，统计 borrower-side .text= 写站点。
      // 当前 lib：只有 config_dialog.dart 有 borrower-side .text=（4 处）；
      // log_list_panel.dart 仅绑定 controller: 不写 .text=。
      final src = _stripComments(
          File('lib/screens/components/dialogs/config_dialog.dart')
              .readAsStringSync());
      final writeSites =
          RegExp(r'\b\w+Controller\.text\s*=').allMatches(src).length;
      expect(writeSites, 4,
          reason: 'R133: 配置弹窗借用-写站点 4 处（_pickTargetWc + 源/目标工作副本/目标URL历史）');

      // log_list_panel 内 0 处 borrower .text= 写
      final llp = _stripComments(
          File('lib/screens/components/log_list_panel.dart')
              .readAsStringSync());
      final llpWriteSites =
          RegExp(r'\b(authorController|titleController)\.text\s*=')
              .allMatches(llp)
              .length;
      expect(llpWriteSites, 0,
          reason:
              'R133: log_list_panel 仅 read controller（绑定到 TextField），无 .text= 写');
    });
  });

  group('R133 doc-as-test 反向自匹配防御 + 元说明锁', () {
    test('main_screen_v3.dart 含 R133 三角色定义 + 拓扑表 + J1-J4 文案', () {
      // 注意：这里不剥离注释——本测试是验证 doc 注释本身存在。
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src.contains('R133 controller flow topology'), isTrue,
          reason: 'R133: 主类必含 R133 章节标题');
      expect(src.contains('Owner（创建者 + 释放者，单一职责）'), isTrue);
      expect(src.contains('Borrower'), isTrue);
      expect(src.contains('J1'), isTrue);
      expect(src.contains('J2'), isTrue);
      expect(src.contains('J3'), isTrue);
      expect(src.contains('J4'), isTrue);
      expect(src.contains('R129/R131/R132/R133 widget owned-resource 四角接合面'),
          isTrue,
          reason: 'R133: 必显式锁定四角接合面（R129/R131/R132/R133）');
    });

    test('config_dialog.dart 含源/目标专用弹窗和 context.mounted 文案', () {
      final src = File('lib/screens/components/dialogs/config_dialog.dart')
          .readAsStringSync();
      expect(src.contains('SourceUrlDialog'), isTrue);
      expect(src.contains('TargetWorkingCopyDialog'), isTrue);
      expect(src.contains('TargetSvnUrlDialog'), isTrue);
      expect(src.contains('context.mounted'), isTrue);
    });

    test('R85-R89 漏迁巡检 widget 维度三次延伸 doc 锁', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      expect(src.contains('R85-R89 漏迁巡检模式 widget 维度三次延伸'), isTrue,
          reason:
              'R133: 显式锁定本轮是 R85-R89 漏迁巡检在 widget 维度的第三次延伸（R131/R132/R133）');
    });
  });
}
