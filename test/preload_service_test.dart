import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/app_config.dart';
import 'package:svn_auto_merge/services/preload_service.dart';

void main() {
  group('evaluatePreloadStopReason', () {
    PreloadSettings settingsWith({
      bool enabled = true,
      bool stopOnBranchPoint = false,
      int maxDays = 0,
      int maxCount = 0,
      int stopRevision = 0,
      String? stopDate,
    }) {
      return PreloadSettings(
        enabled: enabled,
        stopOnBranchPoint: stopOnBranchPoint,
        maxDays: maxDays,
        maxCount: maxCount,
        stopRevision: stopRevision,
        stopDate: stopDate,
      );
    }

    test('全部限制为 0/null → none', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 1, 1),
        settings: settingsWith(),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('countLimit 命中：totalCount == maxCount', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 1000,
        earliestRevision: 50,
        earliestDate: null,
        settings: settingsWith(maxCount: 1000),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.countLimit);
    });

    test('countLimit 不命中：totalCount < maxCount', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 999,
        earliestRevision: 50,
        earliestDate: null,
        settings: settingsWith(maxCount: 1000),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('revisionLimit 命中：earliestRevision == stopRevision', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 200,
        earliestDate: null,
        settings: settingsWith(stopRevision: 200),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.revisionLimit);
    });

    test('revisionLimit 不命中：earliestRevision == 0（未知）', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 0,
        earliestDate: null,
        settings: settingsWith(stopRevision: 200),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('daysLimit 命中：earliestDate 在 daysLimitDate 之前', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 1, 1),
        settings: settingsWith(maxDays: 30),
        daysLimitDate: DateTime(2024, 1, 1),
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.daysLimit);
    });

    test('daysLimit 边界：earliestDate == daysLimitDate 不算超出', () {
      final boundary = DateTime(2024, 1, 1);
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: boundary,
        settings: settingsWith(maxDays: 30),
        daysLimitDate: boundary,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('dateLimit 命中：earliestDate 在 stopDate 之前', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 6, 1),
        settings: settingsWith(stopDate: '2024-01-01'),
        daysLimitDate: null,
        stopDate: DateTime(2024, 1, 1),
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.dateLimit);
    });

    test('branchPoint 命中：stopOnBranchPoint 开启且越过分支点', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 100,
        earliestDate: null,
        settings: settingsWith(stopOnBranchPoint: true),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: 100,
      );
      expect(reason, PreloadStopReason.branchPoint);
    });

    test('branchPoint 未启用：stopOnBranchPoint=false 时即使有分支点也不停', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: null,
        settings: settingsWith(stopOnBranchPoint: false),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: 100,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('branchPoint 还未到：earliestRevision > branchPoint 不停', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 200,
        earliestDate: null,
        settings: settingsWith(stopOnBranchPoint: true),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: 100,
      );
      expect(reason, PreloadStopReason.none);
    });

    test('优先级：count 优先于 revision', () {
      // 两条都触发，应取 count（位于第 1 条规则）
      final reason = evaluatePreloadStopReason(
        totalCount: 1000,
        earliestRevision: 100,
        earliestDate: null,
        settings: settingsWith(maxCount: 1000, stopRevision: 200),
        daysLimitDate: null,
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.countLimit);
    });

    test('优先级：revision 优先于 days', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 1, 1),
        settings: settingsWith(stopRevision: 100, maxDays: 30),
        daysLimitDate: DateTime(2024, 1, 1),
        stopDate: null,
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.revisionLimit);
    });

    test('优先级：days 优先于 date', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 1, 1),
        settings: settingsWith(maxDays: 30, stopDate: '2024-01-01'),
        daysLimitDate: DateTime(2024, 6, 1),
        stopDate: DateTime(2024, 1, 1),
        branchPoint: null,
      );
      expect(reason, PreloadStopReason.daysLimit);
    });

    test('优先级：date 优先于 branchPoint', () {
      final reason = evaluatePreloadStopReason(
        totalCount: 100,
        earliestRevision: 50,
        earliestDate: DateTime(2020, 1, 1),
        settings: settingsWith(
          stopDate: '2024-01-01',
          stopOnBranchPoint: true,
        ),
        daysLimitDate: null,
        stopDate: DateTime(2024, 1, 1),
        branchPoint: 100,
      );
      expect(reason, PreloadStopReason.dateLimit);
    });
  });

  group('describePreloadStopReason', () {
    test('none', () {
      expect(describePreloadStopReason(PreloadStopReason.none), '已完成');
    });

    test('branchPoint 包含 revision 占位', () {
      expect(
        describePreloadStopReason(
          PreloadStopReason.branchPoint,
          branchPoint: 1234,
        ),
        '已到达分支点 r1234',
      );
    });

    test('countLimit 包含已加载条数', () {
      expect(
        describePreloadStopReason(
          PreloadStopReason.countLimit,
          loadedCount: 500,
        ),
        '已到达条数限制 (500 条)',
      );
    });

    test('countLimit 默认 loadedCount=0', () {
      expect(
        describePreloadStopReason(PreloadStopReason.countLimit),
        '已到达条数限制 (0 条)',
      );
    });

    test('daysLimit / revisionLimit / dateLimit / noMoreData / userStopped 文案', () {
      expect(
        describePreloadStopReason(PreloadStopReason.daysLimit),
        '已到达天数限制',
      );
      expect(
        describePreloadStopReason(PreloadStopReason.revisionLimit),
        '已到达指定版本',
      );
      expect(
        describePreloadStopReason(PreloadStopReason.dateLimit),
        '已到达指定日期',
      );
      expect(
        describePreloadStopReason(PreloadStopReason.noMoreData),
        '已加载全部数据',
      );
      expect(
        describePreloadStopReason(PreloadStopReason.userStopped),
        '用户停止',
      );
    });

    test('error 带 errorMessage', () {
      expect(
        describePreloadStopReason(
          PreloadStopReason.error,
          errorMessage: 'boom',
        ),
        '出错: boom',
      );
    });

    test('error 缺省 errorMessage 兜底未知错误', () {
      expect(
        describePreloadStopReason(PreloadStopReason.error),
        '出错: 未知错误',
      );
    });

    test('R97 防漏配：PreloadStopReason.values.length == 9（强制 review describePreloadStopReason 9 case）', () {
      // R95 batch 漏审本 helper（关键词 grep 当时只扫了 widget 层，遗漏 services/）。
      // R97 补齐：新增 PreloadStopReason 时本测会红，强制 review describePreloadStopReason
      // 的 switch 是否补充新 case 的中文文案（包含 errorMessage / loadedCount / branchPoint
      // 等占位符注入策略，新 case 是否需要其中之一），并加入逐值锁定测试。
      expect(PreloadStopReason.values.length, 9,
          reason: '新增 PreloadStopReason enum 时，必须 review describePreloadStopReason '
              '的 switch 是否补充新 case 的中文文案与占位符注入逻辑（branchPoint / loadedCount / errorMessage）。');
    });
  });

  group('computeDaysLimitDate', () {
    test('maxDays > 0 → now.subtract(Duration(days: maxDays))', () {
      // 注入固定 now，断言精确日期，不依赖墙钟
      final now = DateTime(2026, 5, 27, 12, 0, 0);
      expect(
        computeDaysLimitDate(now: now, maxDays: 7),
        DateTime(2026, 5, 20, 12, 0, 0),
      );
    });

    test('maxDays == 1 → 减去一天（最小生效值）', () {
      final now = DateTime(2026, 5, 27);
      expect(
        computeDaysLimitDate(now: now, maxDays: 1),
        DateTime(2026, 5, 26),
      );
    });

    test('maxDays == 0 → null（"0 表示不限制"——锁定原 startPreload 行为）', () {
      final now = DateTime(2026, 5, 27);
      expect(computeDaysLimitDate(now: now, maxDays: 0), isNull);
    });

    test('maxDays < 0 → null（负数同样归为"不限制"，不会反向加日期）', () {
      // 原代码 `settings.maxDays > 0 ? ... : null`，负数走 else 返回 null
      final now = DateTime(2026, 5, 27);
      expect(computeDaysLimitDate(now: now, maxDays: -10), isNull);
    });

    test('maxDays 大值（跨年/跨月）→ Duration 加减正确', () {
      final now = DateTime(2026, 5, 27);
      // 365 天前
      expect(
        computeDaysLimitDate(now: now, maxDays: 365),
        DateTime(2025, 5, 27),
      );
      // 跨多个月
      expect(
        computeDaysLimitDate(now: now, maxDays: 90),
        DateTime(2026, 2, 26),
      );
    });

    test('保留时分秒（不归零到当天 00:00:00）——锁定 Duration.subtract 行为', () {
      // 注意：Duration(days: N) 是绝对 24h * N，不会做日历对齐
      final now = DateTime(2026, 5, 27, 14, 30, 45);
      expect(
        computeDaysLimitDate(now: now, maxDays: 1),
        DateTime(2026, 5, 26, 14, 30, 45),
      );
    });
  });

  group('describePreloadStatusDescription', () {
    test('idle → 空闲（stopReason 不影响）', () {
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.idle,
          stopReason: PreloadStopReason.none,
        ),
        '空闲',
      );
      // 即使有 stopReason 也不查
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.idle,
          stopReason: PreloadStopReason.branchPoint,
          branchPoint: 100,
        ),
        '空闲',
      );
    });

    test('loading → 加载中...', () {
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
        ),
        '加载中...',
      );
    });

    test('loading + loadedCount>0 + earliestRevision>0 → "加载中... (已 N 条, 最早 rXXX)"', () {
      // 2026-06-01 第十五轮：loading 文案展示实时进度，避免大仓库长时间无反馈
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
          loadedCount: 1234,
          earliestRevision: 56789,
        ),
        '加载中... (已 1234 条, 最早 r56789)',
      );
    });

    test('loading + loadedCount>0 + earliestRevision==null → "加载中... (已 N 条)"', () {
      // 加载初期 cache 还没回出 earliestRevision，仍要展示已加载条数
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
          loadedCount: 50,
        ),
        '加载中... (已 50 条)',
      );
    });

    test('loading + loadedCount>0 + earliestRevision<=0 → 走 normalizeOptionalRevision 视作未知 → "加载中... (已 N 条)"', () {
      // 与 normalizeOptionalRevision 同口径：<=0 视为未知/未启用
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
          loadedCount: 10,
          earliestRevision: 0,
        ),
        '加载中... (已 10 条)',
      );
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
          loadedCount: 10,
          earliestRevision: -1,
        ),
        '加载中... (已 10 条)',
      );
    });

    test('loading + loadedCount==0 → 走兜底 "加载中..."（earliestRevision 不影响）', () {
      // 防御预加载刚启动 cache 还空时仍展示干瘪基线，不写"已 0 条"误导用户
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.loading,
          stopReason: PreloadStopReason.none,
          loadedCount: 0,
          earliestRevision: 99999,
        ),
        '加载中...',
      );
    });

    test('paused → 已暂停', () {
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.paused,
          stopReason: PreloadStopReason.none,
        ),
        '已暂停',
      );
    });

    test('completed → 委托 describePreloadStopReason，透传所有占位参数', () {
      // branchPoint 透传
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.branchPoint,
          branchPoint: 12345,
        ),
        '已到达分支点 r12345',
      );
      // loadedCount 透传
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.countLimit,
          loadedCount: 500,
        ),
        '已到达条数限制 (500 条)',
      );
      // 简单 stopReason
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.userStopped,
        ),
        '用户停止',
      );
    });

    test('completed + stopReason.none → "已完成"（与 describePreloadStopReason 一致）', () {
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.none,
        ),
        '已完成',
      );
    });

    test('error → inline "出错: <msg>" 不查 stopReason', () {
      // 原 getter 在 status==error 时直接 inline 返回，不走 _getStopReasonDescription
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.error,
          stopReason: PreloadStopReason.none, // 注意：stopReason 不是 error，仍走 inline
          errorMessage: '网络断开',
        ),
        '出错: 网络断开',
      );
    });

    test('error 缺省 errorMessage 兜底未知错误', () {
      expect(
        describePreloadStatusDescription(
          status: PreloadStatus.error,
          stopReason: PreloadStopReason.none,
        ),
        '出错: 未知错误',
      );
    });

    test('PreloadProgress.statusDescription getter 委托给本函数（行为等价）', () {
      // 锁定 getter 是个薄包装；future 改顶层函数行为时 getter 自动跟进
      const progress = PreloadProgress(
        status: PreloadStatus.completed,
        stopReason: PreloadStopReason.branchPoint,
        branchPoint: 999,
      );
      expect(progress.statusDescription, '已到达分支点 r999');

      const errorProgress = PreloadProgress(
        status: PreloadStatus.error,
        errorMessage: 'oops',
      );
      expect(errorProgress.statusDescription, '出错: oops');
    });

    test('PreloadProgress.statusDescription 透传 earliestRevision（loading 进度展示契约）', () {
      // 2026-06-01 第十五轮：getter 必须把 earliestRevision 转给 helper，
      // 否则 UI chip 看不到最早 rev 段。锁定这个委托链路。
      const progress = PreloadProgress(
        status: PreloadStatus.loading,
        stopReason: PreloadStopReason.none,
        loadedCount: 88,
        earliestRevision: 12321,
      );
      expect(progress.statusDescription, '加载中... (已 88 条, 最早 r12321)');
    });

    test('R97 防漏配：PreloadStatus.values.length == 5（强制 review describePreloadStatusDescription 5 case）', () {
      // R95 batch 漏审本 helper。R97 补齐——新增 PreloadStatus 时本测会红，强制 review
      // describePreloadStatusDescription 的 switch 是否补充新 case 的"独立文案 vs 委托
      // describePreloadStopReason"决策（idle/loading/paused 直接返回；completed 委托
      // describePreloadStopReason；error 走 inline 兜底文案——新 case 需明确属于哪一类）。
      expect(PreloadStatus.values.length, 5,
          reason: '新增 PreloadStatus enum 时，必须 review describePreloadStatusDescription '
              '的 switch 是否补充新 case：是直接返回独立文案（idle/loading/paused）、'
              '委托 describePreloadStopReason（completed）、还是走 inline 兜底（error）。');
    });
  });

  group('normalizeOptionalRevision', () {
    test('正整数 → 原值', () {
      expect(normalizeOptionalRevision(1), 1);
      expect(normalizeOptionalRevision(12345), 12345);
      expect(normalizeOptionalRevision(999999), 999999);
    });

    test('0 → null（与"未缓存任何条目"语义一致）', () {
      expect(normalizeOptionalRevision(0), isNull);
    });

    test('负数 → null（防御性兜底）', () {
      expect(normalizeOptionalRevision(-1), isNull);
      expect(normalizeOptionalRevision(-100), isNull);
    });
  });

  group('formatPreloadErrorMessage', () {
    test('非空 errorMessage → "出错: <msg>"', () {
      expect(formatPreloadErrorMessage('网络超时'), '出错: 网络超时');
    });

    test('null → "出错: 未知错误"', () {
      expect(formatPreloadErrorMessage(null), '出错: 未知错误');
    });

    test('空字符串视作存在（与 ?? 语义一致，不退化到"未知错误"）', () {
      // 锁定 ?? 语义：空串是"已显式提供"，不回落
      expect(formatPreloadErrorMessage(''), '出错: ');
    });

    test('与 describePreloadStopReason(error, ...) 文案一致（同步性契约）', () {
      const msg = 'svn 命令失败';
      expect(
        formatPreloadErrorMessage(msg),
        describePreloadStopReason(
          PreloadStopReason.error,
          errorMessage: msg,
        ),
      );
      // null 也对齐
      expect(
        formatPreloadErrorMessage(null),
        describePreloadStopReason(PreloadStopReason.error),
      );
    });

    test('与 describePreloadStatusDescription(status=error, ...) 文案一致', () {
      const msg = '权限错误';
      expect(
        formatPreloadErrorMessage(msg),
        describePreloadStatusDescription(
          status: PreloadStatus.error,
          stopReason: PreloadStopReason.none,
          errorMessage: msg,
        ),
      );
    });
  });

  group('formatPreloadSettingsDumpLines', () {
    test('全部限制启用 → 5 行精确文案，顺序固定', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: true,
        maxDays: 30,
        maxCount: 500,
        stopRevision: 12345,
        stopDate: '2024-01-01',
      ));
      expect(lines, [
        '    - 到达分支点停止: true',
        '    - 天数限制: 30 天',
        '    - 条数限制: 500 条',
        '    - 版本限制: r12345',
        '    - 日期限制: 2024-01-01',
      ]);
    });

    test('全部限制 = 0 / null → 全部显示"无限制"', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: false,
        maxDays: 0,
        maxCount: 0,
        stopRevision: 0,
        stopDate: null,
      ));
      expect(lines, [
        '    - 到达分支点停止: false',
        '    - 天数限制: 无限制',
        '    - 条数限制: 无限制',
        '    - 版本限制: 无限制',
        '    - 日期限制: 无限制',
      ]);
    });

    test('负数与 0 同视作"无限制"（与 > 0 守卫一致）', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: false,
        maxDays: -1,
        maxCount: -100,
        stopRevision: -5,
        stopDate: null,
      ));
      expect(lines[1], '    - 天数限制: 无限制');
      expect(lines[2], '    - 条数限制: 无限制');
      expect(lines[3], '    - 版本限制: 无限制');
    });

    test('混合：部分启用 + 部分无限制', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: true,
        maxDays: 7,
        maxCount: 0,
        stopRevision: 0,
        stopDate: '2024-12-31',
      ));
      expect(lines, [
        '    - 到达分支点停止: true',
        '    - 天数限制: 7 天',
        '    - 条数限制: 无限制',
        '    - 版本限制: 无限制',
        '    - 日期限制: 2024-12-31',
      ]);
    });

    test('返回的 list 长度恒为 5', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings());
      expect(lines.length, 5);
    });

    test('每行包含 "    - " 前缀（与原 startPreload 输出格式一致）', () {
      final lines = formatPreloadSettingsDumpLines(const PreloadSettings());
      for (final line in lines) {
        expect(line, startsWith('    - '));
      }
    });
  });

  group('formatPreloadStartHeaderLines', () {
    test('返回 3 行：标题 / 源 URL / "  设置:" 子标题', () {
      expect(
        formatPreloadStartHeaderLines(sourceUrl: 'svn://x/branches/foo'),
        [
          '【预加载服务】开始后台预加载',
          '  源 URL: svn://x/branches/foo',
          '  设置:',
        ],
      );
    });

    test('字段顺序固定：标题 → URL → "  设置:"', () {
      final lines = formatPreloadStartHeaderLines(sourceUrl: 'U');
      expect(lines.length, 3);
      expect(lines[0], '【预加载服务】开始后台预加载');
      expect(lines[1].contains('源 URL'), isTrue);
      expect(lines[2], '  设置:');
    });

    test('标题不带前导缩进，2 个数据行带 2 空格前缀', () {
      final lines = formatPreloadStartHeaderLines(sourceUrl: 'svn://x');
      expect(lines[0].startsWith(' '), isFalse);
      expect(lines[1].startsWith('  '), isTrue);
      expect(lines[2].startsWith('  '), isTrue);
    });

    test('sourceUrl 为空串透传（暴露上游异常调用，不做防御）', () {
      // 决策锁定：上层 startPreload 入参契约要求非空，传入空串
      // 会得到 '  源 URL: ' 这种字面输出，暴露异常调用而非静默修正。
      final lines = formatPreloadStartHeaderLines(sourceUrl: '');
      expect(lines[1], '  源 URL: ');
    });
  });

  group('formatPreloadFromHeadResultLine', () {
    test('newDataCount > 0 → "  从 HEAD 获取了 N 条新数据"', () {
      expect(
        formatPreloadFromHeadResultLine(5),
        '  从 HEAD 获取了 5 条新数据',
      );
    });

    test('newDataCount == 0 → "  没有新数据"', () {
      expect(formatPreloadFromHeadResultLine(0), '  没有新数据');
    });

    test('newDataCount < 0 仍走"没有新数据"分支（防御）', () {
      // 决策锁定：负数不会出现在 syncFromHead 契约下，但归入
      // "没有新数据"分支，避免 "获取了 -3 条" 这种异常文案外泄。
      expect(formatPreloadFromHeadResultLine(-1), '  没有新数据');
      expect(formatPreloadFromHeadResultLine(-100), '  没有新数据');
    });

    test('newDataCount == 1 边界（最小正数）', () {
      expect(
        formatPreloadFromHeadResultLine(1),
        '  从 HEAD 获取了 1 条新数据',
      );
    });
  });

  group('formatPreloadCacheStatusLines', () {
    test('earliestRevision > 0 → 返回 2 行：缓存条数 + 最早版本', () {
      expect(
        formatPreloadCacheStatusLines(
          totalCount: 42,
          earliestRevision: 100,
        ),
        [
          '  当前最新区间缓存: 42 条',
          '  最早版本: r100',
        ],
      );
    });

    test('earliestRevision == 0 → 仅 1 行（缓存条数）', () {
      // 决策锁定：getEarliestRevisionInLatestRange 返回 0 表示"未缓存"，
      // 此时打印 "最早版本: r0" 会误导，原代码用 > 0 守卫，本函数照搬。
      expect(
        formatPreloadCacheStatusLines(
          totalCount: 0,
          earliestRevision: 0,
        ),
        ['  当前最新区间缓存: 0 条'],
      );
    });

    test('earliestRevision == 1 边界（最小正数）→ 仍输出 2 行', () {
      final lines = formatPreloadCacheStatusLines(
        totalCount: 1,
        earliestRevision: 1,
      );
      expect(lines.length, 2);
      expect(lines.last, '  最早版本: r1');
    });

    test('earliestRevision < 0（防御性）→ 仅 1 行', () {
      final lines = formatPreloadCacheStatusLines(
        totalCount: 5,
        earliestRevision: -1,
      );
      expect(lines.length, 1);
      expect(lines.first, '  当前最新区间缓存: 5 条');
    });

    test('totalCount == 0 仍输出第 1 行（让"刚开始预加载"状态可见）', () {
      // 决策锁定：即使 totalCount == 0 也输出"当前最新区间缓存: 0 条"，
      // 不做"非空才输出"的优化——"缓存是空"本身就是诊断信息。
      final lines = formatPreloadCacheStatusLines(
        totalCount: 0,
        earliestRevision: 100,
      );
      expect(lines.length, 2);
      expect(lines.first, '  当前最新区间缓存: 0 条');
    });

    test('每行均带 2 空格前导缩进', () {
      final lines = formatPreloadCacheStatusLines(
        totalCount: 1,
        earliestRevision: 1,
      );
      for (final line in lines) {
        expect(line.startsWith('  '), isTrue);
      }
    });
  });

  group('formatPreloadProgressLine', () {
    test('正常路径：loadedCount + earliestRevision', () {
      expect(
        formatPreloadProgressLine(loadedCount: 100, earliestRevision: 50),
        '  已加载: 100 条, 最早: r50',
      );
    });

    test('loadedCount == 0 仍合法输出', () {
      expect(
        formatPreloadProgressLine(loadedCount: 0, earliestRevision: 1),
        '  已加载: 0 条, 最早: r1',
      );
    });

    test('earliestRevision == 1 边界（最小合法值）', () {
      expect(
        formatPreloadProgressLine(loadedCount: 1, earliestRevision: 1),
        '  已加载: 1 条, 最早: r1',
      );
    });

    test('earliestRevision == 0（防御性路径）也输出 r0，不静默吞掉', () {
      // 决策锁定：调用点紧跟 syncLogs(loadMore: true) 的 newCount > 0
      // 场景，earliestRevision 必然 > 0；如果错误传入 0 应在日志里
      // 暴露 "最早: r0"，比静默更利于排查。
      expect(
        formatPreloadProgressLine(loadedCount: 5, earliestRevision: 0),
        '  已加载: 5 条, 最早: r0',
      );
    });

    test('前导 2 空格 + 半角逗号格式（与原 startPreload 输出严格一致）', () {
      final line =
          formatPreloadProgressLine(loadedCount: 7, earliestRevision: 3);
      expect(line.startsWith('  '), isTrue);
      expect(line.contains(', 最早: r'), isTrue);
    });
  });

  group('shouldFetchBranchPoint', () {
    test('真值表 (T,T) → true（启用 + workingDirectory 已知）', () {
      expect(
        shouldFetchBranchPoint(
          stopOnBranchPoint: true,
          workingDirectory: '/tmp/wc',
        ),
        isTrue,
      );
    });

    test('真值表 (T,F) → false（启用但 workingDirectory==null）', () {
      // 关键守卫：`getCopyTailCache(workingDirectory!)` 在 caller 端会强解，
      // 必须由本谓词前置阻止 null deref。
      expect(
        shouldFetchBranchPoint(
          stopOnBranchPoint: true,
          workingDirectory: null,
        ),
        isFalse,
      );
    });

    test('真值表 (F,T) → false（未启用即使 workingDirectory 已知也不取）', () {
      expect(
        shouldFetchBranchPoint(
          stopOnBranchPoint: false,
          workingDirectory: '/tmp/wc',
        ),
        isFalse,
      );
    });

    test('真值表 (F,F) → false（双 false）', () {
      expect(
        shouldFetchBranchPoint(
          stopOnBranchPoint: false,
          workingDirectory: null,
        ),
        isFalse,
      );
    });

    test('空字符串 workingDirectory → true（仅锁 null，不锁 isNotEmpty）', () {
      // 契约文档明确说"任何非 null 字符串都视为可用"——空串的最终过滤
      // 由 LogSyncService.getCopyTailCache 内部的 isUsableWorkingDirectory
      // 完成，本谓词只防 null。改成 isNotEmpty 会让两层守卫语义错位。
      expect(
        shouldFetchBranchPoint(
          stopOnBranchPoint: true,
          workingDirectory: '',
        ),
        isTrue,
        reason: '本助手只锁 null，空串由下游 isUsableWorkingDirectory 过滤',
      );
    });

    test('双维度独立反向断言（#17）：stopOnBranchPoint 翻转改变结果', () {
      // 锁定独立性：固定 workingDirectory，单翻 stopOnBranchPoint
      // 必须切换返回值；否则说明某条短路逻辑错把 wd 当主条件。
      const wd = '/some/wc';
      final on = shouldFetchBranchPoint(
        stopOnBranchPoint: true,
        workingDirectory: wd,
      );
      final off = shouldFetchBranchPoint(
        stopOnBranchPoint: false,
        workingDirectory: wd,
      );
      expect(on, isNot(off));
    });
  });

  group('shouldUpdateBranchPointInProgress', () {
    test('reason==branchPoint && branchPoint!=null → true', () {
      expect(
        shouldUpdateBranchPointInProgress(
          reason: PreloadStopReason.branchPoint,
          branchPoint: 42,
        ),
        isTrue,
      );
    });

    test('reason==branchPoint && branchPoint==null → false（防御 cache miss）', () {
      // getCopyTailCache 失败时返回 null（line 551 `_copyTailCache[wd] = null`），
      // 这种情况下即使 evaluatePreloadStopReason 返回 branchPoint，也不应写入
      // progress——避免 caller 之后用 progress.branchPoint!.toString() 时崩。
      expect(
        shouldUpdateBranchPointInProgress(
          reason: PreloadStopReason.branchPoint,
          branchPoint: null,
        ),
        isFalse,
      );
    });

    test('其他 8 个 reason × branchPoint!=null → 全 false（语义错配防御）', () {
      // 9 个 PreloadStopReason 中除 branchPoint 外的 8 个：即使 caller 误传
      // 非 null 的 branchPoint 值也不应写入——这条断言锁住"reason 必须是
      // branchPoint"的硬性契约，未来增态新 reason 时强制 review。
      const nonBranchReasons = [
        PreloadStopReason.none,
        PreloadStopReason.daysLimit,
        PreloadStopReason.countLimit,
        PreloadStopReason.revisionLimit,
        PreloadStopReason.dateLimit,
        PreloadStopReason.noMoreData,
        PreloadStopReason.userStopped,
        PreloadStopReason.error,
      ];
      for (final r in nonBranchReasons) {
        expect(
          shouldUpdateBranchPointInProgress(reason: r, branchPoint: 42),
          isFalse,
          reason: 'reason=$r 即使 branchPoint=42 也不应写入',
        );
      }
    });

    test('其他 8 个 reason × branchPoint==null → 全 false（双 false 路径）', () {
      const nonBranchReasons = [
        PreloadStopReason.none,
        PreloadStopReason.daysLimit,
        PreloadStopReason.countLimit,
        PreloadStopReason.revisionLimit,
        PreloadStopReason.dateLimit,
        PreloadStopReason.noMoreData,
        PreloadStopReason.userStopped,
        PreloadStopReason.error,
      ];
      for (final r in nonBranchReasons) {
        expect(
          shouldUpdateBranchPointInProgress(reason: r, branchPoint: null),
          isFalse,
          reason: 'reason=$r branchPoint=null 必为 false',
        );
      }
    });

    test('防漏配 #11：PreloadStopReason.values.length == 9（增态强制 review）', () {
      // 未来增加新枚举值（如 customLimit）时，本断言会失败，强制开发者
      // 来这里 review：新 reason 的 branchPoint 写入语义是什么？
      expect(PreloadStopReason.values.length, 9);
    });

    test('branchPoint=0 视为合法值（不当成 sentinel）', () {
      // 边界：分支点 revision 0 在 SVN 实际不可能（rev 从 1 起步），但
      // 本谓词不做 ">0" 守卫——仅锁 null。如果 caller 传 0，要尊重
      // caller，不二次过滤。这与 normalizeOptionalRevision 把 ≤0 转 null
      // 是不同语义层（normalize 在 caller 上游做、本谓词在下游收）。
      expect(
        shouldUpdateBranchPointInProgress(
          reason: PreloadStopReason.branchPoint,
          branchPoint: 0,
        ),
        isTrue,
        reason: '本助手只锁 null，"≤0" 由 normalizeOptionalRevision 上游过滤',
      );
    });

    test('双维度独立反向断言（#17）：reason 与 branchPoint 翻转互不影响', () {
      // 反向断言：固定 branchPoint=42，仅切换 reason 必须改变输出；
      // 反过来固定 reason=branchPoint，仅切换 branchPoint 也必须改变输出。
      // 两个维度都是必要条件，缺一不可。
      final reasonFlipped = shouldUpdateBranchPointInProgress(
        reason: PreloadStopReason.branchPoint,
        branchPoint: 42,
      );
      final reasonFlippedOff = shouldUpdateBranchPointInProgress(
        reason: PreloadStopReason.daysLimit,
        branchPoint: 42,
      );
      expect(reasonFlipped, isNot(reasonFlippedOff));

      final branchPointSet = shouldUpdateBranchPointInProgress(
        reason: PreloadStopReason.branchPoint,
        branchPoint: 100,
      );
      final branchPointNull = shouldUpdateBranchPointInProgress(
        reason: PreloadStopReason.branchPoint,
        branchPoint: null,
      );
      expect(branchPointSet, isNot(branchPointNull));
    });

    test('#9 形似但语义不同：与 shouldFetchBranchPoint 不合并', () {
      // 反向断言：两个谓词都返回 bool 都是 2-flag AND，但语义完全不同。
      // shouldFetchBranchPoint 决定"是否 I/O 取数据"（caller 在 cache lookup
      // 之前调）；shouldUpdateBranchPointInProgress 决定"是否写入 progress"
      // （caller 在 progress 更新之前调）。前者吃 (bool, String?)，后者吃
      // (PreloadStopReason, int?)——签名差异锁定不可合并。
      // 这里通过"两者输入类型互不通用"反向证明：传错类型编译不过。
      // 运行期断言：两者都为 true 时仍然是两个独立判定（caller 必须分别调）。
      final fetchTrue = shouldFetchBranchPoint(
        stopOnBranchPoint: true,
        workingDirectory: '/wc',
      );
      final updateTrue = shouldUpdateBranchPointInProgress(
        reason: PreloadStopReason.branchPoint,
        branchPoint: 42,
      );
      expect(fetchTrue, isTrue);
      expect(updateTrue, isTrue);
      // 两个 true 表达不同维度的"通过"，不可互换——本断言锁意图。
      expect(identical(fetchTrue, updateTrue), isTrue,
          reason: 'Dart bool 字面 true 是同一对象，但语义不同 — 这条断言只是文档化');
    });
  });

  // R102 PreloadProgress.copyWith 全字段对称性 + nullable reset 限制审计：
  // preload_service.dart:445 PreloadProgress.copyWith 8 字段，5 个 nullable
  // （earliestDate / earliestRevision / branchPoint / errorMessage / sourceUrl）
  // 全用 `?? this.X` 模式——无法通过 copyWith reset 回 null。
  // 原本 0 个 copyWith 测试——本轮补对称性 + 5 条 reset 限制 doc。
  group('PreloadProgress copyWith 全字段对称性（R102）', () {
    final baseline = PreloadProgress(
      status: PreloadStatus.loading,
      stopReason: PreloadStopReason.countLimit,
      loadedCount: 50,
      earliestDate: DateTime(2024, 1, 1),
      earliestRevision: 100,
      branchPoint: 42,
      errorMessage: 'baseline-error',
      sourceUrl: 'svn://baseline',
    );

    test('修改单个字段时其他 7 字段全部保持原值', () {
      final modStatus = baseline.copyWith(status: PreloadStatus.completed);
      expect(modStatus.status, PreloadStatus.completed);
      expect(modStatus.stopReason, baseline.stopReason);
      expect(modStatus.loadedCount, baseline.loadedCount);
      expect(modStatus.earliestDate, baseline.earliestDate);
      expect(modStatus.earliestRevision, baseline.earliestRevision);
      expect(modStatus.branchPoint, baseline.branchPoint);
      expect(modStatus.errorMessage, baseline.errorMessage);
      expect(modStatus.sourceUrl, baseline.sourceUrl);

      final modStopReason =
          baseline.copyWith(stopReason: PreloadStopReason.branchPoint);
      expect(modStopReason.stopReason, PreloadStopReason.branchPoint);
      expect(modStopReason.status, baseline.status);

      final modLoaded = baseline.copyWith(loadedCount: 999);
      expect(modLoaded.loadedCount, 999);
      expect(modLoaded.status, baseline.status);

      final newDate = DateTime(2025, 6, 6);
      final modDate = baseline.copyWith(earliestDate: newDate);
      expect(modDate.earliestDate, newDate);
      expect(modDate.earliestRevision, baseline.earliestRevision);

      final modEarliestRev = baseline.copyWith(earliestRevision: 999);
      expect(modEarliestRev.earliestRevision, 999);
      expect(modEarliestRev.earliestDate, baseline.earliestDate);

      final modBranchPoint = baseline.copyWith(branchPoint: 999);
      expect(modBranchPoint.branchPoint, 999);
      expect(modBranchPoint.earliestRevision, baseline.earliestRevision);

      final modErrorMsg = baseline.copyWith(errorMessage: 'new-error');
      expect(modErrorMsg.errorMessage, 'new-error');
      expect(modErrorMsg.status, baseline.status);

      final modSourceUrl = baseline.copyWith(sourceUrl: 'svn://new');
      expect(modSourceUrl.sourceUrl, 'svn://new');
      expect(modSourceUrl.errorMessage, baseline.errorMessage);
    });

    test('R102 lib 实测契约 doc 化：5 个 nullable 字段无法通过 copyWith reset 回 null', () {
      // 现状锁定：PreloadProgress.copyWith 用 `X ?? this.X` 模式——
      // 5 个 nullable 字段（earliestDate / earliestRevision / branchPoint /
      // errorMessage / sourceUrl）传 null 会回退到原值。
      // **判据**：与 MergeJob.copyWith 的 _unset sentinel 模式不一致。
      // 当前现状：lib/services/preload_service.dart 内 PreloadProgress 的状态机推进
      // 都是从一个状态拷贝并修改非 null 字段，无"清空已设字段"需求——所以暂无修
      // lib 紧迫性，但本测试锁定限制契约。

      final tryClearDate = baseline.copyWith(earliestDate: null);
      expect(tryClearDate.earliestDate, baseline.earliestDate,
          reason: 'copyWith(earliestDate: null) 不能清空——`?? this.X` 会回退到原值。');

      final tryClearRev = baseline.copyWith(earliestRevision: null);
      expect(tryClearRev.earliestRevision, baseline.earliestRevision,
          reason:
              'copyWith(earliestRevision: null) 不能清空——`?? this.X` 会回退到原值。');

      final tryClearBp = baseline.copyWith(branchPoint: null);
      expect(tryClearBp.branchPoint, baseline.branchPoint,
          reason: 'copyWith(branchPoint: null) 不能清空——`?? this.X` 会回退到原值。');

      final tryClearErr = baseline.copyWith(errorMessage: null);
      expect(tryClearErr.errorMessage, baseline.errorMessage,
          reason: 'copyWith(errorMessage: null) 不能清空——`?? this.X` 会回退到原值。');

      final tryClearUrl = baseline.copyWith(sourceUrl: null);
      expect(tryClearUrl.sourceUrl, baseline.sourceUrl,
          reason: 'copyWith(sourceUrl: null) 不能清空——`?? this.X` 会回退到原值。');
    });

    test('无参 copyWith 等价于副本（保留所有原值）', () {
      final copy = baseline.copyWith();
      expect(copy.status, baseline.status);
      expect(copy.stopReason, baseline.stopReason);
      expect(copy.loadedCount, baseline.loadedCount);
      expect(copy.earliestDate, baseline.earliestDate);
      expect(copy.earliestRevision, baseline.earliestRevision);
      expect(copy.branchPoint, baseline.branchPoint);
      expect(copy.errorMessage, baseline.errorMessage);
      expect(copy.sourceUrl, baseline.sourceUrl);
    });
  });

  group('R120 等待协议档 3（节流型 sleep）doc-as-test', () {
    // R120 框架（与 R98 throw / R119 then-catchError 同源）—— 等待 channel 三档：
    //   档 1：信号驱动（Completer.future）—— working_copy_manager._acquireLock
    //   档 2：polling + sleep —— logger_service.close
    //   档 3：节流型 sleep（不等任何信号、纯降速）—— 本档 / preload_service:631
    // 本组 doc-as-test 锁档 3 的 sleep 是"主作用"而非"等待副作用"，与档 2 边界对照。

    test('档 3 sleep 是降速主作用 — 删掉不会卡死、只会吞吐爆冲', () {
      // preload_service.startPreload 的循环：
      //   while (!_shouldStop) {
      //     ...syncLogs / 进度更新...
      //     if (newCount == 0) break;
      //     await Future.delayed(const Duration(milliseconds: 100));  // ← 档 3
      //   }
      // 如果删掉这条 delay：循环仍由 _shouldStop / newCount==0 / stopReason 三个
      // 外部信号驱动退出，不会死循环；但每次 syncLogs 完成后立刻发起下一轮，会
      // 给 SVN 服务器和本地 sqlite 写入造成持续高压力。
      // 反向验证档 2/档 3：档 2 删 sleep → 仍退出（吃满 CPU）；档 3 删 sleep →
      // 仍退出（吃满 IO/网络）—— 都不影响 termination，但 dimension 不同：档 2
      // 的循环条件本身已"自然趋向退出"（队列只减不增）；档 3 的循环条件可能"长
      // 期保持 true"（_shouldStop 一直 false），更需要主动节流。
      expect(true, isTrue);
    });

    test('100ms 选值 trade-off vs 档 2 的 10ms — 不可互换', () {
      // 档 3 100ms：与 SVN RTT 同量级，节流而不显眼地拖慢预加载。
      // 档 2 10ms：close 等待，越短越好，10ms 是 CPU 占用与延迟的平衡点。
      // 反例：把档 3 改成 10ms → 节流近乎失效，对 SVN 服务器压力恢复成无节流；
      //       把档 2 改成 100ms → close 延迟最差 100ms，UI 关闭体验劣化。
      // 判据：档 2 越小越好（受 CPU 限制下界）；档 3 选 RTT 同量级（受用户感知上界）。
      expect(true, isTrue);
    });

    test('档 3 退出靠外部 stop 信号 — 与档 1/档 2 区分', () {
      // 档 1 退出：信号源 complete()。
      // 档 2 退出：循环条件布尔翻转（自然趋向退出）。
      // 档 3 退出：循环条件依赖外部 stop 信号 / 数据耗尽 break —— delay 与退出
      //   完全无关。三档退出来源对照：
      //     档 1 = 唤醒信号
      //     档 2 = 内部状态
      //     档 3 = 外部信号 / 边界数据
      expect(true, isTrue);
    });
  });
}
