/// ConfigDialog 源 URL 输入净化契约。
///
/// 锁两件事：
/// 1. 顶层 helper [stripUrlWhitespace]：行为契约（empty / 仅空白 / 内嵌空白
///    / Unicode 空白 / 中文等 non-whitespace 字符 / percent-encoded 不展开）；
/// 2. [UrlInputFormatter] 作为 [TextField.inputFormatters] 的实测表现：
///    用户键入 / 粘贴含空白的 URL → controller.text 立刻为净化后字符串，
///    光标位置 clamp 到合法区间。
///
/// 这个 formatter 解决的真实场景：用户从 wiki / 工单 / 聊天复制 SVN URL，
/// 经常带 leading/trailing 空格、trailing `\n`、富文本里穿插的不可见字符
/// （如 NBSP `\u00A0`）；不净化的话下游 `Uri.parse` 可能成功但 svn info
/// 报 404，用户排查链路加长。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/screens/components/dialogs/config_dialog.dart';

void main() {
  group('stripUrlWhitespace', () {
    test('空串 → 空串（不做任何处理直接返回）', () {
      expect(stripUrlWhitespace(''), '');
    });

    test('全是空白 → 空串', () {
      expect(stripUrlWhitespace('   '), '');
      expect(stripUrlWhitespace('\t\n\r '), '');
    });

    test('无空白的 URL → 原样返回', () {
      expect(
        stripUrlWhitespace('https://repo.example.com/svn/branches/feature'),
        'https://repo.example.com/svn/branches/feature',
      );
    });

    test('leading 空白被剥', () {
      expect(stripUrlWhitespace('   https://repo/branch'), 'https://repo/branch');
    });

    test('trailing 空白被剥', () {
      expect(stripUrlWhitespace('https://repo/branch   '), 'https://repo/branch');
    });

    test('trailing 换行被剥（粘贴时最常见）', () {
      expect(stripUrlWhitespace('https://repo/branch\n'), 'https://repo/branch');
      expect(
        stripUrlWhitespace('https://repo/branch\r\n'),
        'https://repo/branch',
      );
    });

    test('内部空白也被剥（不只是 trim 头尾）', () {
      // 这是 trim() 不能解决的——例如富文本复制时偶尔会在 URL 中间
      // 插入零宽空格 / NBSP / 软换行。
      expect(
        stripUrlWhitespace('https://repo /branch'),
        'https://repo/branch',
      );
      expect(
        stripUrlWhitespace('https://repo\t/branch'),
        'https://repo/branch',
      );
    });

    test('NBSP (U+00A0) 也被剥（RegExp \\s 默认匹配 Unicode 空白）', () {
      expect(
        stripUrlWhitespace('https://repo\u00A0/branch'),
        'https://repo/branch',
      );
    });

    test('已经 percent-encoded 的 %20 不展开成空格再剥', () {
      // 关键不变量：本 helper 不做解码，只删字面空白字符。
      expect(
        stripUrlWhitespace('https://repo/branches/feature%20test'),
        'https://repo/branches/feature%20test',
      );
    });

    test('中文 / Unicode 表情等 non-whitespace 字符原样保留', () {
      expect(
        stripUrlWhitespace('https://repo/分支/测试'),
        'https://repo/分支/测试',
      );
    });

    test('返回值长度 ≤ 入参长度（永远只删不加）', () {
      const cases = [
        '',
        'abc',
        '  abc  ',
        'a b c',
        'https://x',
        '\t\n\r',
      ];
      for (final c in cases) {
        expect(
          stripUrlWhitespace(c).length <= c.length,
          isTrue,
          reason: '入参 "$c"',
        );
      }
    });
  });

  group('UrlInputFormatter.formatEditUpdate', () {
    const formatter = UrlInputFormatter();

    TextEditingValue value(String text, [int? offset]) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset ?? text.length),
      );
    }

    test('无空白输入 → newValue 原样返回（identity，不重建对象）', () {
      const oldVal = TextEditingValue.empty;
      final newVal = value('https://repo/branch');
      final result = formatter.formatEditUpdate(oldVal, newVal);
      // identity 不强制要求，但断言 text 与 selection 完全相同
      expect(result.text, newVal.text);
      expect(result.selection, newVal.selection);
    });

    test('粘贴 trailing 换行 → 净化为无换行字符串，光标移到末尾', () {
      const oldVal = TextEditingValue.empty;
      final newVal = value('https://repo/branch\n', 20); // \n 之后
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'https://repo/branch');
      // 净化后长度 19，原 offset 20 应被 clamp 到 19
      expect(result.selection.baseOffset, 19);
    });

    test('粘贴 leading 空白 → 净化', () {
      const oldVal = TextEditingValue.empty;
      final newVal = value('   https://repo/branch', 22);
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'https://repo/branch');
      expect(result.selection.baseOffset, 19);
    });

    test('光标在中间且文本被净化 → clamp 到不超过新长度', () {
      const oldVal = TextEditingValue.empty;
      // 模拟用户在 'https:// repo' 中间位置（offset=8，正好在空格上）
      final newVal = value('https:// repo', 8);
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'https://repo');
      // 8 ≤ 12（新长度），保留 8
      expect(result.selection.baseOffset, 8);
    });

    test('光标 offset 超过新长度 → clamp 到新长度', () {
      const oldVal = TextEditingValue.empty;
      final newVal = value('a   ', 4); // 末尾，4
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'a');
      expect(result.selection.baseOffset, 1);
    });

    test('全部为空白 → 净化为空串，光标到 0', () {
      const oldVal = TextEditingValue.empty;
      final newVal = value('   \n', 4);
      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '');
      expect(result.selection.baseOffset, 0);
    });
  });

  group('TextField + UrlInputFormatter 集成验证', () {
    testWidgets('粘贴含 trailing 换行的 URL → controller.text 已净化', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: const [UrlInputFormatter()],
          ),
        ),
      ));

      // 模拟用户聚焦后输入（粘贴效果）
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'https://repo.example.com/svn/branches/feature\n',
      );
      await tester.pump();

      expect(controller.text, 'https://repo.example.com/svn/branches/feature');
      controller.dispose();
    });

    testWidgets('粘贴含内嵌空格的 URL → controller.text 内部空格被剥', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: const [UrlInputFormatter()],
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), 'https://repo /branch');
      await tester.pump();

      expect(controller.text, 'https://repo/branch');
      controller.dispose();
    });

    testWidgets('正常无空白输入 → controller.text 原样保留', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: const [UrlInputFormatter()],
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), 'https://repo/branch');
      await tester.pump();

      expect(controller.text, 'https://repo/branch');
      controller.dispose();
    });
  });

  group('ConfigDialog 历史记录下拉选择', () {
    testWidgets('源 URL 历史菜单可选择，并复用 URL 空白净化规则', (tester) async {
      final sourceController = TextEditingController();
      final targetController = TextEditingController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigDialog(
            sourceUrlController: sourceController,
            targetWcController: targetController,
            sourceUrlHistory: const [
              ' https://repo.example.com/svn/branches/feature\n',
            ],
            targetWcHistory: const [],
            onConfirm: () {},
          ),
        ),
      ));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(' https://repo.example.com/svn/branches/feature\n'),
      );
      await tester.pumpAndSettle();

      expect(
        sourceController.text,
        'https://repo.example.com/svn/branches/feature',
      );

      sourceController.dispose();
      targetController.dispose();
    });

    testWidgets('目标工作副本历史菜单可选择，并保留路径中的合法空格', (tester) async {
      final sourceController = TextEditingController();
      final targetController = TextEditingController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigDialog(
            sourceUrlController: sourceController,
            targetWcController: targetController,
            sourceUrlHistory: const [],
            targetWcHistory: const [
              '/Users/name/Working Copies/project branch',
            ],
            onConfirm: () {},
          ),
        ),
      ));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('/Users/name/Working Copies/project branch'));
      await tester.pumpAndSettle();

      expect(
        targetController.text,
        '/Users/name/Working Copies/project branch',
      );

      sourceController.dispose();
      targetController.dispose();
    });
  });
}
