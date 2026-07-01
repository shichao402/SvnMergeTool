import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/merge_config.dart';
import 'package:svn_auto_merge/screens/components/config_bar.dart';

void main() {
  group('extractBranchDisplayName', () {
    test('完整 SVN URL → 末两段', () {
      expect(
        extractBranchDisplayName('svn://example.com/repo/branches/v1'),
        'branches/v1',
      );
    });

    test('恰好两段 → 两段都返回', () {
      expect(extractBranchDisplayName('a/b'), 'a/b');
    });

    test('单段（无 /）→ 原样返回', () {
      expect(extractBranchDisplayName('trunk'), 'trunk');
    });

    test('空串 → 原样返回（split 后只有 1 个空段）', () {
      expect(extractBranchDisplayName(''), '');
    });

    test('尾部带 / → 末两段中第二段为空（现状锁定）', () {
      // 'a/b/' split 后 = ['a', 'b', '']，末两段是 ['b', '']，join 后 'b/'。
      // 这是现状——本函数不去除尾部 /，与下面的 extractFolderDisplayName 不同。
      expect(extractBranchDisplayName('a/b/'), 'b/');
    });

    test('包含连续 // → 不过滤空段（与 main_screen_v3 的 summarizeSourceUrl 行为不同）', () {
      // 'svn://host/x' split 后 = ['svn:', '', 'host', 'x']，末两段 ['host', 'x']，join 'host/x'。
      // summarizeSourceUrl 会过滤空段，本函数不会——两者故意保持现状。
      expect(extractBranchDisplayName('svn://host/x'), 'host/x');
    });

    test('深层路径 → 仍只取末两段', () {
      expect(
        extractBranchDisplayName('svn://h/a/b/c/d/e/f'),
        'e/f',
      );
    });
  });

  group('extractFolderDisplayName', () {
    test('Unix 风格路径 → 取最后一段', () {
      expect(extractFolderDisplayName('/Users/test/project/wc'), 'wc');
    });

    test('Windows 风格路径（反斜杠）→ 反斜杠归一为正斜杠', () {
      expect(extractFolderDisplayName(r'C:\projects\wc'), 'wc');
    });

    test('混合斜杠 → 都归一', () {
      expect(extractFolderDisplayName(r'C:\projects/sub\wc'), 'wc');
    });

    test('单段路径 → 原样返回', () {
      expect(extractFolderDisplayName('wc'), 'wc');
    });

    test('单个尾随斜杠 → 去掉再取最后一段', () {
      expect(extractFolderDisplayName('/a/b/'), 'b');
    });

    test('多个尾随斜杠 → 全部去掉再取最后一段', () {
      expect(extractFolderDisplayName('/a/b///'), 'b');
    });

    test('反斜杠尾随 → 同样去掉', () {
      expect(extractFolderDisplayName(r'C:\projects\wc\'), 'wc');
    });

    test('空串 → 空串', () {
      // split('') 返回 [''], parts.last 是 ''
      expect(extractFolderDisplayName(''), '');
    });

    test('只有斜杠 → 全部去掉后变空串，split 仍返回 [""]，结果是 ""', () {
      // '////' → normalize 后 '' → split 返回 ['']
      expect(extractFolderDisplayName('////'), '');
    });

    test('深层路径 → 仍只取最后一段', () {
      expect(extractFolderDisplayName('/a/b/c/d/e'), 'e');
    });
  });

  group('formatConfigBarSourceLabel', () {
    test('空串 → 占位 "未设置"', () {
      expect(formatConfigBarSourceLabel(''), kConfigBarUnsetPlaceholder);
      expect(formatConfigBarSourceLabel(''), '未设置');
    });

    test('正常 URL → 委托 extractBranchDisplayName 截末两段', () {
      expect(
        formatConfigBarSourceLabel('svn://host/repo/branches/v1'),
        'branches/v1',
      );
    });

    test('单段 URL → 原样返回（不 trim，与 extractBranchDisplayName 边界一致）', () {
      expect(formatConfigBarSourceLabel('trunk'), 'trunk');
    });

    test('全空白字符串 → 视为非空，走 extract 路径（不 trim）', () {
      // 锁定"isEmpty 而非 isEmpty || trim().isEmpty"——和 extractBranchDisplayName
      // 的"原样返回（不 trim）"边界对齐。caller（_buildSelectPhaseView）已经在调用前
      // 用 controller.text.trim() 处理过空白，无需在这层重复 trim。
      expect(formatConfigBarSourceLabel('   '), '   ');
    });
  });

  group('formatConfigBarTargetLabel', () {
    test('空串 → 占位 "未设置"', () {
      expect(formatConfigBarTargetLabel(''), kConfigBarUnsetPlaceholder);
      expect(formatConfigBarTargetLabel(''), '未设置');
    });

    test('Unix 路径 → 委托 extractFolderDisplayName 截尾段', () {
      expect(formatConfigBarTargetLabel('/Users/test/proj/wc'), 'wc');
    });

    test('Windows 反斜杠路径 → 同样能取出 wc', () {
      expect(formatConfigBarTargetLabel(r'C:\projects\wc'), 'wc');
    });

    test('单段路径 → 原样返回（extractFolderDisplayName 行为）', () {
      expect(formatConfigBarTargetLabel('wc'), 'wc');
    });

    test('全空白字符串 → 视为非空（不 trim），走 extract 路径', () {
      // 同 source label，caller 负责 trim
      expect(formatConfigBarTargetLabel('   '), '   ');
    });
  });

  group('formatConfigBarEffectiveTargetLabel', () {
    test('非精简模式 → 展示目标工作副本文件夹名', () {
      expect(
        formatConfigBarEffectiveTargetLabel(
          targetConfig:
              const TargetConfig.fullWorkingCopy('/Users/test/proj/wc'),
        ),
        'wc',
      );
    });

    test('精简模式目标 URL 非空 → 展示目标分支名，不展示工作副本路径', () {
      expect(
        formatConfigBarEffectiveTargetLabel(
          targetConfig: const TargetConfig.sparseTemporary(
            'svn://host/repo/branches/target',
          ),
        ),
        'branches/target',
      );
    });

    test('精简模式目标 URL 为空 → 未设置', () {
      expect(
        formatConfigBarEffectiveTargetLabel(
          targetConfig: const TargetConfig.sparseTemporary(''),
        ),
        '未设置',
      );
    });
  });

  group('kConfigBarUnsetPlaceholder', () {
    test('占位文案是 "未设置"——锁定字面值，UI 改文案时单点更新', () {
      // 这个测试故意比较字面值——避免有人把常量改成别的值后忘了同步 UI 文档/截图，
      // 单测会"硬碰硬"地提醒这是一处面向用户的 UI 字符串决策。
      expect(kConfigBarUnsetPlaceholder, '未设置');
    });

    test('source 与 target 共享同一占位常量（identical）', () {
      // 锁住"两个 label 的 empty 兜底必须共享同一字符串"——防止有人改回硬编码导致漂移
      expect(
        identical(
          formatConfigBarSourceLabel(''),
          formatConfigBarTargetLabel(''),
        ),
        isTrue,
      );
    });
  });

  group('formatConfigBarSourceTooltip（Step 22 - 第十八层 hover）', () {
    // 这一组测试锁定 ConfigBar"源"字段 hover tooltip 的核心契约：
    // 1) 真正裁切（label 是 url 末两段，url 完整）→ 返回完整 url
    // 2) label 字面等于 url 本身 → 返回 ''（dedup，避免重复气泡）
    // 3) trim 边界（caller 已上层 trim，本函数双保险）

    test('完整 SVN URL（label 是末两段，url 是完整长串）→ 返回完整 url', () {
      // 'svn://example.com/repo/branches/v1' label='branches/v1' → 完整 url 必须能展开
      const url = 'svn://example.com/repo/branches/v1';
      expect(formatConfigBarSourceTooltip(url), url);
    });

    test('单段 URL（label 与 url 字面相等）→ "" dedup 不挂 tooltip', () {
      // 'trunk' → label 也是 'trunk'，重复展示是噪音
      expect(formatConfigBarSourceTooltip('trunk'), '');
    });

    test('恰好两段 URL（"a/b" label 也是 "a/b"）→ "" dedup', () {
      // 'a/b' → extractBranchDisplayName 取末两段还是 'a/b'，字面相等
      expect(formatConfigBarSourceTooltip('a/b'), '');
    });

    test('空串 → "" 不挂 tooltip', () {
      expect(formatConfigBarSourceTooltip(''), '');
    });

    test('全空白 → trim 后为空 → "" 不挂 tooltip', () {
      expect(formatConfigBarSourceTooltip('   '), '');
    });

    test('外围带空白的 URL → trim 后返回干净 url（双保险）', () {
      // caller 已经在上层 trim 过——本测试锁定边界双保险，避免 caller 漏 trim 时挂奇怪空白 tooltip
      expect(
        formatConfigBarSourceTooltip('  svn://h/r/b/v1  '),
        'svn://h/r/b/v1',
      );
    });

    test('深层路径（label 末两段，url 完整）→ 返回完整 url', () {
      const url = 'svn://h/a/b/c/d/e/f';
      // label='e/f'，完整 url 展开必须能看到 a/b/c/d
      expect(formatConfigBarSourceTooltip(url), url);
    });
  });

  group('formatConfigBarTargetTooltip（Step 22 - 第十八层 hover）', () {
    test('完整 Unix 路径（label 是 wc，path 是完整）→ 返回完整 path', () {
      const path = '/Users/test/projects/main/wc';
      expect(formatConfigBarTargetTooltip(path), path);
    });

    test('完整 Windows 路径（label 是 wc，path 是 C:\\...）→ 返回完整 path', () {
      const path = r'C:\dev\projects\main\wc';
      // 注意：trim 不影响反斜杠，path 原样返回（不做斜杠归一——那是 label 层的事）
      expect(formatConfigBarTargetTooltip(path), path);
    });

    test('单段路径（"wc" label 也是 "wc"）→ "" dedup 不挂 tooltip', () {
      expect(formatConfigBarTargetTooltip('wc'), '');
    });

    test('空串 → "" 不挂 tooltip', () {
      expect(formatConfigBarTargetTooltip(''), '');
    });

    test('全空白 → trim 后为空 → "" 不挂 tooltip', () {
      expect(formatConfigBarTargetTooltip('   '), '');
    });

    test('外围带空白的路径 → trim 后返回干净 path（双保险）', () {
      expect(
        formatConfigBarTargetTooltip('  /Users/x/wc  '),
        '/Users/x/wc',
      );
    });

    test('尾随斜杠路径（label 去尾斜杠取尾段，path 保留斜杠）→ 返回完整 path', () {
      // label='b'（extractFolderDisplayName 去尾随）、tooltip 是 '/a/b/'（trim 后），字面不等 → 返回完整
      const path = '/a/b/';
      expect(formatConfigBarTargetTooltip(path), path);
    });
  });

  group('formatConfigBarEffectiveTargetTooltip', () {
    test('精简模式 tooltip 展示目标 URL 和自动临时工作副本文案', () {
      final tooltip = formatConfigBarEffectiveTargetTooltip(
        targetConfig: const TargetConfig.sparseTemporary(
          'svn://host/repo/branches/target',
        ),
      );

      expect(tooltip, contains('svn://host/repo/branches/target'));
      expect(tooltip, contains('将自动创建临时工作副本'));
      expect(tooltip, contains('系统临时目录'));
    });

    test('精简模式未设置目标 URL → tooltip 仍提示自动创建临时工作副本', () {
      expect(
        formatConfigBarEffectiveTargetTooltip(
          targetConfig: const TargetConfig.sparseTemporary(''),
        ),
        '将自动创建临时工作副本',
      );
    });
  });

  group('shouldShowSvnOperationMenu', () {
    test('两 flag 都满足 → true', () {
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: true,
          targetConfig: const TargetConfig.fullWorkingCopy('/some/wc'),
        ),
        isTrue,
      );
    });

    test('hasCallback == false → false（caller 没注入回调时静默隐藏）', () {
      // 灰显但点击无响应 → 静默隐藏，避免"按钮可见但无反应"的可避免噪音。
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: false,
          targetConfig: const TargetConfig.fullWorkingCopy('/some/wc'),
        ),
        isFalse,
      );
    });

    test('targetWc.isEmpty → false（路径为空时菜单跑不出有效命令）', () {
      // SVN 操作都需要工作副本路径——空路径时静默隐藏，避免"点了菜单 → 跑命令 → 报错弹窗"。
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: true,
          targetConfig: const TargetConfig.fullWorkingCopy(''),
        ),
        isFalse,
      );
    });

    test('两 flag 都不满足 → false', () {
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: false,
          targetConfig: const TargetConfig.fullWorkingCopy(''),
        ),
        isFalse,
      );
    });

    test('targetWc 仅空白 → true（不在本函数 trim，与 formatConfigBarTargetLabel 边界一致）',
        () {
      // 本函数刻意不 trim——caller 想 trim 由 caller 决定；这是有意契约（与
      // `formatConfigBarTargetLabel` 的"不 trim"对齐）。
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: true,
          targetConfig: const TargetConfig.fullWorkingCopy('   '),
        ),
        isTrue,
      );
    });

    test('精简模式隐藏完整工作副本操作菜单', () {
      expect(
        shouldShowSvnOperationMenu(
          hasCallback: true,
          targetConfig: const TargetConfig.sparseTemporary(
            'svn://host/repo/branches/target',
          ),
        ),
        isFalse,
      );
    });
  });

  group('SvnOperationMenuItemSpec', () {
    test('值相等性（operation + icon + title + subtitle + 两个可选色）', () {
      const a = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.download,
        title: '更新',
        subtitle: '更新工作副本到最新版本',
      );
      const b = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.download,
        title: '更新',
        subtitle: '更新工作副本到最新版本',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('operation 不同 → 不等', () {
      const a = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.download,
        title: '更新',
        subtitle: 's',
      );
      const b = SvnOperationMenuItemSpec(
        operation: SvnOperation.cleanup,
        icon: Icons.download,
        title: '更新',
        subtitle: 's',
      );
      expect(a, isNot(equals(b)));
    });

    test('titleColor 一侧 null 一侧非 null → 不等（按 toARGB32 比较）', () {
      const a = SvnOperationMenuItemSpec(
        operation: SvnOperation.revert,
        icon: Icons.undo,
        title: '还原',
        subtitle: 's',
      );
      const b = SvnOperationMenuItemSpec(
        operation: SvnOperation.revert,
        icon: Icons.undo,
        title: '还原',
        subtitle: 's',
        titleColor: Colors.orange,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString 含 operation 与 title（便于日志排查）', () {
      const spec = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.download,
        title: '更新',
        subtitle: 's',
      );
      expect(spec.toString(), contains('SvnOperation.update'));
      expect(spec.toString(), contains('更新'));
    });
  });

  group('svnOperationMenuSpecs', () {
    test('菜单项数量 == SvnOperation.values.length（防止新增 enum 时漏配菜单）', () {
      // 这条测试是"未来防御"——如果给 SvnOperation 加了第 4 个值，但忘了在 specs
      // 里添加对应菜单项，本测试立刻红，提醒 spec 与 enum 必须同步演进。
      expect(svnOperationMenuSpecs().length, SvnOperation.values.length);
    });

    test('顺序固定：update → switchBranch → revert → cleanup', () {
      // PopupMenu 直接 map 列表到 PopupMenuItem——顺序变更就是视觉变更，必须锁定。
      final ops = svnOperationMenuSpecs().map((s) => s.operation).toList();
      expect(ops, [
        SvnOperation.update,
        SvnOperation.switchBranch,
        SvnOperation.revert,
        SvnOperation.cleanup,
      ]);
    });

    test('文案锁定（title + subtitle，与原 inline 完全一致）', () {
      final specs = svnOperationMenuSpecs();
      expect(specs[0].title, '更新');
      expect(specs[0].subtitle, '更新工作副本到最新版本');
      expect(specs[1].title, '切换');
      expect(specs[1].subtitle, '切换目标工作副本到其他分支');
      expect(specs[2].title, '还原');
      expect(specs[2].subtitle, '撤销所有本地修改');
      expect(specs[3].title, '清理');
      expect(specs[3].subtitle, '清理工作副本');
    });

    test('图标锁定（download / swap_horiz / undo / cleaning_services）', () {
      final specs = svnOperationMenuSpecs();
      expect(specs[0].icon, Icons.download);
      expect(specs[1].icon, Icons.swap_horiz);
      expect(specs[2].icon, Icons.undo);
      expect(specs[3].icon, Icons.cleaning_services);
    });

    test('破坏性操作（revert）唯一带 Colors.orange 前景色，其它项 null', () {
      // 这是核心配色契约——"只有 revert 用橙色"标记破坏性。未来加新破坏性操作时，
      // 这条测试会红（因为新项没配色），提醒补色。
      final specs = svnOperationMenuSpecs();
      expect(specs[0].titleColor, isNull);
      expect(specs[0].iconColor, isNull);
      expect(specs[1].titleColor, isNull);
      expect(specs[1].iconColor, isNull);
      expect(
        specs[2].titleColor?.toARGB32(),
        Colors.orange.toARGB32(),
      );
      expect(
        specs[2].iconColor?.toARGB32(),
        Colors.orange.toARGB32(),
      );
      expect(specs[3].titleColor, isNull);
      expect(specs[3].iconColor, isNull);
    });

    test('每项 operation 字段与 SvnOperation enum 一一对应（无重复、无遗漏）', () {
      final ops = svnOperationMenuSpecs().map((s) => s.operation).toSet();
      expect(ops, SvnOperation.values.toSet());
    });

    test('多次调用返回内容相等的实例（const 列表，可比相等）', () {
      // 实现用 `return const [...]`——每次调用返回同一份 const 字面量。
      // 测试锁定"内容稳定"，避免有人改成 `<SvnOperationMenuItemSpec>[...]`（非 const）
      // 后单点 spec 比较失败而不易察觉。
      final a = svnOperationMenuSpecs();
      final b = svnOperationMenuSpecs();
      expect(a, equals(b));
      expect(a[0], equals(b[0]));
    });
  });

  group('SvnOperationMenuItemSpec == / hashCode 对称性（R103）', () {
    // baseline 用所有 6 字段非默认值，避免与 default null 退化无法区分
    const baseline = SvnOperationMenuItemSpec(
      operation: SvnOperation.update,
      icon: Icons.refresh,
      title: 'T',
      subtitle: 'S',
      titleColor: Color(0xFFAA0000),
      iconColor: Color(0xFF00BB00),
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00BB00),
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（6 字段对称性矩阵）', () {
      // 改一个字段就一定 !=——锁住"任何字段都参与 ==，无字段被遗漏"
      const diffOperation = SvnOperationMenuItemSpec(
        operation: SvnOperation.revert,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00BB00),
      );
      const diffIcon = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.delete,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00BB00),
      );
      const diffTitle = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T2',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00BB00),
      );
      const diffSubtitle = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S2',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00BB00),
      );
      const diffTitleColor = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFBB0000),
        iconColor: Color(0xFF00BB00),
      );
      const diffIconColor = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
        iconColor: Color(0xFF00CC00),
      );
      for (final variant in [
        diffOperation,
        diffIcon,
        diffTitle,
        diffSubtitle,
        diffTitleColor,
        diffIconColor,
      ]) {
        expect(variant, isNot(equals(baseline)));
      }
      // Set 去重：1 个 baseline + 6 个 variant = 7 个互不相等
      final s = <SvnOperationMenuItemSpec>{
        baseline,
        diffOperation,
        diffIcon,
        diffTitle,
        diffSubtitle,
        diffTitleColor,
        diffIconColor,
      };
      expect(s.length, 7, reason: '6 字段对称性矩阵：每改一个字段都应产生独立 Set 元素');
    });

    test('nullable Color 字段 null vs 非 null 不相等', () {
      // 锁定 ?.toARGB32() 链路对 null 的处理（null != 任何非 null Color）
      const withNull = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
      );
      const withColor = SvnOperationMenuItemSpec(
        operation: SvnOperation.update,
        icon: Icons.refresh,
        title: 'T',
        subtitle: 'S',
        titleColor: Color(0xFFAA0000),
      );
      expect(withNull, isNot(equals(withColor)));
    });
  });

  group('ConfigBar 源/目标点击入口拆分', () {
    testWidgets('点击源字段只触发 onSourceTap', (tester) async {
      var sourceTapCount = 0;
      var targetTapCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigBar(
            sourceUrl: 'svn://host/repo/branches/v1',
            targetConfig: const TargetConfig.fullWorkingCopy('/Users/me/wc'),
            onSourceTap: () => sourceTapCount++,
            onTargetTap: () => targetTapCount++,
            onSettingsTap: () {},
          ),
        ),
      ));

      await tester.tap(find.text('branches/v1'));
      await tester.pump();

      expect(sourceTapCount, 1);
      expect(targetTapCount, 0);
    });

    testWidgets('点击目标字段只触发 onTargetTap', (tester) async {
      var sourceTapCount = 0;
      var targetTapCount = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigBar(
            sourceUrl: 'svn://host/repo/branches/v1',
            targetConfig: const TargetConfig.fullWorkingCopy('/Users/me/wc'),
            onSourceTap: () => sourceTapCount++,
            onTargetTap: () => targetTapCount++,
            onSettingsTap: () {},
          ),
        ),
      ));

      await tester.tap(find.text('wc'));
      await tester.pump();

      expect(sourceTapCount, 0);
      expect(targetTapCount, 1);
    });
  });

  group('ConfigBar 精简模式展示', () {
    testWidgets('精简模式显示目标 URL 与自动临时工作副本提示，不显示 SVN 操作菜单', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigBar(
            sourceUrl: 'svn://host/repo/branches/source',
            targetConfig: const TargetConfig.sparseTemporary(
              'svn://host/repo/branches/target',
            ),
            onSourceTap: () {},
            onTargetTap: () {},
            onSettingsTap: () {},
            onSvnOperation: (_) {},
            onTemporarySparseWorkingCopyChanged: (_) {},
          ),
        ),
      ));

      expect(find.textContaining('目标 URL'), findsOneWidget);
      expect(find.text('branches/target'), findsOneWidget);
      expect(find.textContaining('将自动创建临时工作副本'), findsOneWidget);
      expect(find.byType(PopupMenuButton<SvnOperation>), findsNothing);
    });
  });
}
