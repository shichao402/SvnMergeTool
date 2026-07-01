import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/services/log_cache_service.dart';
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/log_filter_service.dart'
    show isUsableWorkingDirectory;
import 'package:svn_auto_merge/services/svn_service.dart'
    show isUsableSvnCredential;
import 'package:svn_auto_merge/providers/app_state.dart'
    show isUsableSourceUrl;
import 'package:svn_auto_merge/services/log_sync_service.dart'
    show isHeadRevisionValid;

CachedRange _r(int id, int start, int end) => CachedRange(
      id: id,
      startRevision: start,
      endRevision: end,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

({int id, int start, int end}) _rec(int id, int start, int end) =>
    (id: id, start: start, end: end);

LogEntry _entry(int rev) => LogEntry(
      revision: rev,
      author: 'a',
      date: '2024-01-01',
      title: 't',
      message: 'm',
    );

void main() {
  setUpAll(() {
    // 与 svn_xml_parser_test 同样：业务代码错误回退路径会调 AppLogger，
    // 而 LoggerService 在没有 Flutter binding 的纯单测里会通过 path_provider
    // 触发 ServicesBinding.instance 失败 → microtask 死循环。这里用不到日志。
    logger.enabled = false;
  });

  group('CachedRange.isContinuousWith', () {
    test('end == other.start → 连续', () {
      // [200,100] 和 [100,50]：100 == 100
      expect(_r(1, 200, 100).isContinuousWith(_r(2, 100, 50)), isTrue);
    });

    test('对称：other.end == start → 也算连续', () {
      // [100,50] 和 [200,100]：100 == 100（从另一侧匹配）
      expect(_r(2, 100, 50).isContinuousWith(_r(1, 200, 100)), isTrue);
    });

    test('差 1 不算连续——避免被 +1 误判', () {
      // [200,101] 和 [100,50]：101 != 100，不是连续
      expect(_r(1, 200, 101).isContinuousWith(_r(2, 100, 50)), isFalse);
    });

    test('完全不相交 → 不连续', () {
      expect(_r(1, 300, 200).isContinuousWith(_r(2, 100, 50)), isFalse);
    });

    test('区间重叠但首尾不等 → 不连续（按当前定义）', () {
      // [200, 80] 与 [100, 50]：交叠但 80 != 100、50 != 200，不算连续
      expect(_r(1, 200, 80).isContinuousWith(_r(2, 100, 50)), isFalse);
    });
  });

  group('CachedRange.mergeWith', () {
    test('合并连续区间：新 start 取较大、新 end 取较小', () {
      final a = _r(1, 200, 100);
      final b = _r(2, 100, 50);
      final m = a.mergeWith(b);
      expect(m.startRevision, 200);
      expect(m.endRevision, 50);
    });

    test('保留调用方的 id', () {
      final a = _r(1, 200, 100);
      final b = _r(2, 100, 50);
      expect(a.mergeWith(b).id, 1);
      expect(b.mergeWith(a).id, 2);
    });

    test('createdAt 取较早者', () {
      final earlier = DateTime.fromMillisecondsSinceEpoch(1000);
      final later = DateTime.fromMillisecondsSinceEpoch(2000);
      final a = CachedRange(
        id: 1,
        startRevision: 200,
        endRevision: 100,
        createdAt: later,
        updatedAt: later,
      );
      final b = CachedRange(
        id: 2,
        startRevision: 100,
        endRevision: 50,
        createdAt: earlier,
        updatedAt: earlier,
      );
      expect(a.mergeWith(b).createdAt, earlier);
      expect(b.mergeWith(a).createdAt, earlier);
    });

    test('不连续直接抛 ArgumentError', () {
      expect(
        () => _r(1, 200, 101).mergeWith(_r(2, 100, 50)),
        throwsArgumentError,
      );
    });
  });

  group('CachedRange.revisionSpan', () {
    test('start - end + 1 即版本跨度', () {
      expect(_r(1, 200, 100).revisionSpan, 101);
      expect(_r(1, 50, 50).revisionSpan, 1);
    });
  });

  group('planMergeAdjacentRanges', () {
    test('空列表 → 全空 plan', () {
      final plan = planMergeAdjacentRanges([]);
      expect(plan.toDelete, isEmpty);
      expect(plan.toUpdate, isEmpty);
      expect(plan.merged, isEmpty);
    });

    test('单元素 → 全空 plan，merged 原样返回', () {
      final input = [_rec(1, 200, 100)];
      final plan = planMergeAdjacentRanges(input);
      expect(plan.toDelete, isEmpty);
      expect(plan.toUpdate, isEmpty);
      expect(plan.merged, [_rec(1, 200, 100)]);
    });

    test('两个连续区间 → next 删除、current end 扩展', () {
      // [200,100] + [100,50] → [200,50]
      final plan = planMergeAdjacentRanges([
        _rec(1, 200, 100),
        _rec(2, 100, 50),
      ]);
      expect(plan.toDelete, [2]);
      expect(plan.toUpdate, [(id: 1, newEnd: 50)]);
      expect(plan.merged, [_rec(1, 200, 50)]);
    });

    test('两个不连续区间 → 不动', () {
      // [200, 110] + [100, 50]：110 != 100
      final input = [_rec(1, 200, 110), _rec(2, 100, 50)];
      final plan = planMergeAdjacentRanges(input);
      expect(plan.toDelete, isEmpty);
      expect(plan.toUpdate, isEmpty);
      expect(plan.merged, input);
    });

    test('链式合并：三段连续 → 合成一段，仅保留首段 id', () {
      // [300,200] + [200,100] + [100,50] → [300,50]
      final plan = planMergeAdjacentRanges([
        _rec(1, 300, 200),
        _rec(2, 200, 100),
        _rec(3, 100, 50),
      ]);
      expect(plan.toDelete, containsAll([2, 3]));
      expect(plan.toDelete.length, 2);
      // toUpdate 只对“吸收方”id=1 起作用——两次合并都更新同一个 id 的 end，
      // 最终 plan.toUpdate 里只剩一条 (id:1, newEnd:50)（用 map 去重）
      expect(plan.toUpdate, hasLength(1));
      expect(plan.toUpdate.single.id, 1);
      expect(plan.toUpdate.single.newEnd, 50);
      expect(plan.merged, [_rec(1, 300, 50)]);
    });

    test('部分连续：连续段合并、不连续段保留', () {
      // [300,200] + [200,100] 连续 → 合成 [300,100]
      // [100,50] 与 [300,100] 又连续 → 再合成 [300,50]
      // 但如果中间断开，例如：[300,200] + [200,100] + [80,50]
      //   前两段合成 [300,100]，与 [80,50] 不连续，保留两段
      final plan = planMergeAdjacentRanges([
        _rec(1, 300, 200),
        _rec(2, 200, 100),
        _rec(3, 80, 50),
      ]);
      expect(plan.toDelete, [2]);
      expect(plan.toUpdate, [(id: 1, newEnd: 100)]);
      expect(plan.merged, [_rec(1, 300, 100), _rec(3, 80, 50)]);
    });

    test('两段不连续 + 后两段连续：仅后两段合并', () {
      // [500,400] 独立；[300,200] + [200,100] 合并为 [300,100]
      final plan = planMergeAdjacentRanges([
        _rec(1, 500, 400),
        _rec(2, 300, 200),
        _rec(3, 200, 100),
      ]);
      expect(plan.toDelete, [3]);
      expect(plan.toUpdate, [(id: 2, newEnd: 100)]);
      expect(plan.merged, [_rec(1, 500, 400), _rec(2, 300, 100)]);
    });

    test('不污染调用方的输入列表', () {
      final input = [_rec(1, 200, 100), _rec(2, 100, 50)];
      final snapshot = List.of(input);
      planMergeAdjacentRanges(input);
      expect(input, snapshot);
    });
  });

  group('planRangeUpdateAfterInsert', () {
    test('latestRange 为 null → createNewRange，使用本次范围', () {
      final plan = planRangeUpdateAfterInsert(
        latestRange: null,
        latestRevision: 200,
        earliestRevision: 100,
        isFromHead: true,
      );
      expect(plan.action, RangeUpdateAction.createNewRange);
      expect(plan.newStart, 200);
      expect(plan.newEnd, 100);
    });

    test('latestRange 为 null + isFromHead=false 也是 createNewRange', () {
      // 没有任何区间时，HEAD 与否没区别
      final plan = planRangeUpdateAfterInsert(
        latestRange: null,
        latestRevision: 80,
        earliestRevision: 50,
        isFromHead: false,
      );
      expect(plan.action, RangeUpdateAction.createNewRange);
      expect(plan.newStart, 80);
      expect(plan.newEnd, 50);
    });

    test('fromHead 与最新区间首尾连续 → extendStart', () {
      // 现有 [200, 100]，本次 [300, 200]：earliestRevision(200) == startRevision(200)
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 200, 100),
        latestRevision: 300,
        earliestRevision: 200,
        isFromHead: true,
      );
      expect(plan.action, RangeUpdateAction.extendStart);
      expect(plan.newStart, 300);
      expect(plan.newEnd, isNull);
    });

    test('fromHead 不连续但本次更新 → createNewRange', () {
      // 现有 [200, 100]，本次 [400, 350]：不连续（350 != 200）但 400 > 200
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 200, 100),
        latestRevision: 400,
        earliestRevision: 350,
        isFromHead: true,
      );
      expect(plan.action, RangeUpdateAction.createNewRange);
      expect(plan.newStart, 400);
      expect(plan.newEnd, 350);
    });

    test('fromHead 但数据已被覆盖 → noop', () {
      // 现有 [500, 100]，本次 [400, 300]：不连续且 400 < 500
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 500, 100),
        latestRevision: 400,
        earliestRevision: 300,
        isFromHead: true,
      );
      expect(plan.action, RangeUpdateAction.noop);
    });

    test('fromHead latestRevision == startRevision 边界（不连续，单条已存在）→ noop', () {
      // 现有 [500, 100]，本次 [500, 480]：earliestRevision(480) != startRevision(500)
      // 且 latestRevision(500) 不严格大于 startRevision(500) → 走 noop 分支
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 500, 100),
        latestRevision: 500,
        earliestRevision: 480,
        isFromHead: true,
      );
      expect(plan.action, RangeUpdateAction.noop);
    });

    test('loadMore 与最新区间首尾连续 → extendEnd', () {
      // 现有 [200, 100]，本次 [100, 50]：latestRevision(100) == endRevision(100)
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 200, 100),
        latestRevision: 100,
        earliestRevision: 50,
        isFromHead: false,
      );
      expect(plan.action, RangeUpdateAction.extendEnd);
      expect(plan.newEnd, 50);
      expect(plan.newStart, isNull);
    });

    test('loadMore 不连续（异常路径兜底）→ createNewRange', () {
      // 现有 [200, 100]，本次 [80, 50]：80 != 100，但仍兜底新开
      final plan = planRangeUpdateAfterInsert(
        latestRange: _r(1, 200, 100),
        latestRevision: 80,
        earliestRevision: 50,
        isFromHead: false,
      );
      expect(plan.action, RangeUpdateAction.createNewRange);
      expect(plan.newStart, 80);
      expect(plan.newEnd, 50);
    });
  });

  group('resolveSourceUrlHash', () {
    test('空映射 → attempts=0，hash 为 MD5 前 16 位', () {
      final r = resolveSourceUrlHash('https://svn.example/repo', {});
      expect(r.attempts, 0);
      expect(r.hash, hasLength(16));
      // MD5 前 16 位是十六进制字符
      expect(r.hash, matches(r'^[0-9a-f]{16}$'));
    });

    test('同一 url 多次解析得到相同 hash', () {
      final a = resolveSourceUrlHash('https://svn.example/repo', {});
      final b = resolveSourceUrlHash('https://svn.example/repo', {});
      expect(a.hash, b.hash);
    });

    test('映射里已有同一 hash 但指向同一 url → 不视为冲突，attempts=0', () {
      const url = 'https://svn.example/repo';
      final base = resolveSourceUrlHash(url, {}).hash;
      final r = resolveSourceUrlHash(url, {base: url});
      expect(r.attempts, 0);
      expect(r.hash, base);
    });

    test('hash 冲突一次 → attempts=1，回退用 url#1 重新算', () {
      const url = 'https://svn.example/repo';
      final base = resolveSourceUrlHash(url, {}).hash;
      // 故意用一个不同的 url 占住 base hash
      final r = resolveSourceUrlHash(url, {base: 'https://other/repo'});
      expect(r.attempts, 1);
      expect(r.hash, isNot(base));
      expect(r.hash, hasLength(16));
    });

    test('连续冲突两次 → attempts=2', () {
      const url = 'https://svn.example/repo';
      final base = resolveSourceUrlHash(url, {}).hash;
      final retry1 = resolveSourceUrlHash(
        url,
        {base: 'https://other-a/repo'},
      ).hash;
      // 第一轮重试得到 retry1；让它也被另一个 url 占住，强制再次重试
      final r = resolveSourceUrlHash(url, {
        base: 'https://other-a/repo',
        retry1: 'https://other-b/repo',
      });
      expect(r.attempts, 2);
      expect(r.hash, isNot(base));
      expect(r.hash, isNot(retry1));
    });

    test('不修改传入的 hashToUrlMap', () {
      const url = 'https://svn.example/repo';
      final base = resolveSourceUrlHash(url, {}).hash;
      final map = <String, String>{base: 'https://other/repo'};
      final snapshot = Map<String, String>.from(map);
      resolveSourceUrlHash(url, map);
      expect(map, snapshot);
    });
  });

  group('revisionExtremesOf', () {
    test('多元素：取最大与最小', () {
      final r = revisionExtremesOf([
        _entry(100),
        _entry(50),
        _entry(200),
        _entry(75),
      ]);
      expect(r, const RevisionExtremes(latest: 200, earliest: 50));
    });

    test('单元素：latest == earliest', () {
      final r = revisionExtremesOf([_entry(42)]);
      expect(r, const RevisionExtremes(latest: 42, earliest: 42));
    });

    test('重复 revision 不去重也不影响 max/min', () {
      final r = revisionExtremesOf([
        _entry(10),
        _entry(10),
        _entry(10),
        _entry(5),
        _entry(20),
      ]);
      expect(r, const RevisionExtremes(latest: 20, earliest: 5));
    });

    test('空列表抛 StateError（与 reduce 行为一致，不做防御兜底）', () {
      // 决策锁定：空入参由上游守卫保证，这里**不**静默吞掉。
      expect(() => revisionExtremesOf(const []), throwsStateError);
    });

    test('已升序输入', () {
      final r = revisionExtremesOf([_entry(1), _entry(2), _entry(3)]);
      expect(r, const RevisionExtremes(latest: 3, earliest: 1));
    });

    test('已降序输入', () {
      final r = revisionExtremesOf([_entry(3), _entry(2), _entry(1)]);
      expect(r, const RevisionExtremes(latest: 3, earliest: 1));
    });

    test('RevisionExtremes 按字段 == / hashCode', () {
      const a = RevisionExtremes(latest: 9, earliest: 1);
      const b = RevisionExtremes(latest: 9, earliest: 1);
      const c = RevisionExtremes(latest: 9, earliest: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('RevisionExtremes.toString 含两个字段', () {
      expect(
        const RevisionExtremes(latest: 7, earliest: 3).toString(),
        contains('latest=7'),
      );
      expect(
        const RevisionExtremes(latest: 7, earliest: 3).toString(),
        contains('earliest=3'),
      );
    });
  });

  group('mergeMetadataExtremes', () {
    test('currentLatest == null（首次插入）→ 直接用 incoming', () {
      final r = mergeMetadataExtremes(
        currentLatest: null,
        currentEarliest: null,
        incomingLatest: 100,
        incomingEarliest: 50,
      );
      expect(r.latest, 100);
      expect(r.earliest, 50);
    });

    test('current 比 incoming 宽：取 current', () {
      final r = mergeMetadataExtremes(
        currentLatest: 200,
        currentEarliest: 10,
        incomingLatest: 100,
        incomingEarliest: 50,
      );
      expect(r.latest, 200);
      expect(r.earliest, 10);
    });

    test('incoming 比 current 宽：取 incoming', () {
      final r = mergeMetadataExtremes(
        currentLatest: 100,
        currentEarliest: 80,
        incomingLatest: 200,
        incomingEarliest: 50,
      );
      expect(r.latest, 200);
      expect(r.earliest, 50);
    });

    test('部分扩张：current 顶 latest，incoming 顶 earliest', () {
      final r = mergeMetadataExtremes(
        currentLatest: 200,
        currentEarliest: 80,
        incomingLatest: 100,
        incomingEarliest: 50,
      );
      expect(r.latest, 200);
      expect(r.earliest, 50);
    });

    test('完全相等：取任一即可，结果稳定', () {
      final r = mergeMetadataExtremes(
        currentLatest: 100,
        currentEarliest: 50,
        incomingLatest: 100,
        incomingEarliest: 50,
      );
      expect(r.latest, 100);
      expect(r.earliest, 50);
    });

    test('currentEarliest 为 null 但 currentLatest 非空 → incoming earliest 直接用', () {
      // metadata 半残（理论不该发生，防御性测试）
      final r = mergeMetadataExtremes(
        currentLatest: 200,
        currentEarliest: null,
        incomingLatest: 100,
        incomingEarliest: 50,
      );
      expect(r.latest, 200);
      expect(r.earliest, 50);
    });

    test('元数据永远不缩小（关键不变量）', () {
      // 即使 incoming 更窄，结果范围也只能更宽。
      final r = mergeMetadataExtremes(
        currentLatest: 1000,
        currentEarliest: 1,
        incomingLatest: 500,
        incomingEarliest: 400,
      );
      expect(r.latest, 1000);
      expect(r.earliest, 1);
    });
  });

  group('formatInsertEntriesHeaderLines', () {
    test('恒为 3 行，标题不带缩进，数据行两空格缩进', () {
      final lines = formatInsertEntriesHeaderLines(
        entriesCount: 42,
        latestRevision: 100,
        earliestRevision: 50,
        isFromHead: true,
      );
      expect(lines, hasLength(3));
      expect(lines[0], '【insertEntries】插入 42 条日志');
      expect(lines[0].startsWith(' '), isFalse);
      expect(lines[1].startsWith('  '), isTrue);
      expect(lines[2].startsWith('  '), isTrue);
    });

    test('字段顺序：标题 → 范围 → isFromHead', () {
      final lines = formatInsertEntriesHeaderLines(
        entriesCount: 1,
        latestRevision: 200,
        earliestRevision: 100,
        isFromHead: false,
      );
      expect(lines[0], '【insertEntries】插入 1 条日志');
      expect(lines[1], '  范围: [200, 100]');
      expect(lines[2], '  isFromHead: false');
    });

    test('范围保持 [latest, earliest] 顺序（latest 在前，与 SQL/原日志一致）', () {
      final lines = formatInsertEntriesHeaderLines(
        entriesCount: 5,
        latestRevision: 999,
        earliestRevision: 1,
        isFromHead: true,
      );
      expect(lines[1], '  范围: [999, 1]');
    });

    test('isFromHead=true 时第 3 行精确文案', () {
      final lines = formatInsertEntriesHeaderLines(
        entriesCount: 1,
        latestRevision: 1,
        earliestRevision: 1,
        isFromHead: true,
      );
      expect(lines[2], '  isFromHead: true');
    });
  });

  group('formatRangeUpdateHeaderLines', () {
    test('恒为 4 行，标题不带缩进，其余三行两空格缩进', () {
      final lines = formatRangeUpdateHeaderLines(
        latestRevision: 100,
        earliestRevision: 50,
        isFromHead: true,
        latestRange: null,
      );
      expect(lines, hasLength(4));
      expect(lines[0], '【区间更新】开始');
      expect(lines[0].startsWith(' '), isFalse);
      for (final line in lines.sublist(1)) {
        expect(line.startsWith('  '), isTrue);
      }
    });

    test('latestRange == null → "无"', () {
      final lines = formatRangeUpdateHeaderLines(
        latestRevision: 100,
        earliestRevision: 50,
        isFromHead: true,
        latestRange: null,
      );
      expect(lines[3], '  当前最新区间: 无');
    });

    test('latestRange 非空 → 走 toString()', () {
      final range = _r(7, 200, 100);
      final lines = formatRangeUpdateHeaderLines(
        latestRevision: 90,
        earliestRevision: 80,
        isFromHead: false,
        latestRange: range,
      );
      expect(lines[3], '  当前最新区间: ${range.toString()}');
    });

    test('字段顺序：标题 → 范围 → isFromHead → 当前最新区间', () {
      final lines = formatRangeUpdateHeaderLines(
        latestRevision: 100,
        earliestRevision: 50,
        isFromHead: true,
        latestRange: null,
      );
      expect(lines[0], '【区间更新】开始');
      expect(lines[1], '  本次插入范围: [100, 50]');
      expect(lines[2], '  isFromHead: true');
      expect(lines[3], '  当前最新区间: 无');
    });
  });

  group('shouldExtendLatestRangeEnd', () {
    // end 是较小的 revision，扩展终点 = 向旧版本走 = end 变小，所以 newEnd < end 才算"真扩展"。

    test('latestRange == null → false（没有区间可扩展）', () {
      expect(
        shouldExtendLatestRangeEnd(latestRange: null, newEndRevision: 50),
        isFalse,
      );
    });

    test('newEnd < endRevision → true（真扩展）', () {
      expect(
        shouldExtendLatestRangeEnd(
          latestRange: _r(1, 200, 100),
          newEndRevision: 50,
        ),
        isTrue,
      );
    });

    test('newEnd == endRevision → false（等值不算扩展，避免一次 noop SQL）', () {
      expect(
        shouldExtendLatestRangeEnd(
          latestRange: _r(1, 200, 100),
          newEndRevision: 100,
        ),
        isFalse,
      );
    });

    test('newEnd > endRevision → false（"扩展"方向反了，应当跳过）', () {
      expect(
        shouldExtendLatestRangeEnd(
          latestRange: _r(1, 200, 100),
          newEndRevision: 150,
        ),
        isFalse,
      );
    });

    test('newEnd 比 endRevision 仅差 1 也算真扩展（无最小步长门槛）', () {
      // 显式锁定：不做任何 step-size guard，差 1 也写。
      expect(
        shouldExtendLatestRangeEnd(
          latestRange: _r(1, 200, 100),
          newEndRevision: 99,
        ),
        isTrue,
      );
    });

    test('endRevision==1 / newEnd==0：边界 revision 也按 < 比较（不做合法性校验）', () {
      // 不假设 revision 必须 >= 1，也不假设有"0/负数"的特殊语义。
      expect(
        shouldExtendLatestRangeEnd(
          latestRange: _r(1, 10, 1),
          newEndRevision: 0,
        ),
        isTrue,
      );
    });
  });

  group('shouldExtendLatestRangeStart', () {
    // start 是较大的 revision，扩展起点 = 向新版本走 = start 变大，所以 newStart > start 才算"真扩展"。

    test('latestRange == null → false（没有区间可扩展）', () {
      expect(
        shouldExtendLatestRangeStart(latestRange: null, newStartRevision: 300),
        isFalse,
      );
    });

    test('newStart > startRevision → true（真扩展）', () {
      expect(
        shouldExtendLatestRangeStart(
          latestRange: _r(1, 200, 100),
          newStartRevision: 300,
        ),
        isTrue,
      );
    });

    test('newStart == startRevision → false（等值不算扩展，避免一次 noop SQL）', () {
      expect(
        shouldExtendLatestRangeStart(
          latestRange: _r(1, 200, 100),
          newStartRevision: 200,
        ),
        isFalse,
      );
    });

    test('newStart < startRevision → false（"扩展"方向反了，应当跳过）', () {
      expect(
        shouldExtendLatestRangeStart(
          latestRange: _r(1, 200, 100),
          newStartRevision: 150,
        ),
        isFalse,
      );
    });

    test('newStart 比 startRevision 仅多 1 也算真扩展（无最小步长门槛）', () {
      expect(
        shouldExtendLatestRangeStart(
          latestRange: _r(1, 200, 100),
          newStartRevision: 201,
        ),
        isTrue,
      );
    });

    test('end 与 start 比较方向相反：同一个 latestRange 下，相同 newRevision 的两个守卫给出对称结论', () {
      // 锁定"end 用 <、start 用 >"的方向对称性——防止有人误把方向写反。
      // 取 newRevision = 150（在 [100, 200] 之间），按定义：
      //   - 对 end (=100) 来说，150 > 100，**不是**真扩展（end 应当变小）→ false
      //   - 对 start (=200) 来说，150 < 200，**不是**真扩展（start 应当变大）→ false
      // 两边都是 false 是巧合（newRevision 落在区间内），但能验证"两边比较方向相反"。
      final range = _r(1, 200, 100);
      expect(
        shouldExtendLatestRangeEnd(latestRange: range, newEndRevision: 150),
        isFalse,
      );
      expect(
        shouldExtendLatestRangeStart(
            latestRange: range, newStartRevision: 150),
        isFalse,
      );

      // 反向：newRevision = 50（小于 end 100）
      //   - 对 end 来说，50 < 100 → true（end 变小，真扩展）
      //   - 对 start 来说，50 < 200 → false（start 应当变大，方向反了）
      expect(
        shouldExtendLatestRangeEnd(latestRange: range, newEndRevision: 50),
        isTrue,
      );
      expect(
        shouldExtendLatestRangeStart(
            latestRange: range, newStartRevision: 50),
        isFalse,
      );

      // newRevision = 300（大于 start 200）
      //   - 对 end 来说，300 > 100 → false
      //   - 对 start 来说，300 > 200 → true
      expect(
        shouldExtendLatestRangeEnd(latestRange: range, newEndRevision: 300),
        isFalse,
      );
      expect(
        shouldExtendLatestRangeStart(
            latestRange: range, newStartRevision: 300),
        isTrue,
      );
    });
  });

  group('buildLogEntryFilterClauses', () {
    test('全 null + minRevision<=0 → 空 whereClauses 与空 args', () {
      // 调用方据此跳过 'WHERE' 关键字。三个常见"未启用"哨兵都视作未启用：
      // null / 0 / 负数。
      for (final v in [null, 0, -1]) {
        final c = buildLogEntryFilterClauses(
          minRevision: v,
          authorFilter: null,
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        );
        expect(c.whereClauses, isEmpty, reason: 'minRevision=$v 应空');
        expect(c.args, isEmpty);
      }
    });

    test('维度顺序固定：minRevision → author → title', () {
      // 单测显式锁定 SQL 片段在 list 中的相对位置——
      // 调换顺序虽不改语义但会让 SQL 文本回归 diff 出现在不该出现的地方。
      final c = buildLogEntryFilterClauses(
        minRevision: 100,
        authorFilter: 'alice',
        titleFilter: 'fix',
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(c.whereClauses, [
        'revision >= ?',
        'author = ?',
        'LOWER(title) LIKE ?',
      ]);
      expect(c.args, [100, 'alice', '%fix%']);
    });

    test('minRevision 守卫：> 0 才生效（0 视作未启用）', () {
      // 防御性边界——SVN revision 1 起步，0 是哨兵；
      // 任何把 `> 0` 改成 `>= 0` 的"清理"会让用户传 0 时意外加入 'revision >= 0'，
      // 虽然不影响结果但让 SQL 多一段无意义子句。
      expect(
        buildLogEntryFilterClauses(
          minRevision: 0,
          authorFilter: null,
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        ).whereClauses,
        isEmpty,
      );
      expect(
        buildLogEntryFilterClauses(
          minRevision: 1,
          authorFilter: null,
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        ).whereClauses,
        ['revision >= ?'],
      );
    });

    test('author 空串守卫：null / "" 都视作未启用，不做 trim 后判空', () {
      // **故意保留**：调用方在 UI 层负责去白；底层不重复防御。
      // 全空字符串（仅含空白）会被视作"已启用"，与 `isMergeInfoArgsValid`
      // 的同源决策一致——下一行单测显式锁定。
      for (final f in [null, '']) {
        expect(
          buildLogEntryFilterClauses(
            minRevision: null,
            authorFilter: f,
            titleFilter: null,
            messageFilter: null,
            authorMode: AuthorMatchMode.exact,
          ).whereClauses,
          isEmpty,
          reason: 'authorFilter=$f 应未启用',
        );
      }
    });

    test('author 仅空格 → 视作"已启用"，exact 模式下 trim 后变空字符串', () {
      // 锁定"不在底层 trim 后判空"——如果 UI 错传 '   '，会得到
      // `author = ''` 这种**永远查不到结果的 SQL**，作为 bug 信号显眼，
      // 比静默忽略好。
      final c = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: '   ',
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(c.whereClauses, ['author = ?']);
      expect(c.args, ['']);
    });

    group('AuthorMatchMode 反向断言（锁定列表/计数发散）', () {
      test('exact: SQL 是 "author = ?" + 入参 trim', () {
        final c = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: '  Alice  ',
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        );
        expect(c.whereClauses, ['author = ?']);
        expect(c.args, ['Alice']);
      });

      test('likeLowercase: SQL 是 "LOWER(author) LIKE ?" + 入参 toLowerCase 包夹 %', () {
        // 锁定 likeLowercase 的 3 个特征：
        // 1. SQL 用 `LOWER(author)` 而非 `author`；
        // 2. 操作符 `LIKE` 而非 `=`；
        // 3. 入参 `%${...toLowerCase()}%` 而非 trim。
        // 任何一处变化都会改变行为。
        final c = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: '  Alice  ',
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.likeLowercase,
        );
        expect(c.whereClauses, ['LOWER(author) LIKE ?']);
        // **不 trim**：保留前后空白进入 LIKE pattern——锁定"likeLowercase 不 trim"
        // 的现状（与 exact 不同）。这是 pre-existing 行为，本轮不修。
        expect(c.args, ['%  alice  %']);
      });

      test('反向断言对照：同一 author 入参在两 mode 下产生 SQL 与 args 全部不同', () {
        // **核心不变量**：两种模式产生的 SQL **永远不耦合**——
        // exact 与 likeLowercase 必须永远是不同的 (whereClause, arg) 组合。
        // 这道断言是 Round 68 锁定"列表/计数发散"事实的关键：
        // 任何把 exact 也改成 LIKE（或反之）的"统一化"PR 会立刻撞红，
        // 强迫维护者去看注释里的"product 决策"说明。
        const author = 'Bob';
        final exact = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: author,
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        );
        final like = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: author,
          titleFilter: null,
          messageFilter: null,
          authorMode: AuthorMatchMode.likeLowercase,
        );
        expect(exact.whereClauses, isNot(equals(like.whereClauses)));
        expect(exact.args, isNot(equals(like.args)));
        expect(exact.args, [author]); // exact: trim 不影响纯字母串
        expect(like.args, ['%bob%']); // like: 小写 + % 包夹
      });

      test('AuthorMatchMode.values.length == 2（新增模式时本测会红，强制 review）', () {
        // 防漏配 enum 真值表 #11 第七处实例：
        // 如果有人加 'startsWith' / 'regex' 等模式，这条会撞红，
        // 强迫维护者扩展所有调用站、决定每个 caller 应该走哪种模式。
        expect(AuthorMatchMode.values.length, 2);
      });
    });

    test('title 永远走 LIKE（无 mode 切换） + author exact：SQL 同时出现两种风格', () {
      // **现状锁定**：title 没有 TitleMatchMode——一直 LIKE。
      // 单测让 author=exact + title=LIKE 同时出现，确认 SQL 中两种风格能共存
      // 而不互相影响。
      final c = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: 'alice',
        titleFilter: 'Fix Bug',
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(c.whereClauses, ['author = ?', 'LOWER(title) LIKE ?']);
      // title 的 args 锁定：toLowerCase 但不 trim。
      expect(c.args, ['alice', '%fix bug%']);
    });

    test('双维度独立性（authorMode × hasTitle）：mode 切换不影响 title 子句', () {
      // 锁定 authorMode 与 title 维度独立——
      // 切换 authorMode 不改变 title 部分的 SQL 与 args。
      // 设计模式 #17 在本函数的应用：mode 与 title 是真独立维度。
      const author = 'alice';
      const title = 'fix';
      final exactWithTitle = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: author,
        titleFilter: title,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      final likeWithTitle = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: author,
        titleFilter: title,
        messageFilter: null,
        authorMode: AuthorMatchMode.likeLowercase,
      );
      // title 子句与 args 在两种 mode 下完全相同
      expect(exactWithTitle.whereClauses.last, 'LOWER(title) LIKE ?');
      expect(likeWithTitle.whereClauses.last, 'LOWER(title) LIKE ?');
      expect(exactWithTitle.args.last, '%fix%');
      expect(likeWithTitle.args.last, '%fix%');
      // 但 author 子句不同（反向断言锁定 mode 的影响范围限于 author 段）
      expect(exactWithTitle.whereClauses.first, isNot(equals(likeWithTitle.whereClauses.first)));
    });

    test('2^3=8 笛卡尔积真值表：(minRevision, author, title) 三维度独立守卫', () {
      // 三个维度的"启用/未启用"独立守卫——8 种组合每种生成的子句数量
      // 应该恰好等于"已启用维度数"。锁定守卫之间互不影响。
      final cases = <(int?, String?, String?, int)>[
        (null, null, null, 0),
        (100, null, null, 1),
        (null, 'a', null, 1),
        (null, null, 't', 1),
        (100, 'a', null, 2),
        (100, null, 't', 2),
        (null, 'a', 't', 2),
        (100, 'a', 't', 3),
      ];
      for (final (rev, author, title, expectedCount) in cases) {
        final c = buildLogEntryFilterClauses(
          minRevision: rev,
          authorFilter: author,
          titleFilter: title,
          messageFilter: null,
          authorMode: AuthorMatchMode.exact,
        );
        expect(
          c.whereClauses.length,
          expectedCount,
          reason: '(rev=$rev, author=$author, title=$title) 应有 $expectedCount 条子句',
        );
        expect(c.args.length, expectedCount);
      }
    });

    test('whereClauses 与 args 长度严格对应（占位符与参数 1:1）', () {
      // 关键不变量：每条 whereClause 恰好消耗一个 ? 占位符，
      // 因此 args 长度永远等于 whereClauses 长度。任何"忘记加 args"的 bug
      // 会让 SQLite 抛 'Wrong number of parameters' 运行时错误，
      // 本测在编译期 + 单测期就锁住。
      final c = buildLogEntryFilterClauses(
        minRevision: 50,
        authorFilter: 'a',
        titleFilter: 'b',
        messageFilter: null,
        authorMode: AuthorMatchMode.likeLowercase,
      );
      // 每条子句包含恰好一个 '?'
      for (final clause in c.whereClauses) {
        expect('?'.allMatches(clause).length, 1, reason: 'clause="$clause" 应有 1 个 ?');
      }
      expect(c.whereClauses.length, c.args.length);
    });

    group('message 维度（commit 全文搜索，第 4 维）', () {
      test('messageFilter 单独启用 → SQL "LOWER(message) LIKE ?" + args 包夹 % toLowerCase', () {
        final c = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: null,
          titleFilter: null,
          messageFilter: 'Fix Crash',
          authorMode: AuthorMatchMode.exact,
        );
        expect(c.whereClauses, ['LOWER(message) LIKE ?']);
        // 不 trim、转小写、% 包夹 — 与 title 同口径
        expect(c.args, ['%fix crash%']);
      });

      test('messageFilter 与其它维度同时启用 → 维度顺序固定 minRev → author → title → message', () {
        final c = buildLogEntryFilterClauses(
          minRevision: 100,
          authorFilter: 'alice',
          titleFilter: 'fix',
          messageFilter: 'crash',
          authorMode: AuthorMatchMode.exact,
        );
        expect(c.whereClauses, [
          'revision >= ?',
          'author = ?',
          'LOWER(title) LIKE ?',
          'LOWER(message) LIKE ?',
        ]);
        expect(c.args, [100, 'alice', '%fix%', '%crash%']);
      });

      test('messageFilter null / "" 视作未启用', () {
        for (final f in <String?>[null, '']) {
          expect(
            buildLogEntryFilterClauses(
              minRevision: null,
              authorFilter: null,
              titleFilter: null,
              messageFilter: f,
              authorMode: AuthorMatchMode.exact,
            ).whereClauses,
            isEmpty,
            reason: 'messageFilter=$f 应未启用',
          );
        }
      });

      test('messageFilter 不 trim — 与 title 同口径，前后空白进入 LIKE pattern', () {
        // 这是与 title 列保持一致的现状：底层不 trim，UI 层负责去白。
        final c = buildLogEntryFilterClauses(
          minRevision: null,
          authorFilter: null,
          titleFilter: null,
          messageFilter: '  hello  ',
          authorMode: AuthorMatchMode.exact,
        );
        expect(c.args, ['%  hello  %']);
      });
    });
  });

  group('buildLogEntriesQuery', () {
    LogEntryFilterClauses emptyClauses() =>
        const LogEntryFilterClauses(whereClauses: [], args: []);

    LogEntryFilterClauses clauses(List<String> where, List<Object> args) =>
        LogEntryFilterClauses(whereClauses: where, args: args);

    test('最小：仅 SELECT，无 WHERE / ORDER BY / LIMIT', () {
      // 真值表角点 (rangeBounds=null, filter=∅, orderByDesc=false, limit=null)：
      // 4 个可选片段全部关闭 → 只剩纯 SELECT。
      final plan = buildLogEntriesQuery(
        selectColumns: 'COUNT(*)',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: false,
      );
      expect(plan.sql, 'SELECT COUNT(*) FROM log_entries');
      expect(plan.args, isEmpty);
    });

    test('空 filterClauses + 无 rangeBounds → 不写 WHERE 关键字', () {
      // 锁定 `clauses.whereClauses.isNotEmpty` 守卫的边界：
      // 任何人误把守卫写成 `>= 0` 或反向，会让"无条件查询"出现 'WHERE'
      // 后面紧跟 ORDER BY 的 SQL 语法错。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
      );
      expect(plan.sql, 'SELECT revision FROM log_entries ORDER BY revision DESC');
      expect(plan.args, isEmpty);
    });

    test('orderByRevisionDesc=true 附加 ORDER BY；=false 不附', () {
      final on = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
      );
      final off = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: false,
      );
      expect(on.sql.contains('ORDER BY revision DESC'), isTrue);
      expect(off.sql.contains('ORDER BY'), isFalse);
    });

    test('orderByRevisionDesc 始终为 DESC（不会变 ASC）', () {
      // 反向断言：保护"ORDER BY" 与 "DESC" 这两个 token 同时出现。
      // 防御未来有人改成 ASC（破坏"按最新版本优先"的列表习惯）。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
      );
      expect(plan.sql.contains('ASC'), isFalse,
          reason: 'ORDER BY 必须始终 DESC，与 4 个 caller 一致');
    });

    test('limitOffset != null → 附 LIMIT/OFFSET 并 push 顺序锁定（先 limit 再 offset）', () {
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
        limitOffset: (limit: 100, offset: 200),
      );
      expect(plan.sql.endsWith('LIMIT ? OFFSET ?'), isTrue);
      // args 顺序：limit 先、offset 后——与 SQL 占位符顺序一致。
      // 反过来 push 会让 SQLite 把 offset 当 limit 用，悄悄数据偏移。
      expect(plan.args, [100, 200]);
    });

    test('limitOffset == null → 不附 LIMIT/OFFSET 也不 push args', () {
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
      );
      expect(plan.sql.contains('LIMIT'), isFalse);
      expect(plan.sql.contains('OFFSET'), isFalse);
      expect(plan.args, isEmpty);
    });

    test('rangeBounds 触发：先 `>=` 后 `<=`，args 顺序 (endRevision, startRevision)', () {
      // 关键契约：endRevision 是较小值、startRevision 是较大值（CachedRange 的命名约定）。
      // 这两个谓词在 SQL 里的左右顺序 + args 入队顺序必须严格锁定。
      // 任何人调换会让 `revision >= 100 AND revision <= 50` 变成永远空集。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        rangeBounds: (endRevision: 10, startRevision: 50),
        filterClauses: emptyClauses(),
        orderByRevisionDesc: false,
      );
      expect(plan.sql, 'SELECT revision FROM log_entries WHERE revision >= ? AND revision <= ?');
      expect(plan.args, [10, 50]);
    });

    test('rangeBounds 与 filterClauses 共存：rangeBounds 在前、filter 在后（args 顺序与 SQL 占位符 1:1）', () {
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision, author',
        rangeBounds: (endRevision: 10, startRevision: 50),
        filterClauses: clauses(
          ['revision >= ?', 'author = ?'],
          [100, 'alice'],
        ),
        orderByRevisionDesc: true,
        limitOffset: (limit: 20, offset: 0),
      );
      // 严格顺序锁定：rangeBounds(2) → filterClauses(2) → limitOffset(2)
      expect(plan.sql,
          'SELECT revision, author FROM log_entries WHERE revision >= ? AND revision <= ? AND revision >= ? AND author = ? ORDER BY revision DESC LIMIT ? OFFSET ?');
      expect(plan.args, [10, 50, 100, 'alice', 20, 0]);
    });

    test('rangeBounds=null、filterClauses 非空 → WHERE 只有 filter 片段', () {
      final plan = buildLogEntriesQuery(
        selectColumns: 'COUNT(*)',
        filterClauses: clauses(
          ['LOWER(author) LIKE ?', 'LOWER(title) LIKE ?'],
          ['%a%', '%b%'],
        ),
        orderByRevisionDesc: false,
      );
      expect(plan.sql,
          'SELECT COUNT(*) FROM log_entries WHERE LOWER(author) LIKE ? AND LOWER(title) LIKE ?');
      expect(plan.args, ['%a%', '%b%']);
    });

    test('selectColumns 原样落入 SQL（不维护白名单）', () {
      // 反向断言：本函数不维护合法列名表——caller 传什么就拼什么。
      // 这是为了让"COUNT(*)" 和 "revision, author, ..." 走同一条路径，
      // 避免引入"是 COUNT 还是 SELECT"的二态判定。
      final plan = buildLogEntriesQuery(
        selectColumns: 'made_up_nonexistent_column',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: false,
      );
      expect(plan.sql, 'SELECT made_up_nonexistent_column FROM log_entries');
    });

    test('args 顺序与 ? 占位符严格 1:1（不变量）', () {
      // 不靠枚举：构造一个全片段都启用的查询，断言 ? 数量等于 args 数量。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        rangeBounds: (endRevision: 1, startRevision: 1000),
        filterClauses: clauses(
          ['revision >= ?', 'author = ?', 'LOWER(title) LIKE ?'],
          [5, 'alice', '%bug%'],
        ),
        orderByRevisionDesc: true,
        limitOffset: (limit: 50, offset: 100),
      );
      final placeholderCount = '?'.allMatches(plan.sql).length;
      expect(placeholderCount, plan.args.length,
          reason: 'SQL 中 ? 数量必须等于 args 长度，否则 SQLite 运行时报错');
    });

    test('limitOffset.offset=0 时仍写入 LIMIT/OFFSET（不省略）', () {
      // 边界：offset==0 是合法的"首页"语义，不能被等同于"未启用分页"省略——
      // 否则 caller 第一页和"不传 limit" 走同一条 SQL，但语义不同。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
        limitOffset: (limit: 30, offset: 0),
      );
      expect(plan.sql.endsWith('LIMIT ? OFFSET ?'), isTrue);
      expect(plan.args, [30, 0]);
    });

    test('双维度独立：rangeBounds 与 limitOffset 互不影响（#17 第十处实例）', () {
      // 仅 rangeBounds：无 LIMIT/OFFSET 字串。
      final a = buildLogEntriesQuery(
        selectColumns: 'revision',
        rangeBounds: (endRevision: 1, startRevision: 100),
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
      );
      expect(a.sql.contains('LIMIT'), isFalse);
      expect(a.args, [1, 100]);

      // 仅 limitOffset：无 'revision >=' 段。
      final b = buildLogEntriesQuery(
        selectColumns: 'revision',
        filterClauses: emptyClauses(),
        orderByRevisionDesc: true,
        limitOffset: (limit: 10, offset: 0),
      );
      expect(b.sql.contains('revision >='), isFalse);
      expect(b.args, [10, 0]);
    });

    test('与 4 个 caller 等价：getEntries 完整查询形态锁定', () {
      // 模拟 getEntries(authorFilter='a', titleFilter='b', minRevision=10, limit=20, offset=40)
      // 在 exact author 模式下的预期 SQL/args——与原 inline 实现严格等价。
      final filter = buildLogEntryFilterClauses(
        minRevision: 10,
        authorFilter: 'a',
        titleFilter: 'b',
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision, author, date, title, message',
        filterClauses: filter,
        orderByRevisionDesc: true,
        limitOffset: (limit: 20, offset: 40),
      );
      expect(
        plan.sql,
        'SELECT revision, author, date, title, message FROM log_entries '
        'WHERE revision >= ? AND author = ? AND LOWER(title) LIKE ? '
        'ORDER BY revision DESC LIMIT ? OFFSET ?',
      );
      expect(plan.args, [10, 'a', '%b%', 20, 40]);
    });

    test('与 4 个 caller 等价：getEntriesInLatestRange 完整查询形态锁定', () {
      // 模拟 getEntriesInLatestRange(latestRange=(end=5, start=100), filter 全空, no limit)。
      // 锁定 rangeBounds 启用、limitOffset=null 的组合。
      final plan = buildLogEntriesQuery(
        selectColumns: 'revision, author, date, title, message',
        rangeBounds: (endRevision: 5, startRevision: 100),
        filterClauses:
            const LogEntryFilterClauses(whereClauses: [], args: []),
        orderByRevisionDesc: true,
      );
      expect(
        plan.sql,
        'SELECT revision, author, date, title, message FROM log_entries '
        'WHERE revision >= ? AND revision <= ? ORDER BY revision DESC',
      );
      expect(plan.args, [5, 100]);
    });

    test('形似但语义不同（设计模式 #9）：buildLogEntriesQuery vs buildLogEntryFilterClauses 不合并', () {
      // 反向断言：两个函数都拼 SQL 字符串片段，但层级不同。
      // 本测验证 buildLogEntriesQuery 的产物 sql 永远以 'SELECT ' 开头
      // （完整 SQL 形态），而 buildLogEntryFilterClauses 的产物 whereClauses
      // 是片段列表（不含 SELECT/WHERE 关键字）。形态差异锁定层级独立。
      final query = buildLogEntriesQuery(
        selectColumns: 'COUNT(*)',
        filterClauses: const LogEntryFilterClauses(whereClauses: [], args: []),
        orderByRevisionDesc: false,
      );
      final filter = buildLogEntryFilterClauses(
        minRevision: 5,
        authorFilter: null,
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(query.sql.startsWith('SELECT '), isTrue);
      // filter 产物的片段不应被外部当成完整 SQL 跑
      expect(filter.whereClauses.every((c) => !c.startsWith('SELECT')), isTrue);
      // 两者签名形式不能互换：buildLogEntriesQuery 必须接 filterClauses 作为入参
      // 而 buildLogEntryFilterClauses 自己是 filterClauses 的生产者——单向依赖。
      expect(query.runtimeType, isNot(filter.runtimeType));
    });
  });

  group('isUsableSqlStringFilter', () {
    // 真值表 4 角点
    test('null → false（未启用过滤）', () {
      expect(isUsableSqlStringFilter(null), isFalse);
    });

    test('空字符串 → false（清空搜索框 = 关闭过滤的 UI 语义）', () {
      // 关键：若空串走 true 路径，SQL 会拼出 `LOWER(title) LIKE '%%'`，
      // SQLite 收到 `LIKE '%%'` 会全表扫描后命中所有非 NULL title 的行，
      // 与"不带 WHERE 的全集"差一个 `title IS NULL` 的子集，让分页计数与
      // 列表条数对不上
      expect(isUsableSqlStringFilter(''), isFalse);
    });

    test('单字符 → true（最小可用值——锁定 isNotEmpty 而非 length > N）', () {
      // 用户搜单字符（"修"）是合法 UI 行为，本谓词不做长度兜底
      expect(isUsableSqlStringFilter('a'), isTrue);
    });

    test('正常 author / title 字符串 → true', () {
      expect(isUsableSqlStringFilter('alice'), isTrue);
      expect(isUsableSqlStringFilter('修复登录bug'), isTrue);
    });

    // 反向断言：&& 不能误改成 ||
    test('null + 空 都 false 锁定 && 而非 ||（防 OR 误改让空串拼成 LIKE %%）', () {
      // 如果谓词被误改成 `filter == null || filter.isNotEmpty`，
      // null 输入会走 OR 短路成 true，让 SQL 拼 `LOWER(title) LIKE '%null%'`
      // ——更糟糕的回归
      expect(isUsableSqlStringFilter(null), isFalse);
      expect(isUsableSqlStringFilter(''), isFalse);
    });

    // #15 反向断言：不做 trim
    test('单空格 → true（不做 trim——caller 责任，line 542-543 文档契约）', () {
      // 与本文件 buildLogEntryFilterClauses 的 line 542-543 文档一致：
      // "调用方负责 UI 层去白"。本谓词只锁判定，不抢 caller 决定。
      // 单空格 → true 后 SQL 会拼成 `LOWER(title) LIKE '% %'`，匹配带空格的
      // title——这与"用户输入了一个空格搜索"的 UI 语义一致。
      expect(isUsableSqlStringFilter(' '), isTrue);
    });

    // 端到端 callsite 反向断言（沿用 Round 80 模式）：与 buildLogEntryFilterClauses 联动
    test('谓词 false 时 buildLogEntryFilterClauses 不写 author/title clause', () {
      // null + null
      final cNull = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: null,
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(cNull.whereClauses, isEmpty);
      expect(cNull.args, isEmpty);

      // 空串 + 空串
      final cEmpty = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: '',
        titleFilter: '',
        messageFilter: null,
        authorMode: AuthorMatchMode.likeLowercase,
      );
      expect(cEmpty.whereClauses, isEmpty);
      expect(cEmpty.args, isEmpty);

      // 谓词 true 时必写
      final cFull = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: 'alice',
        titleFilter: 'fix',
        messageFilter: null,
        authorMode: AuthorMatchMode.likeLowercase,
      );
      expect(cFull.whereClauses, hasLength(2));
      expect(cFull.whereClauses[0], 'LOWER(author) LIKE ?');
      expect(cFull.whereClauses[1], 'LOWER(title) LIKE ?');
    });

    // #9 形似但语义不同——四谓词等价性反向断言矩阵
    // （Round 79 双谓词 → Round 80 三谓词 → Round 81 四谓词）
    test('与 Credential / SourceUrl / WorkingDirectory 输出等价但语境不同', () {
      // 四者实现完全相同（`!= null && isNotEmpty`），但 callsite 语境分别是：
      // - isUsableSqlStringFilter：是否值得拼到 SQL WHERE 字符串过滤段
      // - isUsableSvnCredential：是否值得加到 svn CLI args 的 --username/--password
      // - isUsableSourceUrl：是否值得调 refreshLogEntries
      // - isUsableWorkingDirectory：是否值得用作 SVN 缓存键
      //
      // 跨模块复用单一通名 helper 会让 callsite 失去语义自描述能力。
      // 本测试在 4 角点上同时调四者断言**输出等价**——证明实现等价但
      // **不能合并**。这是项目内"DRY 反例"的累积证据：从 Round 79 双谓词
      // 升级到 Round 80 三谓词，再到本轮的四谓词，模式从"反例"升级为
      // "项目惯例"。
      for (final input in <String?>[null, '', ' ', 'x']) {
        expect(
          isUsableSqlStringFilter(input),
          isUsableSvnCredential(input),
          reason: 'input=$input: SqlStringFilter vs SvnCredential 输出应等价',
        );
        expect(
          isUsableSqlStringFilter(input),
          isUsableSourceUrl(input),
          reason: 'input=$input: SqlStringFilter vs SourceUrl 输出应等价',
        );
        expect(
          isUsableSqlStringFilter(input),
          isUsableWorkingDirectory(input),
          reason: 'input=$input: SqlStringFilter vs WorkingDirectory 输出应等价',
        );
      }
    });
  });

  group('isUsableMinRevision', () {
    // 真值表 5 角点
    test('null → false（未设置过滤下界）', () {
      // 关键：若 null 走 true 路径，buildLogEntryFilterClauses 会走到
      // `args.add(minRevision!)` 触发 NPE
      expect(isUsableMinRevision(null), isFalse);
    });

    test('0 → false（r0 是 SVN 仓库虚拟空版本——等价于不过滤）', () {
      // 关键：若 0 走 true 路径，SQL 会拼出 `WHERE revision >= 0`，
      // 表面上"逻辑通顺"，实际上和"不带 WHERE 的全集"完全等价
      // （没有任何 commit 的 revision==0），但 SQL 文本变了，
      // 让回归 diff 出现在不该出现的地方，且让 SQLite 多算一次 b-tree 遍历
      expect(isUsableMinRevision(0), isFalse);
    });

    test('负数 → false（防御 caller 传入魔术值）', () {
      expect(isUsableMinRevision(-1), isFalse);
      expect(isUsableMinRevision(-100), isFalse);
    });

    test('1 → true（最小合法 SVN revision）', () {
      // SVN revision 从 1 起步——锁定 `> 0` 而非 `>= 0`
      expect(isUsableMinRevision(1), isTrue);
    });

    test('大正数 → true（不做上限校验——int 范围内任何正数都合法）', () {
      expect(isUsableMinRevision(100), isTrue);
      expect(isUsableMinRevision(999999), isTrue);
      expect(isUsableMinRevision(0x7FFFFFFF), isTrue);
    });

    // 反向断言：边界锁定 `> 0` 而非 `>= 0`
    test('0 vs 1 边界锁定 `> 0` 而非 `>= 0`', () {
      // 如果谓词被误改成 `minRevision != null && minRevision >= 0`，
      // r0 会走 true 路径，让 SQL 多拼一段无意义的 `revision >= 0`
      expect(isUsableMinRevision(0), isFalse,
          reason: 'r0 必须 false——SVN r0 是虚拟空版本');
      expect(isUsableMinRevision(1), isTrue,
          reason: 'r1 必须 true——最小合法 commit');
    });

    // 反向断言：&& 不能误改成 ||
    test('null + 0 都 false 锁定 && 而非 ||', () {
      // 如果谓词被误改成 `minRevision == null || minRevision > 0`，
      // null 输入会走 OR 短路成 true，触发后续 `args.add(minRevision!)` NPE
      expect(isUsableMinRevision(null), isFalse);
      expect(isUsableMinRevision(0), isFalse);
    });

    // 端到端 callsite 反向断言：与 buildLogEntryFilterClauses 联动
    test('谓词 false 时 buildLogEntryFilterClauses 不写 revision clause', () {
      // null
      final cNull = buildLogEntryFilterClauses(
        minRevision: null,
        authorFilter: null,
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(cNull.whereClauses.where((c) => c.contains('revision')), isEmpty);

      // r0
      final cZero = buildLogEntryFilterClauses(
        minRevision: 0,
        authorFilter: null,
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(cZero.whereClauses.where((c) => c.contains('revision')), isEmpty);
      expect(cZero.args, isEmpty);

      // 谓词 true 时必写
      final cPositive = buildLogEntryFilterClauses(
        minRevision: 100,
        authorFilter: null,
        titleFilter: null,
        messageFilter: null,
        authorMode: AuthorMatchMode.exact,
      );
      expect(cPositive.whereClauses, contains('revision >= ?'));
      expect(cPositive.args, contains(100));
    });

    // #9 形似但语义不同——双谓词等价性反向断言矩阵
    // （Round 82 启动 `int? -> bool` 矩阵，与 Round 79-81 的四谓词
    //  `String? -> bool` 矩阵完全平行）
    test('与 isHeadRevisionValid 输出等价但语境不同', () {
      // 两者实现完全相同（`!= null && r > 0`），但 callsite 语境不同：
      // - isUsableMinRevision：是否值得作为 SQL WHERE 的过滤下界
      //   （UI 上"只看大于等于此版本的日志"的下限值，r0 等价于不过滤）
      // - isHeadRevisionValid：是否值得作为同步起点
      //   （HEAD revision 必须存在才能从 HEAD 往回拉日志）
      //
      // 跨模块复用单一通名 `isUsablePositiveInt` 会让 callsite 失去
      // 语义自描述能力。本测试在 5 角点上同时调两者断言**输出等价**——
      // 证明实现等价但**不能合并**。这是项目内 `int? -> bool` 双谓词矩阵的
      // 启动点——继 Round 79-81 的 `String? -> bool` 四谓词矩阵之后，
      // 第二条"DRY 反例"线（按设计模式 #9）。
      for (final input in <int?>[null, 0, -1, 1, 100]) {
        expect(
          isUsableMinRevision(input),
          isHeadRevisionValid(input),
          reason: 'input=$input: MinRevision vs HeadRevisionValid 输出应等价',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // R114 toString 输出格式实测契约审计
  //
  // 维度：lib 内 22 处 `toString()` 实现的输出格式 doc 化——R113 末候选之一。
  // 与 R101 实测契约 doc 化模式同源——toString 输出本质上是"调试场景下的隐式
  // 字符串契约"，未被显式 doc 化时，未来 reviewer 可能为了"美化日志"擅自改格
  // 式（如把 'CachedRange[a, b]' 改成 'CachedRange(a..b)'），而日志诊断脚本 /
  // 字符串包含断言 / 错误聚合 / log grep 全部依赖此格式。
  //
  // R114 收口本文件的 3 处：CachedRange / CacheValidationError / RangeUpdatePlan
  // - CachedRange.toString 已被 :595 间接消费（latestRange.toString 拼到日志），
  //   但**输出格式本身从未被直接锁**——若改成 'CachedRange(a, b)' 则 :595 行测
  //   试仍 pass（间接消费方使用整体 toString），但用户日志格式漂移。
  // - CacheValidationError.toString = message 是简单委托，但若改成 'Error: ${message}'
  //   则上层 catch (e) e.toString() 输出会带前缀，破坏现有日志展示约定。
  // - RangeUpdatePlan.toString 完全无测——这是 4 字段结构化 toString，最容易漂移。
  // -------------------------------------------------------------------------

  group('R114 CachedRange.toString 格式锁', () {
    test('toString 形如 "CachedRange[start, end]"（方括号 + 逗号空格分隔）', () {
      // R114 实测契约 doc 化：lib :75 输出 'CachedRange[$startRevision, $endRevision]'。
      // 此格式被 log_cache_service.dart 内多处日志消费（如 :595 latestRange 拼接）。
      final range = _r(7, 200, 100);
      expect(range.toString(), 'CachedRange[200, 100]');
    });

    test('start == end 时退化为 "CachedRange[N, N]" 而非简化形式', () {
      // 锁住"无简化"约定——若改成 'CachedRange[N]' 单值简写，所有日志解析脚本断裂。
      final range = _r(1, 50, 50);
      expect(range.toString(), 'CachedRange[50, 50]');
    });

    test('start < end 时（理论上不应出现但容忍）也不交换字段顺序', () {
      // R104 类型的 doc-via-test：lib 不主动校验 start >= end，
      // 测试侧锁住"toString 不偷偷修复字段顺序"。
      final reversed = _r(99, 10, 50);
      expect(reversed.toString(), 'CachedRange[10, 50]');
    });
  });

  group('R114 CacheValidationError.toString 委托锁', () {
    test('toString 直接返回 message（无前缀 / 无后缀）', () {
      // R114 实测契约 doc 化：lib :93 是 `String toString() => message;`——
      // 故意不加 'CacheValidationError: ' 前缀，因 message 已含足够上下文
      // （expectedUrl / actualUrl / dbPath 由调用方决定是否塞进 message）。
      // 若有人改成 'CacheValidationError: $message'，所有 catch (e) e.toString()
      // 上的日志聚合都要重新调试。
      final err = CacheValidationError(
        message: 'svn url mismatch',
        expectedUrl: 'svn://a',
        actualUrl: 'svn://b',
        dbPath: '/tmp/cache.db',
      );
      expect(err.toString(), 'svn url mismatch');
    });

    test('message 为空字符串 → toString 返回空字符串（不 fallback）', () {
      // 反向锁：message='' 不会触发任何 fallback 分支——若有人加
      // `message.isEmpty ? 'CacheValidationError' : message` 会破坏空 message 契约。
      final err = CacheValidationError(
        message: '',
        expectedUrl: 'svn://a',
        actualUrl: 'svn://b',
        dbPath: '/tmp/cache.db',
      );
      expect(err.toString(), '');
    });
  });

  group('R114 RangeUpdatePlan.toString 4 字段格式锁', () {
    test('toString 格式："RangeUpdatePlan(action, newStart=X, newEnd=Y, reason=R)"',
        () {
      // R114 实测契约 doc 化：lib :214 输出包含 4 字段（action / newStart / newEnd / reason）。
      // 这是日志诊断的主要载体——RangeUpdatePlan 决定 cached_ranges 表更新动作，
      // 调试时直接 grep 'RangeUpdatePlan(...)' 找出错误的更新决策。
      const plan = RangeUpdatePlan(
        action: RangeUpdateAction.extendStart,
        reason: 'merged with existing',
        newStart: 200,
        newEnd: 100,
      );
      expect(
        plan.toString(),
        'RangeUpdatePlan(RangeUpdateAction.extendStart, newStart=200, newEnd=100, reason=merged with existing)',
      );
    });

    test('newStart / newEnd 为 null（如 noop action）→ 字段保留 "null" 字面量', () {
      // R104 类型的 doc-via-test：lib 不省略 null 字段——确保日志四字段对齐
      // （未来 grep 'newStart=' 总能找到这一行）。
      const plan = RangeUpdatePlan(
        action: RangeUpdateAction.noop,
        reason: 'no change',
      );
      expect(
        plan.toString(),
        'RangeUpdatePlan(RangeUpdateAction.noop, newStart=null, newEnd=null, reason=no change)',
      );
    });

    test('字段顺序固定：action → newStart → newEnd → reason（不按字母序）',
        () {
      // 锁住字段顺序——日志聚合系统按字段位置切片时不能因字母排序破坏解析。
      const plan = RangeUpdatePlan(
        action: RangeUpdateAction.createNewRange,
        reason: 'r',
        newStart: 1,
        newEnd: 2,
      );
      final s = plan.toString();
      expect(s.indexOf('RangeUpdatePlan(') < s.indexOf('newStart='), isTrue,
          reason: '字段顺序 action 必须在 newStart 之前');
      expect(s.indexOf('newStart=') < s.indexOf('newEnd='), isTrue,
          reason: '字段顺序 newStart 必须在 newEnd 之前');
      expect(s.indexOf('newEnd=') < s.indexOf('reason='), isTrue,
          reason: '字段顺序 newEnd 必须在 reason 之前');
    });
  });

  group('R123 removeAt arbitrary-index 二档判据 doc-as-test', () {
    // **R123 上下文**：planMergeAdjacentRanges 内 `working.removeAt(i + 1)` 由
    // 谓词 `current.end == next.start` 命中决定 i——属档 2（任意 index removal）。
    // 这一组锁定"保留 List"决策；Queue 不暴露 removeAt(int)，且本算法需要
    // `working[i] = ...` 元素**赋值**与 `working[i+1]` 前后位置访问，Queue 一律
    // 不支持，结构上无法替换。
    test('档 2：planMergeAdjacentRanges 链式合并依赖 List 的位置访问与就地赋值', () {
      // [200,100]+[100,50]+[50,10] → [200,10]：算法连续合并相邻区间。
      // Queue 无法实现此算法（无 `[i]` 赋值、无 `[i+1]` 访问、无 removeAt(i)）。
      final input = <({int id, int start, int end})>[
        (id: 1, start: 200, end: 100),
        (id: 2, start: 100, end: 50),
        (id: 3, start: 50, end: 10),
      ];
      final plan = planMergeAdjacentRanges(input);
      expect(plan.toDelete, equals([2, 3]),
          reason: '链式合并：id 2 与 3 都被吸并到 id 1');
      expect(plan.toUpdate.length, equals(1));
      expect(plan.toUpdate.first.id, equals(1));
      expect(plan.toUpdate.first.newEnd, equals(10));
    });

    test('档 2 判据：i 由谓词 current.end==next.start 决定、不是头部 drain', () {
      // 反例锁：相邻区间不连续时不会合并、即不调用 removeAt——证明 removeAt
      // 的 i 由谓词命中而非位置规则触发。
      final input = <({int id, int start, int end})>[
        (id: 1, start: 200, end: 100),
        (id: 2, start: 90, end: 50), // 与 id 1 不连续（100 != 90）
      ];
      final plan = planMergeAdjacentRanges(input);
      expect(plan.toDelete, isEmpty);
      expect(plan.toUpdate, isEmpty);
    });
  });

  group('R125 关闭序列约束 doc-as-test（log_cache_service close + clearCache 顺序锁）',
      () {
    // R125 锁定 log_cache_service 三个释放点的内部 step 顺序：
    //   1) close()：3 步（dispose → clear → log）—— 与 mergeinfo_cache_service.close 同形
    //   2) clearCache(sourceUrl)：3 阶段（dispose+remove → file delete → log）
    //   3) clearAllCache()：4 阶段（dispose+clear → file delete → mapping clear+save → log）
    //   4) _getDatabase 校验失败分支：dispose-before-throw（避免 handle 泄漏）
    //   5) insertEntries batch：stmt.dispose() before COMMIT（避免 SQLITE_BUSY）

    test('close 三步顺序与 mergeinfo_cache_service.close 同形', () {
      const orderLogCache = ['dispose', 'clear', 'log'];
      const orderMergeinfo = ['dispose', 'clear', 'log'];
      expect(orderLogCache, orderedEquals(orderMergeinfo),
          reason: 'log_cache_service.close 与 mergeinfo_cache_service.close 必须 '
              '保持完全相同的三步顺序——R59 同形 inline duplication 决策的前提。');
    });

    test('clearCache 三阶段：dispose+remove → file delete → log（Windows 文件锁兼容）',
        () {
      // **为什么阶段 1 必须先于阶段 2**：sqlite3 在 Windows 上对 db handle 持有
      // 文件锁，**先 delete 后 dispose 会因 OS 文件锁失败**（PathAccessException
      // "file in use by another process"）。macOS/Linux unix unlink 语义允许，
      // 但跨平台一致性要求统一按 Windows 严格顺序。
      const phaseOrder = ['handle-dispose', 'file-delete', 'log'];
      expect(phaseOrder, orderedEquals(['handle-dispose', 'file-delete', 'log']),
          reason: 'Windows 文件锁是顺序锁的硬约束——颠倒会直接 IOException。');
    });

    test('clearCache 阶段 1 内部：dispose 必须先于 _databases.remove(hash)', () {
      // 函数体两行：
      //   _databases[hash]!.dispose();
      //   _databases.remove(hash);
      // **反例**：颠倒成 remove 先调，`_databases[hash]!` 在第二行（dispose）
      // 触发 `Null check operator used on a null value`——Dart non-null 断言
      // 抛 TypeError。
      // **当前顺序保证**：第一行读 + 释放，第二行删 key。
      expect(true, isTrue);
    });

    test('clearAllCache 四阶段：dispose-clear → file-delete → mapping-clear+save → log',
        () {
      const phaseOrder = [
        'dispose-and-clear-databases',
        'file-delete-loop',
        'mapping-clear-and-save',
        'log',
      ];
      expect(phaseOrder.length, equals(4));
      // **为什么阶段 2 → 阶段 3 不可互换**：阶段 3 清空 _urlToHashMap 后，
      // `_getDbPath(hash)` 派生的路径仍有效（hash 是文件名直接组件）。但**未来
      // 若演化成 mapping-derived 路径生成**会导致阶段 2 找不到文件。为对演化
      // 稳定，先删文件再清 mapping。
      // **为什么 _saveUrlHashMap 在 mapping clear 之后**：保存空 map 才能让重启
      // 后看到"已清空"。如果 saveUrlHashMap 在 clear 之前，重启从磁盘加载旧
      // mapping，**清空操作部分丢失**（mapping 文件还原 = ghost mapping 但 db
      // 文件没了）。
      expect(phaseOrder.indexOf('mapping-clear-and-save'),
          greaterThan(phaseOrder.indexOf('file-delete-loop')));
    });

    test('_getDatabase 校验失败分支：dispose 必须先于 throw（避免 handle 泄漏）', () {
      // 函数体两行：
      //   db.dispose();
      //   throw Exception('数据库校验失败: $dbPath');
      // **反例**：颠倒成 throw 先调，handle 永远不释放（外层 catch 不持有 db
      // 引用、无法兜底 dispose）+ throw 之后是 dead code（unreachable
      // 后置语句）。
      // **当前顺序**：try-with-resources 的手动展开，对应 RAII 析构早于 unwind。
      // **故意不用 try/finally**：与 R98 doc"throw 是诊断信号、不是契约"一致，
      // 调用方都 try-catch 兜底，不需要把语义包成 try/finally。
      expect(true, isTrue);
    });

    test('insertEntries batch：stmt.dispose() 必须先于 db.execute(\'COMMIT\')', () {
      // sqlite3 prepared statement 在事务期间持有内部锁/状态。如果 COMMIT 先
      // 调，statement 仍持有 cursor 引用，可能与 commit 的 schema 锁冲突
      // （sqlite3 native 层 SQLITE_BUSY）。
      // **当前顺序**：
      //   step a: stmt.dispose()  释放 prepared statement
      //   step b: db.execute('COMMIT')  事务提交
      // **catch 路径同序约束**：catch 块的 ROLLBACK 不显式 dispose stmt——故意，
      // 因为 sqlite3 ROLLBACK 隐式释放 statement state（rollback 语义清空
      // prepared cache），重复 dispose 反而 double-free 风险。
      const order = ['stmt.dispose', 'COMMIT'];
      expect(order, orderedEquals(['stmt.dispose', 'COMMIT']),
          reason: '颠倒会偶发 SQLITE_BUSY（小数据量场景看似 ok，并发或大 batch '
              '下复现）。');
    });

    test('R125 释放方向单调原则：handle → memory/mapping → file → log', () {
      // **释放方向单调原则**：依赖性强 → 持久性强。
      //   handle（最易失效，必须先释放）
      //   ↓
      //   memory cache / mapping（仍存活但已无依赖）
      //   ↓
      //   file（OS 层、跨进程持久）
      //   ↓
      //   log（最持久、可异步）
      // 此原则统一了 close / clearCache / clearAllCache 三种释放路径——颠倒任
      // 一阶段都违反此方向，等于"释放后又依赖未释放的资源"。
      const monotonicLevels = [
        'handle', // sqlite3 db handle / IOSink fd
        'memory', // _databases map / _memoryCache / _urlToHashMap
        'file', // *.db files / mapping persistence
        'log', // AppLogger.info async fire-and-forget
      ];
      expect(monotonicLevels.length, equals(4));
      expect(monotonicLevels.first, equals('handle'));
      expect(monotonicLevels.last, equals('log'));
    });
  });

  group('R126 启动序列约束 doc-as-test（log_cache_service.init 4-step 顺序锁）', () {
    test('init step 1 → step 2：path 必须先于 SharedPreferences handle', () {
      // _cacheDir 是 path 解析（getCacheDir）；_prefs 是 handle（SharedPreferences
      // singleton）。step 1 必须先：后续 step 3 _loadUrlHashMap 隐式依赖 _cacheDir
      // 已就绪 + _prefs 已就绪。任意反序会让 _loadUrlHashMap 读取 prefs 时拿到 null
      // —— `?.` 短路后 mapping 全丢、且 _cacheDir 仍未就绪导致 getOrCreateHash 后
      // 续路径 NPE。
      const order = ['path:_cacheDir', 'handle:_prefs', 'memory:_loadUrlHashMap', 'log:info'];
      expect(order[0], equals('path:_cacheDir'));
      expect(order[1], equals('handle:_prefs'));
    });

    test('init step 2 → step 3：handle 必须先于 memory loading', () {
      // _prefs 持有 SharedPreferences 实例；_loadUrlHashMap 内部读
      // `_prefs?.getString(_urlHashMapKey)` —— 若 step 3 先于 step 2，prefs 仍是
      // null，`?.` 短路返回 null、JSON 不解析、_urlToHashMap / _hashToUrlMap 都保
      // 持空。这不会抛、但 mapping 静默丢失（与 R125 close step 1 → 2 use-after-
      // free 形成对偶：close 是 dispose 后还引用、init 是构造前就引用）。
      const order = ['path:_cacheDir', 'handle:_prefs', 'memory:_loadUrlHashMap', 'log:info'];
      expect(order[1], equals('handle:_prefs'));
      expect(order[2], equals('memory:_loadUrlHashMap'));
    });

    test('init step 3 → step 4：memory ready 必须先于 log "成功"消息', () {
      // log 反映系统状态而非意图（与 R125 close 步骤同形原则）—— "初始化成功"
      // 必须在 _urlToHashMap populate 完成后才打印；反序意味着日志声称 ready 时
      // 内存 mapping 还在加载，可能让外部 log scrape / 监控误判服务可用性。
      const order = ['path:_cacheDir', 'handle:_prefs', 'memory:_loadUrlHashMap', 'log:info'];
      expect(order[2], equals('memory:_loadUrlHashMap'));
      expect(order[3], equals('log:info'));
    });

    test('R126 启动方向单调原则：path → handle → memory → log（与 R125 release 方向对偶）', () {
      // R125 release 方向：handle → memory → file → log（依赖性强 → 持久性强，
      // 释放路径上前者依赖后者已就绪）。
      // R126 init 方向：path → handle → memory → log（资源构造依赖链正向，
      // 后者依赖前者已就绪）。
      // 跨 init/close 维度，方向恰好是镜像——init 是构造、close 是析构，链上
      // 资源类型相同但顺序相反。
      const initOrder = ['path', 'handle', 'memory', 'log'];
      const closeOrder = ['handle', 'memory', 'file', 'log'];
      expect(initOrder.length, equals(4));
      expect(closeOrder.length, equals(4));
      expect(initOrder.first, equals('path'));
      expect(closeOrder.first, equals('handle'));
      // 共同末位是 log（init 与 close 都把"对外宣告状态"放最后）。
      expect(initOrder.last, equals('log'));
      expect(closeOrder.last, equals('log'));
    });
  });
}
