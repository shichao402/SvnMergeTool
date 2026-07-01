import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svn_auto_merge/models/app_config.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/storage_service.dart';

void main() {
  group('normalizeMruHistory', () {
    test('空 list → 空 list', () {
      expect(normalizeMruHistory([], maxLength: 20), isEmpty);
    });

    test('无重复且未超长 → 原样返回（顺序保持）', () {
      final result = normalizeMruHistory(['a', 'b', 'c'], maxLength: 20);
      expect(result, ['a', 'b', 'c']);
    });

    test('有重复 → 保留首次出现的顺序（LinkedHashSet 语义）', () {
      // [a, b, a, c] 走 toSet().toList() 等于 [a, b, c]，不是 [a, c, b]
      final result = normalizeMruHistory(['a', 'b', 'a', 'c'], maxLength: 20);
      expect(result, ['a', 'b', 'c']);
    });

    test('超过 maxLength → 截断到前 maxLength 条', () {
      final input = List<String>.generate(25, (i) => 'item-$i');
      final result = normalizeMruHistory(input, maxLength: 20);
      expect(result.length, 20);
      expect(result.first, 'item-0');
      expect(result.last, 'item-19');
    });

    test('恰好 maxLength → 不截断', () {
      final input = List<String>.generate(20, (i) => 'i$i');
      final result = normalizeMruHistory(input, maxLength: 20);
      expect(result.length, 20);
    });

    test('不修改入参', () {
      final input = ['a', 'b', 'a'];
      final snapshot = List<String>.from(input);
      normalizeMruHistory(input, maxLength: 20);
      expect(input, snapshot);
    });

    test('maxLength <= 0 → 抛 ArgumentError', () {
      expect(() => normalizeMruHistory(['a'], maxLength: 0),
          throwsA(isA<ArgumentError>()));
      expect(() => normalizeMruHistory(['a'], maxLength: -1),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('promoteToMruFront', () {
    test('item 不在 history → 插到 index 0', () {
      final result = promoteToMruFront(['a', 'b'], 'c', maxLength: 20);
      expect(result, ['c', 'a', 'b']);
    });

    test('item 已在 history → 移动到 index 0', () {
      final result = promoteToMruFront(['a', 'b', 'c'], 'b', maxLength: 20);
      expect(result, ['b', 'a', 'c']);
    });

    test('item 已在第一位 → 仍是第一位（顺序保持）', () {
      final result = promoteToMruFront(['a', 'b', 'c'], 'a', maxLength: 20);
      expect(result, ['a', 'b', 'c']);
    });

    test('history 含 item 的多个副本（防御）→ 全部移除后插入一次', () {
      final result =
          promoteToMruFront(['a', 'b', 'a', 'c', 'a'], 'a', maxLength: 20);
      expect(result, ['a', 'b', 'c']);
    });

    test('插入后超过 maxLength → 截断', () {
      // 已有 5 条，maxLength=5，插入新 item 应挤掉最后一条
      final result = promoteToMruFront(
        ['a', 'b', 'c', 'd', 'e'],
        'NEW',
        maxLength: 5,
      );
      expect(result, ['NEW', 'a', 'b', 'c', 'd']);
    });

    test('插入已存在元素 + 截断 → 长度不会大于 maxLength', () {
      final result = promoteToMruFront(
        ['a', 'b', 'c', 'd', 'e'],
        'd',
        maxLength: 5,
      );
      expect(result, ['d', 'a', 'b', 'c', 'e']);
      expect(result.length, 5);
    });

    test('空 history + 插入 → 单元素 list', () {
      final result = promoteToMruFront([], 'x', maxLength: 5);
      expect(result, ['x']);
    });

    test('item 是空字符串也会插入（trim 守卫由调用方负责）', () {
      // 这是契约：纯函数不做语义校验
      final result = promoteToMruFront(['a'], '', maxLength: 5);
      expect(result, ['', 'a']);
    });

    test('不修改入参', () {
      final input = ['a', 'b', 'c'];
      final snapshot = List<String>.from(input);
      promoteToMruFront(input, 'b', maxLength: 5);
      expect(input, snapshot);
    });

    test('maxLength <= 0 → 抛 ArgumentError', () {
      expect(() => promoteToMruFront([], 'x', maxLength: 0),
          throwsA(isA<ArgumentError>()));
    });

    group('R124 mutator 二档判据 doc-as-test（档 1 + 档 2 共存于同函数）', () {
      // R124：promoteToMruFront 内部同时含两类 mutator
      //   - while(next.remove(item))：档 2（element 由谓词等值匹配决定）
      //   - next.insert(0, item)：档 1（index ≡ 0 常量字面量）
      // 这是 R124 二档判据**首次发现"同函数共存"形态**——
      // R123 logger / merge_execution_state / log_cache 三处都是单档独立站点，
      // promoteToMruFront 把两档交错使用。重构时不能"统一"两类 mutator，必须
      // 各按各档处理（remove(item) 档 2 不能改 Set，insert(0) 档 1 不能改成
      // append 后 sort）。

      test('档 2 反证：remove(item) 不依赖位置语义但依赖 List 顺序', () {
        // 给重复输入，验证 while-loop 移除"全部匹配项"——这是档 2 的关键行为
        // （Set.remove 一次性移除唯一实例、List.remove 只移除第一个）。
        final result = promoteToMruFront(
          ['a', 'b', 'a', 'c', 'a'],
          'a',
          maxLength: 10,
        );
        // 期望：所有 'a' 被移除后插入头部一次
        expect(result.where((e) => e == 'a').length, 1,
            reason:
                '档 2 mutator 必须循环 remove 全部匹配项；改成 Set 后此语义会变成"唯一实例 + 一次性移除"');
        expect(result[0], 'a',
            reason:
                'insert(0, ...) 档 1 必须把 item 插到 head；改成 add(item) 会丢失 MRU 语义');
      });

      test('档 1 反证：insert(0, item) 是单次 O(n) 不会退化成 O(n²)', () {
        // R122 logger drain loop 在循环里反复 removeAt(0) 是 O(n²)；
        // promoteToMruFront 的 insert(0) 在循环外、只插一次 → O(n) 合法档 1。
        final result = promoteToMruFront(
          List<String>.generate(100, (i) => 'item$i'),
          'newItem',
          maxLength: 200,
        );
        expect(result.length, 101);
        expect(result[0], 'newItem');
      });

      test('R124 二档判据明文 doc-as-test（同函数两档独立性）', () {
        // 这条测试是**doc-as-test**——存在本身就是 R124 doc 的一部分：
        // 档 2 操作（while remove）与档 1 操作（insert 0）互不干涉地共存于
        // 同一函数。重构者若把 while-loop 改成 Set.remove + List.fromSet 会破
        // 坏 MRU 顺序；改 insert(0) 成 add 会破坏头部插入。两档独立检查。
        final input = ['x', 'y', 'x'];
        final result = promoteToMruFront(input, 'x', maxLength: 5);
        // 档 2 行为：所有 'x' 被移除（输入有 2 个）
        expect(result.where((e) => e == 'x').length, 1);
        // 档 1 行为：插入头部
        expect(result.first, 'x');
        // 不修改入参：档 1+2 都作用在 next（List.from copy）上
        expect(input, ['x', 'y', 'x']);
      });
    });
  });

  group('window bounds storage', () {
    test('windowBoundsToJson / parseWindowBoundsJson 可往返', () {
      const bounds = Rect.fromLTWH(12.5, -20, 1280, 720);
      final json = windowBoundsToJson(bounds);

      expect(json, {
        'left': 12.5,
        'top': -20.0,
        'width': 1280.0,
        'height': 720.0,
      });
      expect(parseWindowBoundsJson(jsonEncode(json)), bounds);
    });

    test('parseWindowBoundsJson 遇到坏数据 → null', () {
      expect(parseWindowBoundsJson(null), isNull);
      expect(parseWindowBoundsJson(''), isNull);
      expect(parseWindowBoundsJson('not-json'), isNull);
      expect(
        parseWindowBoundsJson(
          jsonEncode({
            'left': 10,
            'top': 10,
            'width': 0,
            'height': 720,
          }),
        ),
        isNull,
      );
    });

    test('StorageService 保存并读取 window_bounds 单一 JSON key', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();

      const bounds = Rect.fromLTWH(100, 120, 1280, 720);
      await StorageService().saveWindowBounds(bounds);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kWindowBoundsKey), isNotNull);
      expect(await StorageService().getWindowBounds(), bounds);
    });
  });

  group('recoverInterruptedJobs', () {
    // 构造小工厂：调整 status / completedIndex / resumeFromStepId 来触发
    // shouldRecoverAsInterrupted 的不同分支。
    MergeJob makeJob({
      required int jobId,
      required JobStatus status,
      int completedIndex = 0,
      String? resumeFromStepId,
    }) {
      return MergeJob(
        jobId: jobId,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 3,
        revisions: const [1, 2],
        status: status,
        completedIndex: completedIndex,
        resumeFromStepId: resumeFromStepId,
      );
    }

    test('空 list → (空 list, 0)', () {
      final r = recoverInterruptedJobs([]);
      expect(r.jobs, isEmpty);
      expect(r.recoveredCount, 0);
    });

    test('全部为 done/pending(无进度) → 不恢复，原样返回', () {
      final jobs = [
        makeJob(jobId: 1, status: JobStatus.done),
        makeJob(jobId: 2, status: JobStatus.pending),
        makeJob(jobId: 3, status: JobStatus.failed),
      ];
      final r = recoverInterruptedJobs(jobs);
      expect(r.recoveredCount, 0);
      expect(r.jobs.length, 3);
      // 未触发恢复的对象保持原引用
      expect(identical(r.jobs[0], jobs[0]), isTrue);
      expect(identical(r.jobs[1], jobs[1]), isTrue);
      expect(identical(r.jobs[2], jobs[2]), isTrue);
    });

    test('running 任务 → 恢复为 paused（计数 +1）', () {
      final jobs = [makeJob(jobId: 1, status: JobStatus.running)];
      final r = recoverInterruptedJobs(jobs);
      expect(r.recoveredCount, 1);
      expect(r.jobs[0].status, JobStatus.paused);
      // 恢复后是新对象（copyWith 产物）
      expect(identical(r.jobs[0], jobs[0]), isFalse);
    });

    test('pending 但 completedIndex > 0 → 视为中断，恢复', () {
      final jobs = [
        makeJob(jobId: 1, status: JobStatus.pending, completedIndex: 1),
      ];
      final r = recoverInterruptedJobs(jobs);
      expect(r.recoveredCount, 1);
      expect(r.jobs[0].status, JobStatus.paused);
    });

    test('pending + resumeFromStepId 非空 → 视为中断，恢复', () {
      final jobs = [
        makeJob(
          jobId: 1,
          status: JobStatus.pending,
          resumeFromStepId: 'commit',
        ),
      ];
      final r = recoverInterruptedJobs(jobs);
      expect(r.recoveredCount, 1);
      expect(r.jobs[0].status, JobStatus.paused);
      // recoverInterrupted 会把 resumeFromStepId 清掉
      expect(r.jobs[0].resumeFromStepId, isNull);
    });

    test('混合：仅对触发条件的任务恢复，顺序与计数都正确', () {
      final jobs = [
        makeJob(jobId: 1, status: JobStatus.done), // 不恢复
        makeJob(jobId: 2, status: JobStatus.running), // 恢复
        makeJob(jobId: 3, status: JobStatus.pending), // 不恢复（无进度）
        makeJob(
          jobId: 4,
          status: JobStatus.pending,
          completedIndex: 2,
        ), // 恢复
      ];
      final r = recoverInterruptedJobs(jobs);
      expect(r.recoveredCount, 2);
      expect(r.jobs.length, 4);
      // 顺序保持
      expect(r.jobs.map((j) => j.jobId).toList(), [1, 2, 3, 4]);
      expect(r.jobs[0].status, JobStatus.done);
      expect(r.jobs[1].status, JobStatus.paused);
      expect(r.jobs[2].status, JobStatus.pending);
      expect(r.jobs[3].status, JobStatus.paused);
    });

    test('返回新 list（不是同一引用）', () {
      final jobs = [makeJob(jobId: 1, status: JobStatus.done)];
      final r = recoverInterruptedJobs(jobs);
      expect(identical(r.jobs, jobs), isFalse);
    });
  });

  // 锁住 storage_service 的 preload 读路径与 PreloadSettings 序列化契约：
  // - getPreloadSettings() 返回的扁平 map 形状必须能被 PreloadSettings.fromJson 直接消费；
  // - getPreloadSettingsTyped() 内部就是这层组合，调用方不应再手工挑字段重建（之前
  //   main_screen_v3._loadPreloadSettings 漏了 stop_revision/stop_date 是真实 bug）。
  // 这里不依赖 SharedPreferences mock，直接锁映射本身。
  group('PreloadSettings.fromJson × getPreloadSettings 契约', () {
    /// 与 storage_service.dart::getPreloadSettings() 完全同形的默认 map。
    Map<String, dynamic> defaultStoredMap() => {
          'enabled': true,
          'stop_on_branch_point': true,
          'max_days': 90,
          'max_count': 1000,
          'stop_revision': 0,
          'stop_date': null,
        };

    test('默认 map → 与 const PreloadSettings() 等价', () {
      final s = PreloadSettings.fromJson(defaultStoredMap());
      expect(s.enabled, true);
      expect(s.stopOnBranchPoint, true);
      expect(s.maxDays, 90);
      expect(s.maxCount, 1000);
      expect(s.stopRevision, 0);
      expect(s.stopDate, isNull);
    });

    test('全字段非默认值 → 全字段保留（包括 stop_revision / stop_date）', () {
      final map = {
        'enabled': false,
        'stop_on_branch_point': false,
        'max_days': 30,
        'max_count': 500,
        'stop_revision': 12345,
        'stop_date': '2026-01-15',
      };
      final s = PreloadSettings.fromJson(map);
      expect(s.enabled, false);
      expect(s.stopOnBranchPoint, false);
      expect(s.maxDays, 30);
      expect(s.maxCount, 500);
      expect(s.stopRevision, 12345);
      expect(s.stopDate, '2026-01-15');
    });

    test('完全空 map → 全部走 PreloadSettings 默认值', () {
      final s = PreloadSettings.fromJson({});
      expect(s.enabled, true);
      expect(s.stopOnBranchPoint, true);
      expect(s.maxDays, 90);
      expect(s.maxCount, 1000);
      expect(s.stopRevision, 0);
      expect(s.stopDate, isNull);
    });

    test('缺 stop_revision/stop_date → 这两字段回落默认值，其它字段不受影响', () {
      // 模拟旧版本写入、新版本读取的兼容场景。
      final map = {
        'enabled': false,
        'stop_on_branch_point': false,
        'max_days': 7,
        'max_count': 50,
      };
      final s = PreloadSettings.fromJson(map);
      expect(s.enabled, false);
      expect(s.stopOnBranchPoint, false);
      expect(s.maxDays, 7);
      expect(s.maxCount, 50);
      expect(s.stopRevision, 0);
      expect(s.stopDate, isNull);
    });

    test('toJson → fromJson roundtrip 保持等价（写读两端共享契约）', () {
      const original = PreloadSettings(
        enabled: false,
        stopOnBranchPoint: false,
        maxDays: 14,
        maxCount: 200,
        stopRevision: 99999,
        stopDate: '2025-12-31',
      );
      final round = PreloadSettings.fromJson(original.toJson());
      expect(round.enabled, original.enabled);
      expect(round.stopOnBranchPoint, original.stopOnBranchPoint);
      expect(round.maxDays, original.maxDays);
      expect(round.maxCount, original.maxCount);
      expect(round.stopRevision, original.stopRevision);
      expect(round.stopDate, original.stopDate);
    });

    test(
        'getPreloadSettings() 默认 map 的 key 集合 == PreloadSettings.toJson 的 key 集合',
        () {
      // 这一条专门防回归：如果哪天 storage_service 默认 map 加了 key 但 PreloadSettings
      // 没跟上（或反过来），契约就破了，这里立刻挂掉。
      final storedKeys = defaultStoredMap().keys.toSet();
      final modelKeys = const PreloadSettings().toJson().keys.toSet();
      expect(storedKeys, modelKeys);
    });
  });

  group('defaultPreloadSettingsMap', () {
    test('包含全部 6 个键', () {
      final map = defaultPreloadSettingsMap();
      expect(
        map.keys.toSet(),
        {
          'enabled',
          'stop_on_branch_point',
          'max_days',
          'max_count',
          'stop_revision',
          'stop_date',
        },
      );
    });

    test('每个键的默认值精确锁定（与 UI 占位符 / getPreload* 兜底必须一致）', () {
      // 任意一个值漂移都会导致 UI 默认显示与"未保存设置"实际行为不一致
      final map = defaultPreloadSettingsMap();
      expect(map['enabled'], true);
      expect(map['stop_on_branch_point'], true);
      expect(map['max_days'], 90);
      expect(map['max_count'], 1000);
      expect(map['stop_revision'], 0);
      expect(map['stop_date'], isNull);
    });

    test('多次调用返回独立 map（一次修改不影响下次）', () {
      final a = defaultPreloadSettingsMap();
      a['max_days'] = 7;
      a['enabled'] = false;
      final b = defaultPreloadSettingsMap();
      expect(b['max_days'], 90);
      expect(b['enabled'], true);
      expect(identical(a, b), isFalse);
    });

    test('PreloadSettings.fromJson(default) 不抛错且字段对齐', () {
      // 锁定"读"侧 fromJson 与"写"侧默认 map 的契约对齐——
      // 如果 PreloadSettings 加了必填字段而默认 map 漏了，本测试会先红
      final settings = PreloadSettings.fromJson(defaultPreloadSettingsMap());
      expect(settings.enabled, true);
      expect(settings.stopOnBranchPoint, true);
      expect(settings.maxDays, 90);
      expect(settings.maxCount, 1000);
      expect(settings.stopRevision, 0);
      expect(settings.stopDate, isNull);
    });
  });

  group('buildPreloadWriteOps', () {
    test('空 settings → 空 ops list（部分更新语义：什么都没传就什么都不写）', () {
      expect(buildPreloadWriteOps(<String, dynamic>{}), isEmpty);
    });

    test('单 key enabled → 单条 setBool 指令', () {
      final ops = buildPreloadWriteOps(<String, dynamic>{'enabled': true});
      expect(ops, [
        const PreloadWriteOp(
          key: 'preload_enabled',
          kind: PreloadWriteOpKind.setBool,
          value: true,
        ),
      ]);
    });

    test('全部 6 个 key 都填 → 6 条指令，顺序固定', () {
      // 顺序契约：enabled / stop_on_branch_point / max_days / max_count /
      // stop_revision / stop_date —— 单测显式锁定，方便 review 对比 diff
      final ops = buildPreloadWriteOps(<String, dynamic>{
        'enabled': false,
        'stop_on_branch_point': false,
        'max_days': 30,
        'max_count': 500,
        'stop_revision': 12345,
        'stop_date': '2024-01-01',
      });
      expect(ops.map((o) => o.key).toList(), [
        'preload_enabled',
        'preload_stop_on_branch_point',
        'preload_max_days',
        'preload_max_count',
        'preload_stop_revision',
        'preload_stop_date',
      ]);
      expect(ops.map((o) => o.kind).toList(), [
        PreloadWriteOpKind.setBool,
        PreloadWriteOpKind.setBool,
        PreloadWriteOpKind.setInt,
        PreloadWriteOpKind.setInt,
        PreloadWriteOpKind.setInt,
        PreloadWriteOpKind.setString,
      ]);
      expect(ops.map((o) => o.value).toList(), [
        false,
        false,
        30,
        500,
        12345,
        '2024-01-01',
      ]);
    });

    test('stop_date 显式 null → removeKey 指令（SharedPreferences 不能存 null）', () {
      final ops = buildPreloadWriteOps(<String, dynamic>{'stop_date': null});
      expect(ops, [
        const PreloadWriteOp(
          key: 'preload_stop_date',
          kind: PreloadWriteOpKind.removeKey,
          value: null,
        ),
      ]);
    });

    test('stop_date 非 null → setString 指令', () {
      final ops = buildPreloadWriteOps(
        <String, dynamic>{'stop_date': '2024-12-31'},
      );
      expect(ops, [
        const PreloadWriteOp(
          key: 'preload_stop_date',
          kind: PreloadWriteOpKind.setString,
          value: '2024-12-31',
        ),
      ]);
    });

    test('多余 key 被静默忽略（与原 savePreloadSettings 6 段 containsKey 守卫一致）', () {
      final ops = buildPreloadWriteOps(<String, dynamic>{
        'enabled': true,
        'unknown_field': 'should be ignored',
        'another_unknown': 42,
      });
      expect(ops.length, 1);
      expect(ops.single.key, 'preload_enabled');
    });

    test('部分更新：只传 enabled + max_days 两个 key → 只生成 2 条指令', () {
      // 锁定"部分更新"语义：调用方只想改某几个 key，未传的 key 不会被影响
      final ops = buildPreloadWriteOps(<String, dynamic>{
        'enabled': true,
        'max_days': 60,
      });
      expect(ops.length, 2);
      expect(ops[0].key, 'preload_enabled');
      expect(ops[1].key, 'preload_max_days');
    });

    test('每个布尔 key 独立处理（enabled true / stop_on_branch_point false 同时存在）', () {
      final ops = buildPreloadWriteOps(<String, dynamic>{
        'stop_on_branch_point': false,
        'enabled': true,
      });
      // 顺序由函数内部决定，不是 settings 入参的迭代顺序
      expect(ops[0].key, 'preload_enabled');
      expect(ops[0].value, true);
      expect(ops[1].key, 'preload_stop_on_branch_point');
      expect(ops[1].value, false);
    });

    test('PreloadWriteOp 相等性（== / hashCode）', () {
      const a = PreloadWriteOp(
        key: 'k',
        kind: PreloadWriteOpKind.setInt,
        value: 1,
      );
      const b = PreloadWriteOp(
        key: 'k',
        kind: PreloadWriteOpKind.setInt,
        value: 1,
      );
      const c = PreloadWriteOp(
        key: 'k',
        kind: PreloadWriteOpKind.setInt,
        value: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('PreloadWriteOp.toString 形状', () {
      const op = PreloadWriteOp(
        key: 'preload_enabled',
        kind: PreloadWriteOpKind.setBool,
        value: true,
      );
      expect(op.toString(),
          'PreloadWriteOp(PreloadWriteOpKind.setBool, preload_enabled, true)');
    });
  });

  // ===========================================================================
  // R104：SharedPreferences key 持久化兼容性巡检
  //
  // 目的：把 StorageService 里散落的字符串字面量 key 锁死在测试里。任何重命名
  // / 拼写错误都会让用户已经持久化的数据在下次读取时静默丢失（getX 返回
  // null/[]，回退到默认值）。lib 端没有迁移层，一旦 key 漂移就回不来。
  //
  // 锁定方式：通过 setMockInitialValues 预置一个用 "已知 key" 写入的值，再用
  // public API 读取，断言公共 API 看见这个值。如果有人改 key、读侧就会拿到
  // 默认值，断言失败。同时反向断言：调用 setX → 读 raw _prefs 验证写入的
  // 是同一个 key 字面量。
  //
  // 不在本轮覆盖：
  // - LogCacheService._urlHashMapKey：init() 触碰文件系统，单测要 mock 路径
  //   服务，超出本轮范围。改用一条字符串字面量断言把常量值锁死。
  // - 队列文件里的 'jobs' JSON key：那是文件内 JSON 字段，不是 prefs key；
  //   见下方 R105 "队列文件 JSON schema 持久化" group 单独覆盖。
  //   （**R105 纠正**：R104 原 comment 声称 loadQueue/saveQueue 已有 round-trip
  //   集成测试覆盖，实际只测了 app_paths 的文件路径，JSON 处理本身没测——R105 补齐。）
  // ===========================================================================
  group('SharedPreferences key 持久化（R104）', () {
    setUpAll(() {
      // R104：StorageService 的 setX 会调用 AppLogger.storage.info()，后者
      // 异步写文件 → 触发 path_provider → 在纯单测环境下没有 Binding，
      // 写日志的 Future 会卡住 teardown。关掉文件日志即可。
      logger.enabled = false;
    });

    setUp(() async {
      // 每个测试前清空 mock 存储，并强制 StorageService 重新拿一次实例
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await StorageService().init();
    });

    test('source_url_history：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'source_url_history': <String>['svn://a', 'svn://b'],
      });
      await StorageService().init();
      expect(
          await StorageService().getSourceUrlHistory(), ['svn://a', 'svn://b']);
    });

    test('source_url_history：写 key 锁定', () async {
      await StorageService().saveSourceUrlHistory(['svn://x']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('source_url_history'), ['svn://x']);
    });

    test('switch_branch_history：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'switch_branch_history': <String>['svn://sw/a', 'svn://sw/b'],
      });
      await StorageService().init();
      expect(await StorageService().getSwitchBranchHistory(),
          ['svn://sw/a', 'svn://sw/b']);
    });

    test('switch_branch_history：写 key 锁定', () async {
      await StorageService().saveSwitchBranchHistory(['svn://sw/x']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('switch_branch_history'), ['svn://sw/x']);
    });

    test('target_url_history：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'target_url_history': <String>['svn://target/a', 'svn://target/b'],
      });
      await StorageService().init();
      expect(await StorageService().getTargetUrlHistory(),
          ['svn://target/a', 'svn://target/b']);
    });

    test('target_url_history：写 key 锁定', () async {
      await StorageService().saveTargetUrlHistory(['svn://target/x']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('target_url_history'), ['svn://target/x']);
      expect(prefs.getStringList('source_url_history'), isNull);
      expect(prefs.getStringList('switch_branch_history'), isNull);
    });

    test('target_wc_history：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'target_wc_history': <String>['/wc/a', '/wc/b'],
      });
      await StorageService().init();
      expect(await StorageService().getTargetWcHistory(), ['/wc/a', '/wc/b']);
    });

    test('target_wc_history：写 key 锁定', () async {
      await StorageService().saveTargetWcHistory(['/wc/x']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('target_wc_history'), ['/wc/x']);
    });

    test('last_source_url：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_source_url': 'svn://last',
      });
      await StorageService().init();
      expect(await StorageService().getLastSourceUrl(), 'svn://last');
    });

    test('last_source_url：写 key 锁定', () async {
      await StorageService().saveLastSourceUrl('svn://saved');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_source_url'), 'svn://saved');
    });

    test('last_target_wc：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_target_wc': '/wc/last',
      });
      await StorageService().init();
      expect(await StorageService().getLastTargetWc(), '/wc/last');
    });

    test('last_target_wc：写 key 锁定', () async {
      await StorageService().saveLastTargetWc('/wc/saved');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_target_wc'), '/wc/saved');
    });

    test('last_target_url：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_target_url': 'svn://target/last',
      });
      await StorageService().init();
      expect(await StorageService().getLastTargetUrl(), 'svn://target/last');
    });

    test('last_target_url：写 key 锁定', () async {
      await StorageService().saveLastTargetUrl('svn://target/saved');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_target_url'), 'svn://target/saved');
      expect(prefs.getString('last_source_url'), isNull);
    });

    test('default_max_retries：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'default_max_retries': 7,
      });
      await StorageService().init();
      expect(await StorageService().getDefaultMaxRetries(), 7);
    });

    test('default_max_retries：写 key 锁定', () async {
      await StorageService().saveDefaultMaxRetries(9);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('default_max_retries'), 9);
    });

    test('default_max_retries：缺失 key 返回 kDefaultMaxRetries', () async {
      // 锁定"key 缺失 → 默认值"的 fallback 语义；如果 key 被改名，已有用户
      // 的设置会回退到默认值（这正是本轮要防的场景）
      expect(await StorageService().getDefaultMaxRetries(), kDefaultMaxRetries);
    });

    test('merge_validation_script_path：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'merge_validation_script_path': r'Tools\check_merge.sh',
      });
      await StorageService().init();
      expect(
        await StorageService().getMergeValidationScriptPath(),
        'Tools/check_merge.sh',
      );
    });

    test('merge_validation_script_path：写 key 锁定并 trim', () async {
      await StorageService()
          .saveMergeValidationScriptPath(r'  Tools\check_merge.sh  ');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('merge_validation_script_path'),
        'Tools/check_merge.sh',
      );
    });

    test('merge_validation_script_path：缺失 key 返回默认脚本路径', () async {
      await StorageService().init();
      expect(
        await StorageService().getMergeValidationScriptPath(),
        kDefaultMergeValidationScriptPath,
      );
    });

    test('merge_validation_script_path：空白写入会清除 key，读取回落默认路径', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'merge_validation_script_path': 'Tools/check_merge.sh',
      });
      await StorageService().init();

      await StorageService().saveMergeValidationScriptPath('   ');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('merge_validation_script_path'), isFalse);
      expect(
        await StorageService().getMergeValidationScriptPath(),
        kDefaultMergeValidationScriptPath,
      );
    });

    test('use_temporary_sparse_working_copy：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'use_temporary_sparse_working_copy': true,
      });
      await StorageService().init();
      expect(await StorageService().getUseTemporarySparseWorkingCopy(), true);
    });

    test('use_temporary_sparse_working_copy：写 key 锁定', () async {
      await StorageService().saveUseTemporarySparseWorkingCopy(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_temporary_sparse_working_copy'), true);
    });

    test('use_temporary_sparse_working_copy：缺失 key 默认关闭', () async {
      expect(await StorageService().getUseTemporarySparseWorkingCopy(), false);
    });

    test('author_filter_history：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'author_filter_history': <String>['alice', 'bob'],
      });
      await StorageService().init();
      expect(await StorageService().getAuthorFilterHistory(), ['alice', 'bob']);
    });

    test('author_filter_history：写 key 锁定', () async {
      await StorageService().addAuthorToFilterHistory('charlie');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('author_filter_history'), ['charlie']);
    });

    test('last_author_filter：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_author_filter': 'alice',
      });
      await StorageService().init();
      expect(await StorageService().getLastAuthorFilter(), 'alice');
    });

    test('last_author_filter：写 key 锁定', () async {
      await StorageService().saveLastAuthorFilter('bob');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_author_filter'), 'bob');
    });

    test('last_title_filter：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_title_filter': 'fix bug',
      });
      await StorageService().init();
      expect(await StorageService().getLastTitleFilter(), 'fix bug');
    });

    test('last_title_filter：写 key 锁定', () async {
      await StorageService().saveLastTitleFilter('refactor');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_title_filter'), 'refactor');
    });

    test('last_title_filter：空字符串不写', () async {
      await StorageService().saveLastTitleFilter('   ');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_title_filter'), null);
    });

    test('last_title_filter：trim 后写入', () async {
      await StorageService().saveLastTitleFilter('  hello  ');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_title_filter'), 'hello');
    });

    test('last_message_filter：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_message_filter': 'cherry-pick',
      });
      await StorageService().init();
      expect(await StorageService().getLastMessageFilter(), 'cherry-pick');
    });

    test('last_message_filter：写 key 锁定', () async {
      await StorageService().saveLastMessageFilter('hotfix');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_message_filter'), 'hotfix');
    });

    test('last_message_filter：空字符串不写', () async {
      await StorageService().saveLastMessageFilter('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_message_filter'), null);
    });

    test('last_message_filter：trim 后写入', () async {
      await StorageService().saveLastMessageFilter('  msg  ');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_message_filter'), 'msg');
    });

    test('preload_enabled：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_enabled': false,
      });
      await StorageService().init();
      expect(await StorageService().getPreloadEnabled(), false);
    });

    test('preload_enabled：写 key 锁定', () async {
      await StorageService().savePreloadEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('preload_enabled'), true);
    });

    test('preload_stop_on_branch_point：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_stop_on_branch_point': false,
      });
      await StorageService().init();
      expect(await StorageService().getPreloadStopOnBranchPoint(), false);
    });

    test('preload_max_days：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_max_days': 45,
      });
      await StorageService().init();
      expect(await StorageService().getPreloadMaxDays(), 45);
    });

    test('preload_max_count：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_max_count': 500,
      });
      await StorageService().init();
      expect(await StorageService().getPreloadMaxCount(), 500);
    });

    test('preload_stop_revision：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_stop_revision': 12345,
      });
      await StorageService().init();
      expect(await StorageService().getPreloadStopRevision(), 12345);
    });

    test('preload_stop_date：读 key 锁定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_stop_date': '2025-01-15',
      });
      await StorageService().init();
      expect(await StorageService().getPreloadStopDate(), '2025-01-15');
    });

    test('preload_settings 旧 key 在 savePreloadSettings() 中会被清理', () async {
      // 这是历史迁移逻辑：旧版本曾经把 6 个字段塞进单个 'preload_settings'
      // JSON。新版本拆成 6 个独立 key。savePreloadSettings() 调用一次会
      // remove 掉旧 key——这条迁移路径必须保活，否则旧用户数据残留
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preload_settings': '{"enabled":true}', // 旧格式残留
      });
      await StorageService().init();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('preload_settings'), true,
          reason: 'savePreloadSettings 调用之前旧 key 应仍存在');
      await StorageService().savePreloadSettings(<String, dynamic>{
        'enabled': true,
      });
      expect(prefs.containsKey('preload_settings'), false,
          reason: 'savePreloadSettings 必须把旧 key 清掉');
    });

    test('全部 key 名集合（防止漂移的兜底快照）', () async {
      // 一次性写所有 key，再断言每个 key 都能被找回。这是对单 key 测试的
      // 双保险——如果有人新增 key 但忘了写测试，至少在这里会暴露。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'source_url_history': <String>['x'],
        'switch_branch_history': <String>['sw'],
        'target_wc_history': <String>['y'],
        'target_url_history': <String>['tu'],
        'last_source_url': 'lsu',
        'last_target_wc': 'ltw',
        'last_target_url': 'ltu',
        'default_max_retries': 3,
        'merge_validation_script_path': 'Tools/check_merge.sh',
        'author_filter_history': <String>['af'],
        'last_author_filter': 'laf',
        'preload_enabled': true,
        'preload_stop_on_branch_point': true,
        'preload_max_days': 30,
        'preload_max_count': 100,
        'preload_stop_revision': 1,
        'preload_stop_date': '2025-01-01',
        'use_temporary_sparse_working_copy': true,
      });
      await StorageService().init();
      final prefs = await SharedPreferences.getInstance();
      // R104 已知 key 列表（按字母序）；任何新增/删除/改名必须同步更新这里
      const knownKeys = <String>[
        'author_filter_history',
        'default_max_retries',
        'last_author_filter',
        'last_source_url',
        'last_target_wc',
        'last_target_url',
        'merge_validation_script_path',
        'preload_enabled',
        'preload_max_count',
        'preload_max_days',
        'preload_stop_date',
        'preload_stop_on_branch_point',
        'preload_stop_revision',
        'source_url_history',
        'switch_branch_history',
        'target_wc_history',
        'target_url_history',
        'use_temporary_sparse_working_copy',
      ];
      for (final key in knownKeys) {
        expect(prefs.containsKey(key), true,
            reason: '已知 key "$key" 必须可被 SharedPreferences 看到');
      }
      // 反向：如果 lib 引入了未登记的新 key，知名 key 数量与实际不符就会暴露
      expect(prefs.getKeys().toSet(), knownKeys.toSet(),
          reason: 'lib 实际持久化的 key 集合必须与 R104 已知清单完全一致；'
              '若新增 key，必须同步更新 R104 已知清单和单 key 测试');
    });
  });

  group('队列文件 JSON schema 持久化（R105）', () {
    // R105：JSON file format 持久化兼容审计——锁定队列文件的顶层 schema 字段名、
    // 序列化格式、异常路径。背景：原 loadQueue / saveQueue 直接 inline JSON 处理，
    // 'jobs' 字面量散落在 storage_service.dart 两处（读 + 写），任何重命名都会
    // 让用户已经持久化的队列文件在下次启动时静默丢失（loadQueue 走 catch 路径
    // 返回空 list）。R105 把 JSON 解析/序列化抽出到 parseQueueJson /
    // serializeQueueJson 纯函数 + 在此 group 锁字段名与格式契约。
    //
    // **R104 错误纠正**：R104 在 storage_service_test.dart:534 注释里声称
    // "loadQueue/saveQueue 已有 round-trip 集成测试覆盖"——实际只有 app_paths
    // 测了文件路径解析，loadQueue/saveQueue 的 JSON 处理本身没有任何测试。
    // R105 补齐这条空白。

    MergeJob makeJob(int jobId) {
      return MergeJob(
        jobId: jobId,
        sourceUrl: 'svn://source/$jobId',
        targetWc: '/tmp/wc/$jobId',
        targetUrl: 'svn://target/$jobId',
        maxRetries: 3,
        revisions: [jobId * 10, jobId * 10 + 1],
        status: JobStatus.pending,
      );
    }

    group('serializeQueueJson 输出格式', () {
      test("顶层固定为 'jobs' 字段对象", () {
        final content = serializeQueueJson([makeJob(1)]);
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded.keys.toSet(), {'jobs'},
            reason: "顶层 schema 必须是 {'jobs': [...]}；新增字段会破坏 parseQueueJson");
        expect(decoded['jobs'], isA<List>(),
            reason: "'jobs' 字段必须是 List；改类型会让 parseQueueJson 抛 TypeError");
      });

      test('空 list → 空 jobs 数组', () {
        final content = serializeQueueJson([]);
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded['jobs'], isEmpty);
      });

      test('使用 2 空格缩进（人类可读）', () {
        final content = serializeQueueJson([makeJob(1)]);
        // 缩进检查：第二行（'jobs' 字段所在行）必须以 2 空格开头
        final lines = content.split('\n');
        expect(lines.length, greaterThan(1),
            reason: 'JsonEncoder.withIndent 输出必然带换行');
        expect(lines[1].startsWith('  "jobs"'), isTrue,
            reason: '缩进格式：JsonEncoder.withIndent("  ") = 2 空格；'
                '改成无缩进或制表符会让备份/版本控制场景下的 diff 噪音激增');
      });

      test('多 job 顺序保留', () {
        final content =
            serializeQueueJson([makeJob(1), makeJob(2), makeJob(3)]);
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        final jobsList = decoded['jobs'] as List<dynamic>;
        final ids = jobsList
            .map((j) => (j as Map<String, dynamic>)['jobId'] as int)
            .toList();
        expect(ids, [1, 2, 3], reason: '任务队列顺序 = 执行顺序，序列化必须保留 list 顺序');
      });
    });

    group('parseQueueJson 解析契约', () {
      test('正常路径：空 jobs → 空 list', () {
        final result = parseQueueJson('{"jobs": []}');
        expect(result, isEmpty);
      });

      test('正常路径：单 job round-trip', () {
        final original = [makeJob(42)];
        final content = serializeQueueJson(original);
        final parsed = parseQueueJson(content);
        expect(parsed.length, 1);
        expect(parsed[0].jobId, 42);
        expect(parsed[0].sourceUrl, 'svn://source/42');
        expect(parsed[0].targetWc, '/tmp/wc/42');
        expect(parsed[0].targetUrl, 'svn://target/42');
      });

      test('旧队列文件缺 targetUrl → 解析为 null（向后兼容）', () {
        final parsed = parseQueueJson('''
{
  "jobs": [
    {
      "jobId": 7,
      "sourceUrl": "svn://source/7",
      "targetWc": "/tmp/wc/7",
      "maxRetries": 3,
      "revisions": [70],
      "status": "pending"
    }
  ]
}
''');
        expect(parsed.single.targetUrl, isNull);
      });

      test('多 job round-trip 顺序保留', () {
        final original = [makeJob(1), makeJob(2), makeJob(3)];
        final content = serializeQueueJson(original);
        final parsed = parseQueueJson(content);
        expect(parsed.map((j) => j.jobId).toList(), [1, 2, 3],
            reason: 'parse 必须保留 JSON 数组顺序——loadQueue 后续传给 '
                'recoverInterruptedJobs 时仍按 list 顺序处理');
      });

      test('异常：顶层非 Map（裸数组）→ 抛 TypeError', () {
        expect(() => parseQueueJson('[]'), throwsA(isA<TypeError>()),
            reason: '顶层必须是对象 {...}；裸数组会让 jsonDecode as Map 失败。'
                '调用方 loadQueue 用 try/catch 吞掉、返回空 list（安全降级）');
      });

      test('异常：缺 jobs 字段 → 抛 TypeError', () {
        expect(() => parseQueueJson('{}'), throwsA(isA<TypeError>()),
            reason: "缺 'jobs' 字段时 json['jobs'] 是 null，as List 强转抛 TypeError");
      });

      test("异常：'jobs' 字段非 List → 抛 TypeError", () {
        expect(() => parseQueueJson('{"jobs": "not-a-list"}'),
            throwsA(isA<TypeError>()),
            reason: "'jobs' 类型契约：必须是 List。改成 Map 或 String 会让"
                'as List<dynamic> 强转抛 TypeError——loadQueue 走 catch 路径返回空 list');
      });

      test('异常：jobs 元素非 Map → 抛 TypeError', () {
        expect(() => parseQueueJson('{"jobs": ["not-a-map"]}'),
            throwsA(isA<TypeError>()),
            reason: '元素契约：必须是 Map，能被 MergeJob.fromJson 接受。'
                '元素损坏时**强制**整次 loadQueue 失败而非部分恢复——'
                '这是有意行为：损坏的队列文件走"全空 + 用户重建"安全路径');
      });

      test('异常：非 JSON 字符串 → 抛 FormatException', () {
        expect(() => parseQueueJson('not-valid-json'),
            throwsA(isA<FormatException>()),
            reason: 'jsonDecode 解析失败抛 FormatException——loadQueue 吞掉返回空');
      });
    });

    group('queue 文件 JSON 字段名字面量锁定', () {
      test("'jobs' 字面量锁定（向后兼容防漏）", () {
        // R105：用断言反向锁住"如果 serializeQueueJson 内部把 'jobs' 改名为
        // 'queue' 或 'items'，这条 fail 是第一道防御"。同时它也保护
        // parseQueueJson——后者必须用同样字面量读，否则 round-trip 立刻 fail。
        final content = serializeQueueJson([makeJob(1)]);
        expect(content.contains('"jobs"'), isTrue,
            reason: "'jobs' 是磁盘文件 schema 字段，与用户已有的 queue.json 文件"
                "强耦合。改名必须配合迁移路径——参考 R104 preload_settings 旧 key 清理模式");
        expect(content.contains('"queue"'), isFalse,
            reason: '反向锁：如果有人把字段名改成 queue / items / tasks，必撞红');
      });

      test('已知 JSON schema 字段全集快照', () {
        // R104 在 prefs 维度建立"已知 key 全集"代偿登记表；R105 在 file
        // schema 维度做同样的事——锁定队列文件的顶层 schema 字段集合，
        // 新增字段必撞红。**这是用测试代偿 lib 缺 schema version 字段**。
        const knownTopLevelKeys = {'jobs'};
        final content = serializeQueueJson([makeJob(1)]);
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded.keys.toSet(), knownTopLevelKeys,
            reason: '队列文件顶层 schema 必须与已知字段集合完全一致；'
                '新增字段（如 "version" / "metadata"）需同步更新此清单 + 加迁移路径测试');
      });
    });
  });
}
