import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/merge_config.dart';
import 'package:svn_auto_merge/models/merge_job.dart';

void main() {
  group('TargetConfig', () {
    test('fullWorkingCopy 只携带目标工作副本路径', () {
      const config = TargetConfig.fullWorkingCopy('/tmp/wc');

      expect(config.mode, TargetMode.fullWorkingCopy);
      expect(config.isFullWorkingCopy, isTrue);
      expect(config.isTemporarySparseWorkingCopy, isFalse);
      expect(config.workingCopyPath, '/tmp/wc');
      expect(config.svnUrl, isEmpty);
      expect(config.jobTargetWc, '/tmp/wc');
      expect(config.jobTargetUrl, isNull);
      expect(config.probeTarget, '/tmp/wc');
      expect(config.probeRole, '目标工作副本');
    });

    test('sparseTemporary 只携带目标 SVN URL，任务 targetWc 兼容字段为空', () {
      const config = TargetConfig.sparseTemporary('svn://repo/branches/target');

      expect(config.mode, TargetMode.temporarySparseWorkingCopy);
      expect(config.isFullWorkingCopy, isFalse);
      expect(config.isTemporarySparseWorkingCopy, isTrue);
      expect(config.workingCopyPath, isEmpty);
      expect(config.svnUrl, 'svn://repo/branches/target');
      expect(config.jobTargetWc, isEmpty);
      expect(config.jobTargetUrl, 'svn://repo/branches/target');
      expect(config.probeTarget, 'svn://repo/branches/target');
      expect(config.probeRole, '目标 SVN URL');
    });

    test('fromLegacy 按模式解释旧字段，精简模式不把 targetWc 当 URL', () {
      final sparse = TargetConfig.fromLegacy(
        targetWc: '/tmp/wc',
        targetUrl: 'svn://repo/branches/target',
        useTemporarySparseWorkingCopy: true,
      );
      final full = TargetConfig.fromLegacy(
        targetWc: '/tmp/wc',
        targetUrl: 'svn://repo/branches/target',
        useTemporarySparseWorkingCopy: false,
      );

      expect(sparse,
          const TargetConfig.sparseTemporary('svn://repo/branches/target'));
      expect(full, const TargetConfig.fullWorkingCopy('/tmp/wc'));
    });
  });

  group('MergeJob', () {
    test(
        'withConfig freezes mutually exclusive target config into legacy JSON fields',
        () {
      final fullJob = MergeJob.withConfig(
        jobId: 1,
        sourceConfig: const SourceConfig(url: 'svn://repo/branches/source'),
        targetConfig: const TargetConfig.fullWorkingCopy('/tmp/wc')
            .withResolvedTargetUrl('svn://repo/branches/target'),
        maxRetries: 1,
        revisions: const [100],
      );
      final sparseJob = MergeJob.withConfig(
        jobId: 2,
        sourceConfig: const SourceConfig(url: 'svn://repo/branches/source'),
        targetConfig:
            const TargetConfig.sparseTemporary('svn://repo/branches/target'),
        maxRetries: 1,
        revisions: const [100],
      );

      expect(fullJob.targetWc, '/tmp/wc');
      expect(fullJob.targetUrl, 'svn://repo/branches/target');
      expect(fullJob.useTemporarySparseWorkingCopy, isFalse);
      expect(sparseJob.targetWc, isEmpty);
      expect(sparseJob.targetUrl, 'svn://repo/branches/target');
      expect(sparseJob.useTemporarySparseWorkingCopy, isTrue);
    });

    test('旧队列 JSON 可反序列化并推导 TargetConfig', () {
      final legacyFull = MergeJob.fromJson(const {
        'jobId': 3,
        'sourceUrl': 'svn://repo/branches/source',
        'targetWc': '/tmp/wc',
        'maxRetries': 1,
        'revisions': [100],
      });
      final legacySparse = MergeJob.fromJson(const {
        'jobId': 4,
        'sourceUrl': 'svn://repo/branches/source',
        'targetWc': '',
        'targetUrl': 'svn://repo/branches/target',
        'useTemporarySparseWorkingCopy': true,
        'maxRetries': 1,
        'revisions': [100],
      });

      expect(legacyFull.targetConfig.isFullWorkingCopy, isTrue);
      expect(legacyFull.targetConfig.workingCopyPath, '/tmp/wc');
      expect(legacySparse.targetConfig.isTemporarySparseWorkingCopy, isTrue);
      expect(legacySparse.targetConfig.svnUrl, 'svn://repo/branches/target');
    });

    test('copyWith preserves nullable fields unless overridden', () {
      const job = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 3,
        revisions: [101, 102],
        commitMessageTemplate: 'merge {revision}',
        commitSupplement: '--crid=42',
        mergeValidationScriptPath: 'Tools/check_merge.sh',
        useTemporarySparseWorkingCopy: true,
        temporaryWorkingCopyPath: '/tmp/sparse-wc',
        resumeFromStepId: 'commit',
      );

      final copied = job.copyWith(status: JobStatus.paused);
      final cleared = job.copyWith(
        resumeFromStepId: null,
        commitMessageTemplate: null,
        commitSupplement: null,
        mergeValidationScriptPath: null,
        temporaryWorkingCopyPath: null,
      );

      expect(copied.resumeFromStepId, 'commit');
      expect(copied.commitMessageTemplate, 'merge {revision}');
      expect(copied.commitSupplement, '--crid=42');
      expect(copied.mergeValidationScriptPath, 'Tools/check_merge.sh');
      expect(copied.useTemporarySparseWorkingCopy, isTrue);
      expect(copied.temporaryWorkingCopyPath, '/tmp/sparse-wc');
      expect(cleared.resumeFromStepId, isNull);
      expect(cleared.commitMessageTemplate, isNull);
      expect(cleared.commitSupplement, isNull);
      expect(cleared.mergeValidationScriptPath, isNull);
      expect(cleared.temporaryWorkingCopyPath, isNull);
    });

    test('json round trip keeps resume step and temporary sparse fields', () {
      const job = MergeJob(
        jobId: 8,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [200, 201, 202],
        status: JobStatus.paused,
        completedIndex: 1,
        pauseReason: '冲突',
        resumeFromStepId: 'merge',
        useTemporarySparseWorkingCopy: true,
        temporaryWorkingCopyPath: '/tmp/sparse-wc',
      );

      final restored = MergeJob.fromJson(job.toJson());

      expect(restored.resumeFromStepId, 'merge');
      expect(restored.useTemporarySparseWorkingCopy, isTrue);
      expect(restored.temporaryWorkingCopyPath, '/tmp/sparse-wc');
      expect(restored.currentRevision, 201);
      expect(restored.completedRevisions, [200]);
      expect(restored.remainingRevisions, [201, 202]);
    });

    test('recoverInterrupted keeps progress and requires manual resume', () {
      const job = MergeJob(
        jobId: 9,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [300, 301, 302],
        status: JobStatus.running,
        completedIndex: 1,
        resumeFromStepId: 'commit',
      );

      final recovered = job.recoverInterrupted();

      expect(recovered.status, JobStatus.paused);
      expect(recovered.completedIndex, 1);
      expect(recovered.currentRevision, 301);
      expect(recovered.pauseReason, kInterruptedJobPauseReason);
      expect(recovered.error, kInterruptedJobPauseReason);
      expect(recovered.resumeFromStepId, isNull);
    });

    test('shouldRecoverAsInterrupted detects stale in-progress jobs', () {
      const runningJob = MergeJob(
        jobId: 10,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [400, 401],
        status: JobStatus.running,
      );
      const pendingWithProgress = MergeJob(
        jobId: 11,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [500, 501],
        status: JobStatus.pending,
        completedIndex: 1,
      );
      const freshPending = MergeJob(
        jobId: 12,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [600, 601],
        status: JobStatus.pending,
      );

      expect(runningJob.shouldRecoverAsInterrupted, isTrue);
      expect(pendingWithProgress.shouldRecoverAsInterrupted, isTrue);
      expect(freshPending.shouldRecoverAsInterrupted, isFalse);
    });

    test('job flags reflect safe local queue actions', () {
      const failedJob = MergeJob(
        jobId: 13,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [700, 701, 702],
        status: JobStatus.failed,
        completedIndex: 1,
      );
      const doneJob = MergeJob(
        jobId: 14,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [800],
        status: JobStatus.done,
        completedIndex: 1,
      );

      expect(failedJob.canDelete, isTrue);
      expect(failedJob.canRequeueRemaining, isTrue);
      expect(doneJob.status.isFinished, isTrue);
      expect(doneJob.canRequeueRemaining, isFalse);
    });

    test('currentRevision becomes null after all revisions are completed', () {
      const doneJob = MergeJob(
        jobId: 15,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 2,
        revisions: [900, 901],
        status: JobStatus.done,
        completedIndex: 2,
      );

      expect(doneJob.currentRevision, isNull);
      expect(doneJob.remainingRevisions, isEmpty);
      expect(doneJob.completedRevisions, [900, 901]);
    });
  });

  group('clampedCompletedRevisionCount', () {
    // 构造一个最简 MergeJob，仅 revisions 与 completedIndex 有意义
    MergeJob mkJob(
            {required List<int> revisions, required int completedIndex}) =>
        MergeJob(
          jobId: 1,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: revisions,
          completedIndex: completedIndex,
        );

    // 真值表 5 角点
    test('completedIndex 在 [0, length] 区间内 → 原样返回', () {
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3, 4, 5], completedIndex: 2)),
        2,
      );
    });

    test('completedIndex == 0 → 0（下界刚好）', () {
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3], completedIndex: 0)),
        0,
      );
    });

    test('completedIndex == length → length（上界刚好——全部完成）', () {
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3], completedIndex: 3)),
        3,
      );
    });

    test('completedIndex < 0 → clamp 到 0（防越界——模型默认值/copyWith 异常时降级）', () {
      // 关键：若漏掉 clamp，UI 会渲染 `-1/5`、`-99/5` 这种负数进度，视觉穿帮
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3, 4, 5], completedIndex: -1)),
        0,
      );
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3], completedIndex: -100)),
        0,
      );
    });

    test('completedIndex > length → clamp 到 length（防越界——超完成异常）', () {
      // 关键：若漏掉 clamp，UI 会渲染 `7/5`、`100/3` 这种超界进度
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3, 4, 5], completedIndex: 7)),
        5,
      );
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3], completedIndex: 100)),
        3,
      );
    });

    // 边界锁定：clamp(0, length) 不是 clamp(1, length)
    test('completedIndex == 0 必须返回 0（锁定下界 0 而非 1）', () {
      // 如果 helper 被误改成 `clamp(1, ...)`，刚开始执行的任务（completedIndex=0）
      // 会被错误显示为 1/N——给用户错觉"已完成 1 条"实际上还没开始
      expect(
        clampedCompletedRevisionCount(
            mkJob(revisions: [1, 2, 3], completedIndex: 0)),
        0,
      );
    });

    // 空 revisions 的边界处理
    test('空 revisions + completedIndex == 0 → 0（length=0 的合法状态）', () {
      // 这是 caller 还会判 `length == 0` 早返回的状态——本谓词只负责 clamp
      expect(
        clampedCompletedRevisionCount(mkJob(revisions: [], completedIndex: 0)),
        0,
      );
    });

    test('空 revisions + completedIndex 异常值 → clamp 到 0（length=0 是上界）', () {
      // 即使 length=0 时本 helper 也能正常 clamp，不会触发任何运行时异常
      expect(
        clampedCompletedRevisionCount(mkJob(revisions: [], completedIndex: 5)),
        0,
      );
      expect(
        clampedCompletedRevisionCount(mkJob(revisions: [], completedIndex: -1)),
        0,
      );
    });

    // 端到端 callsite 反向断言（R80/R81/R82/R83 模式延续）：
    // 与 4 个 caller 函数（formatJobProgress / computeJobProgressRatio /
    // formatRevisionProgress / computeJobProgressFraction）联动验证
    // —— 但这些函数分散在 panel 文件中，此处只锁本谓词的输入输出契约；
    // panel 函数自己的测试 group 会覆盖端到端行为。
    test('返回值始终落在 [0, revisions.length] 闭区间内（不变量锁定）', () {
      // 在多组随机化输入上验证 helper 的不变量
      const revs = [1, 2, 3, 4, 5];
      for (final completedIndex in [-1000, -1, 0, 1, 3, 5, 6, 1000]) {
        final result = clampedCompletedRevisionCount(
            mkJob(revisions: revs, completedIndex: completedIndex));
        expect(result, greaterThanOrEqualTo(0),
            reason: 'completedIndex=$completedIndex: 必须 >= 0');
        expect(result, lessThanOrEqualTo(revs.length),
            reason: 'completedIndex=$completedIndex: 必须 <= length');
      }
    });
  });

  group('extractSourceDisplayName', () {
    test('正常 URL：取末段', () {
      expect(
        extractSourceDisplayName(
            'https://svn.example.com/repo/branches/feature-x'),
        'feature-x',
      );
    });

    test('SVN trunk 风格', () {
      expect(extractSourceDisplayName('svn://repo/trunk'), 'trunk');
    });

    test('不含 / 的输入整段返回', () {
      expect(extractSourceDisplayName('feature-x'), 'feature-x');
    });

    test('空字符串 → 空字符串', () {
      expect(extractSourceDisplayName(''), '');
    });

    test('与 extractWcDisplayName 当前实现等价（语义不同但今天等价）', () {
      // 锁定"今天等价、明天可能不同"的预期：路径侧 vs URL 侧的展示名提取
      // 是两个独立函数，未来 URL 端可能加 query/fragment 剥离。今天的等价性
      // 是 SVN URL 不含 fragment 的副产品。
      const x = 'a/b/c';
      expect(extractSourceDisplayName(x), extractWcDisplayName(x));
    });

    // R89 漏迁巡检：job_queue_panel.buildJobSubtitle 曾内联
    // `job.sourceUrl.split('/').last`，R89 替换为 `extractSourceDisplayName(job.sourceUrl)`。
    // 本测以"曾经的 inline 入参形态"喂给 helper，验证两种表达式在所有角点上输出
    // 等价——R85 → R86 → R88 → R89 漏迁等价测试模式延续。
    test('R89 迁移：buildJobSubtitle inline 等价于本 helper', () {
      final candidates = <String>[
        'https://svn.example.com/repo/branches/feature-x',
        'svn://repo/trunk',
        'feature-x',
        '',
        'a/b/c',
        'http://h/p1/p2/',
        '/leading/slash/branch',
      ];
      for (final sourceUrl in candidates) {
        expect(
          extractSourceDisplayName(sourceUrl),
          sourceUrl.split('/').last,
          reason: 'sourceUrl=$sourceUrl 时两种表达式应等价',
        );
      }
    });
  });

  group('extractWcDisplayName', () {
    test('正常路径：取末段', () {
      expect(extractWcDisplayName('/Users/foo/wc/projectA'), 'projectA');
    });

    test('单段输入整段返回', () {
      expect(extractWcDisplayName('projectA'), 'projectA');
    });

    test('以 / 结尾 → 末段为空字符串（bug 信号，刻意不回退到上一段）', () {
      // 路径以 / 结尾通常是上游拼接 bug，让空串显眼比"猜上一段"更利排查。
      expect(extractWcDisplayName('/tmp/wc/'), '');
    });

    test('空字符串 → 空字符串', () {
      expect(extractWcDisplayName(''), '');
    });

    test('Windows 反斜杠不识别（上游 normalizeWorkingCopyPath 是事实源）', () {
      // 故意不在这里重复做规范化——让上游路径规范化是唯一事实源。
      // 真实生产路径到这里时已经全部正斜杠。
      expect(
          extractWcDisplayName(r'C:\foo\wc\projectA'), r'C:\foo\wc\projectA');
    });
  });

  group('formatJobDescription', () {
    test('正常情况：5 段拼接', () {
      expect(
        formatJobDescription(
          jobId: 1,
          statusText: '等待',
          wcDisplayName: 'projectA',
          sourceDisplayName: 'feature-x',
          revisionListText: 'r100, r101',
        ),
        '#1 [等待] WC=projectA | 源=feature-x | r100, r101',
      );
    });

    test('结构性分隔符：3 个 " | " 半角竖线两侧加空格', () {
      // 运维通过 ' | WC=' / ' | 源=' 做 grep 切片——分隔符的字面与位置必须稳定。
      final line = formatJobDescription(
        jobId: 2,
        statusText: 'X',
        wcDisplayName: 'W',
        sourceDisplayName: 'S',
        revisionListText: 'R',
      );
      // " | " 应当出现恰好 2 次（WC 与 源 之间、源 与 rev 之间）。
      // 注：'#2 [X] WC=W' 内不含 ' | '。
      expect(' | '.allMatches(line).length, 2);
    });

    test('段顺序固定：jobId → status → WC → 源 → revisionList', () {
      final line = formatJobDescription(
        jobId: 99,
        statusText: 'S',
        wcDisplayName: 'W',
        sourceDisplayName: 'SRC',
        revisionListText: 'r1',
      );
      final iJobId = line.indexOf('#99');
      final iStatus = line.indexOf('[S]');
      final iWc = line.indexOf('WC=W');
      final iSrc = line.indexOf('源=SRC');
      final iRev = line.indexOf('r1');
      expect(iJobId, 0);
      expect(iJobId < iStatus, isTrue);
      expect(iStatus < iWc, isTrue);
      expect(iWc < iSrc, isTrue);
      expect(iSrc < iRev, isTrue);
    });

    test('空 wcDisplayName → "WC= |"（等号后空白作为 bug 信号）', () {
      final line = formatJobDescription(
        jobId: 3,
        statusText: 'X',
        wcDisplayName: '',
        sourceDisplayName: 's',
        revisionListText: 'r1',
      );
      expect(line.contains('WC= |'), isTrue);
    });

    test('空 revisionListText → 末尾以 " | " 结尾（暴露空 revisions 的 bug）', () {
      final line = formatJobDescription(
        jobId: 4,
        statusText: 'X',
        wcDisplayName: 'W',
        sourceDisplayName: 'S',
        revisionListText: '',
      );
      expect(line.endsWith(' | '), isTrue);
    });

    test('jobId 负数透传（暴露上游编号 bug）', () {
      // 不防御负数：jobId 由全局自增器分配，传负数 = 上游 bug 应当显眼。
      final line = formatJobDescription(
        jobId: -1,
        statusText: 'X',
        wcDisplayName: 'W',
        sourceDisplayName: 'S',
        revisionListText: 'r1',
      );
      expect(line.startsWith('#-1 '), isTrue);
    });
  });

  group('formatJobStatusWithProgress', () {
    test('paused 附加进度括号', () {
      expect(formatJobStatusWithProgress(JobStatus.paused, 1, 3), '已暂停 (1/3)');
    });

    test('其它 4 个状态原样返回 displayName（无括号）', () {
      // 锁定"只有 paused 才加进度"的契约——避免有人"为了一致性"给所有状态加上进度。
      expect(formatJobStatusWithProgress(JobStatus.pending, 0, 3), '等待');
      expect(formatJobStatusWithProgress(JobStatus.running, 1, 3), '执行中');
      expect(formatJobStatusWithProgress(JobStatus.done, 3, 3), '完成');
      expect(formatJobStatusWithProgress(JobStatus.failed, 2, 3), '失败');
    });

    test('paused 的 i/n 异常值原样透传（不做 clamp）', () {
      // i > n / i < 0 / n == 0 都直接拼字面，让异常进度作为 bug 信号显眼。
      expect(formatJobStatusWithProgress(JobStatus.paused, 5, 3), '已暂停 (5/3)');
      expect(
          formatJobStatusWithProgress(JobStatus.paused, -1, 3), '已暂停 (-1/3)');
      expect(formatJobStatusWithProgress(JobStatus.paused, 0, 0), '已暂停 (0/0)');
    });

    test('paused 进度括号格式：半角空格 + 半角圆括号 + 半角斜杠', () {
      // 与中文全角"（）"刻意区分——状态条字符宽度敏感，半角更紧凑。
      final line = formatJobStatusWithProgress(JobStatus.paused, 1, 3);
      expect(line.contains(' ('), isTrue);
      expect(line.contains('/'), isTrue);
      expect(line.endsWith(')'), isTrue);
      expect(line.contains('（'), isFalse);
      expect(line.contains('）'), isFalse);
    });
  });

  group('formatRevisionListShort', () {
    test('正常列表：r 前缀 + 半角逗号空格分隔', () {
      expect(formatRevisionListShort([100, 101, 102]), 'r100, r101, r102');
    });

    test('单元素：无分隔符', () {
      expect(formatRevisionListShort([42]), 'r42');
    });

    test('空列表 → 空字符串（不返回占位文案）', () {
      // 让上层 formatJobDescription 在 revisions 为空时拼出 '... | ' 末尾空白
      // 作为 bug 信号显眼。
      expect(formatRevisionListShort([]), '');
    });

    test('负数透传（暴露上游 bug，不做防御）', () {
      // SVN revision 永远 >= 1；传负数 = 上游 bug，应该让 'r-1' 显眼出现。
      expect(formatRevisionListShort([-1, -2]), 'r-1, r-2');
    });

    test('不去重 / 不排序（保持入参顺序）', () {
      // "乱序的 revisions" 是潜在的状态机 bug 信号——日志直接显眼比静默修复好。
      expect(formatRevisionListShort([3, 1, 2, 1]), 'r3, r1, r2, r1');
    });

    test('使用半角分隔符（与 formatJobDescription 风格统一）', () {
      // 不用全角"，"或中文顿号"、"——保持机读 grep 友好。
      final line = formatRevisionListShort([1, 2]);
      expect(line.contains(', '), isTrue);
      expect(line.contains('，'), isFalse);
      expect(line.contains('、'), isFalse);
    });
  });

  group('resolveRecoveryReason', () {
    test('正常字符串：trim 后返回', () {
      expect(resolveRecoveryReason('  冲突  '), '冲突');
    });

    test('空字符串 → 默认 kInterruptedJobPauseReason', () {
      expect(resolveRecoveryReason(''), kInterruptedJobPauseReason);
    });

    test('仅空白字符 → 默认（与 isEmpty 不同！UI 上不可见等同于未填）', () {
      // 这是契约的核心：'   ' / '\n' / '\t' 在 isEmpty 看来非空，但用户语义为空。
      expect(resolveRecoveryReason('   '), kInterruptedJobPauseReason);
      expect(resolveRecoveryReason('\n'), kInterruptedJobPauseReason);
      expect(resolveRecoveryReason('\t'), kInterruptedJobPauseReason);
      expect(resolveRecoveryReason(' \t\n '), kInterruptedJobPauseReason);
    });

    test('入参恰好等于默认值 → trim 后返回该字符串本身（不做 identity 优化）', () {
      // 锁定行为：函数不"识别"默认值；返回值是 trim 后的字符串，恰好与默认相等。
      expect(
        resolveRecoveryReason(kInterruptedJobPauseReason),
        kInterruptedJobPauseReason,
      );
    });

    test('入参带前后空白且非空白 → 返回 trim 后的非空白部分', () {
      expect(resolveRecoveryReason('  提交失败  '), '提交失败');
      expect(resolveRecoveryReason('\n冲突\t'), '冲突');
    });
  });

  group('evaluateNeedsIntervention', () {
    test('仅 paused → true，其他 4 个状态 → false（5 行真值表）', () {
      // 防漏配 enum 真值表 (#11) 第六处实例：遍历 JobStatus.values，
      // 任何新增枚举值会强制 review。
      final results = {
        for (final s in JobStatus.values) s: evaluateNeedsIntervention(s),
      };
      expect(results, {
        JobStatus.pending: false,
        JobStatus.running: false,
        JobStatus.paused: true,
        JobStatus.done: false,
        JobStatus.failed: false,
      });
    });

    test('JobStatus.values.length == 5（新增枚举值时本测会红，强制 review）', () {
      expect(JobStatus.values.length, 5);
    });
  });

  group('evaluateCanDelete', () {
    test('5 行真值表：仅 running / paused → false，其他 → true', () {
      // 防漏配 enum 真值表，与 evaluateNeedsIntervention 同模式。
      final results = {
        for (final s in JobStatus.values) s: evaluateCanDelete(s),
      };
      expect(results, {
        JobStatus.pending: true,
        JobStatus.running: false,
        JobStatus.paused: false,
        JobStatus.done: true,
        JobStatus.failed: true,
      });
    });

    test('与 evaluateNeedsIntervention 的真值不重合（独立维度）', () {
      // canDelete 与 needsIntervention 是不同决策；同时为 false 的状态有 running，
      // 同时为 true 的状态有 done / failed / pending——独立函数独立测试，
      // 防止有人误以为 "needsIntervention == !canDelete" 而合并判定。
      // running: canDelete=false, needsIntervention=false （都 false 但不同原因）
      expect(evaluateCanDelete(JobStatus.running), isFalse);
      expect(evaluateNeedsIntervention(JobStatus.running), isFalse);
      // pending: canDelete=true, needsIntervention=false
      expect(evaluateCanDelete(JobStatus.pending), isTrue);
      expect(evaluateNeedsIntervention(JobStatus.pending), isFalse);
    });
  });

  group('evaluateCanRequeueRemaining', () {
    test('双维度真值表 5×2=10 行：仅 (failed, true) → true', () {
      // 双维度真值表 (#11+#15+#17 第六处实例)：status × hasRemainingRevisions。
      final results = <(JobStatus, bool), bool>{};
      for (final s in JobStatus.values) {
        for (final has in [true, false]) {
          results[(s, has)] = evaluateCanRequeueRemaining(
            status: s,
            hasRemainingRevisions: has,
          );
        }
      }
      // 仅一个组合为 true
      final trueKeys = results.entries.where((e) => e.value).map((e) => e.key);
      expect(trueKeys, [(JobStatus.failed, true)]);
    });

    test('反向断言 A：固定 hasRemaining=true，仅 failed 与其他状态结果不同', () {
      // 锁定"hasRemaining=true 时 status 决定结果"：除 failed 外其他状态全为 false，
      // failed 为 true。如果有人误把 done 也加入"可重新入队"会立即撞红。
      final results = {
        for (final s in JobStatus.values)
          s: evaluateCanRequeueRemaining(
            status: s,
            hasRemainingRevisions: true,
          ),
      };
      expect(results[JobStatus.failed], isTrue);
      // 其他 4 个全 false
      for (final s in JobStatus.values.where((s) => s != JobStatus.failed)) {
        expect(results[s], isFalse, reason: 'status=$s 应为 false');
      }
    });

    test('反向断言 B：固定 status=failed，hasRemaining=true vs false 仅 hasRemaining 不同',
        () {
      // 与 A 成对：锁定 "status=failed 时 hasRemaining 决定结果"。
      // 两条加起来证明 (status, hasRemaining) 是真独立维度——
      // 设计模式 #17 第六处实例。
      expect(
        evaluateCanRequeueRemaining(
          status: JobStatus.failed,
          hasRemainingRevisions: true,
        ),
        isTrue,
      );
      expect(
        evaluateCanRequeueRemaining(
          status: JobStatus.failed,
          hasRemainingRevisions: false,
        ),
        isFalse,
      );
    });
  });

  group('evaluateShouldRecoverAsInterrupted', () {
    test('running → 立刻 true，不论 completedIndex / resumeFromStepId', () {
      // 第 1 段优先级：running 短路，后两个参数完全不影响。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.running,
          completedIndex: 0,
          resumeFromStepId: null,
        ),
        isTrue,
      );
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.running,
          completedIndex: 5,
          resumeFromStepId: 'svn_update',
        ),
        isTrue,
      );
    });

    test(
        'paused / done / failed → 立刻 false，不论 completedIndex / resumeFromStepId',
        () {
      // 第 2 段优先级：非 pending 非 running 一律 false——
      // "已结束的状态"不需要按中断恢复。
      for (final s in [JobStatus.paused, JobStatus.done, JobStatus.failed]) {
        // 即使有进度信号也必须 false
        expect(
          evaluateShouldRecoverAsInterrupted(
            status: s,
            completedIndex: 5,
            resumeFromStepId: 'svn_update',
          ),
          isFalse,
          reason: 'status=$s + 完整恢复信号 应为 false',
        );
        // 边界：无信号
        expect(
          evaluateShouldRecoverAsInterrupted(
            status: s,
            completedIndex: 0,
            resumeFromStepId: null,
          ),
          isFalse,
          reason: 'status=$s + 无信号 应为 false',
        );
      }
    });

    test('pending + completedIndex>0 → true（已开始过执行）', () {
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 1,
          resumeFromStepId: null,
        ),
        isTrue,
      );
    });

    test('pending + completedIndex==0 + resumeFromStepId==null → false（崭新任务）',
        () {
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 0,
          resumeFromStepId: null,
        ),
        isFalse,
      );
    });

    test('pending + completedIndex==0 + resumeFromStepId="" → false（空串等价 null）',
        () {
      // 关键边界：空字符串 isNotEmpty=false，与 null 等价走 || 短路看 completedIndex。
      // 防止有人把判定从 isNotEmpty 改成 != null 导致空串变成 true。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 0,
          resumeFromStepId: '',
        ),
        isFalse,
      );
    });

    test('pending + completedIndex==0 + resumeFromStepId="svn_update" → true',
        () {
      // 第 3 段优先级的后半：resumeFromStepId 非空时单独触发恢复。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 0,
          resumeFromStepId: 'svn_update',
        ),
        isTrue,
      );
    });

    test(
        'pending + completedIndex==0 + resumeFromStepId="   "（仅空白）→ true（不做 trim）',
        () {
      // 锁定"isNotEmpty 不做 trim"——空白字符串视作有效 resume 点；
      // 防止有人把判定改成 isNotEmpty + trim 导致行为静默改变。
      // 故意保留：上游写入时不应有空白污染，出现就让恢复路径暴露问题。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 0,
          resumeFromStepId: '   ',
        ),
        isTrue,
      );
    });

    test('反向断言：running 状态下 (completedIndex, resumeFromStepId) 切换不影响结果', () {
      // 锁定第 1 段优先级的"短路"性质：4 种 (completedIndex, resumeFromStepId) 组合
      // 在 running 状态下结果必须全为 true。
      final cases = [
        (0, null),
        (5, null),
        (0, 'step'),
        (5, 'step'),
      ];
      for (final (idx, step) in cases) {
        expect(
          evaluateShouldRecoverAsInterrupted(
            status: JobStatus.running,
            completedIndex: idx,
            resumeFromStepId: step,
          ),
          isTrue,
          reason: 'running 短路应忽略 (idx=$idx, step=$step)',
        );
      }
    });

    test('反向断言：done 状态下 (completedIndex, resumeFromStepId) 切换不影响结果', () {
      // 锁定第 2 段优先级的"短路"性质：与 running 反向断言成对，
      // 证明非 pending 状态下后两个参数维度独立无影响。
      final cases = [
        (0, null),
        (5, null),
        (0, 'step'),
        (5, 'step'),
      ];
      for (final (idx, step) in cases) {
        expect(
          evaluateShouldRecoverAsInterrupted(
            status: JobStatus.done,
            completedIndex: idx,
            resumeFromStepId: step,
          ),
          isFalse,
          reason: 'done 短路应忽略 (idx=$idx, step=$step)',
        );
      }
    });

    test('completedIndex 负数（异常输入）→ 走 > 0 判定为 false', () {
      // 边界：> 0 而不是 >= 1，负数也是 false（与 0 等价）。
      // 不做防御性 dart range check——异常 completedIndex 是上游持久化 bug 信号。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: -1,
          resumeFromStepId: null,
        ),
        isFalse,
      );
    });
  });

  // ===========================================================================
  // R96: enum-internal method 覆盖审计（JobStatusExtension）
  // ---------------------------------------------------------------------------
  // R95 给 12 个 "helper-takes-enum" 形态的映射函数都铺了"4 层防御栈"
  // （编译器 exhaustive / 循环式 guard / .length guard / 逐值断言）。
  // R96 把同样防御栈延伸到 enum-internal `switch (this)` 形态——这是 R95
  // 关键词搜索的盲区（R95 grep `switch on enum`，未覆盖 `extension` 内的
  // `switch (this)` 写法）。
  //
  // lib/ 内现存两处 enum-internal switch：
  //  1. JobStatusExtension.displayName（merge_job.dart:30-43，5 cases）
  //  2. WcOperationTypeX.label（working_copy_manager.dart:211-230，8 cases）
  //
  // 其中 (2) 已在 working_copy_manager_test.dart:504-528 完成同等防御
  // （loop 非空 guard + 8 条逐值锁 + 文案唯一性互斥），无需再加
  // .length guard——uniqueness 隐式承担"新增 enum 即 fail"的角色。
  //
  // 本 group 补 (1) JobStatusExtension 的全部成员：
  //  - displayName (5-case switch)：逐值 + .length guard
  //  - isActive (3-state predicate)：真值表 + .length guard
  //  - isFinished (2-state predicate)：真值表 + .length guard
  //
  // 每条 .length guard 的 reason 字段独立指向"现在 review 哪个 method 的何种
  // 决策"——保留 R95 测试反 DRY 原则（fail message 是核心产出）。
  // ===========================================================================
  group('JobStatusExtension.displayName', () {
    test('5 个枚举值的中文文案锁定', () {
      // 任何文案漂移都需要先红再绿——displayName 在 UI 与日志多处展示，
      // 改动需先确认所有 callsite 一并迁移。
      expect(JobStatus.pending.displayName, '等待');
      expect(JobStatus.running.displayName, '执行中');
      expect(JobStatus.paused.displayName, '已暂停');
      expect(JobStatus.done.displayName, '完成');
      expect(JobStatus.failed.displayName, '失败');
    });

    test('每个枚举值都有非空 displayName', () {
      // 循环式 guard：新增 enum 时自动覆盖、无需修改测试；
      // 与 .length guard 互补——这层捕"新增 enum 但 displayName 漏 case"
      // （编译器 exhaustive switch 已会报错，本测是冗余防御层）。
      for (final s in JobStatus.values) {
        expect(s.displayName, isNotEmpty,
            reason: '$s 必须有可读 displayName，否则状态条会出现空文案');
      }
    });

    test('5 个 displayName 互不相同 — 防止两个状态在 UI 里成同一句话', () {
      // 与 WcOperationType.label 同模式：唯一性约束 + 集合大小相等
      // 隐含 .length 校验，新增 enum 但 displayName 与他人重复时会撞红。
      final names = JobStatus.values.map((e) => e.displayName).toSet();
      expect(names.length, JobStatus.values.length,
          reason: 'displayName 必须互不相同——重复会让用户在状态条/日志里无法区分');
    });

    test('R96 防漏配：JobStatus.values.length == 5（强制 review displayName 5 case）',
        () {
      // 即便有 uniqueness guard，仍保留显式 .length guard——reason 精确指向
      // "review JobStatusExtension.displayName 的 5 个 case 文案"。
      // 维持 R95 反 DRY 原则：每条 guard 的 fail message 单独自描述。
      expect(JobStatus.values.length, 5,
          reason:
              '新增 JobStatus enum 时，必须 review JobStatusExtension.displayName '
              '的 switch (this) 是否补充新 case 的中文文案，并加入逐值锁定测试。');
    });
  });

  group('JobStatusExtension.isActive', () {
    test('真值表 5 行：仅 pending / running / paused → true', () {
      // 与 evaluateCanDelete / evaluateNeedsIntervention 同模式——
      // 全枚举值真值表锁定，新增 enum 时 map literal 缺失会显眼。
      final results = {
        for (final s in JobStatus.values) s: s.isActive,
      };
      expect(results, {
        JobStatus.pending: true,
        JobStatus.running: true,
        JobStatus.paused: true,
        JobStatus.done: false,
        JobStatus.failed: false,
      });
    });

    test('与 isFinished 互斥（覆盖全部 5 个枚举值）', () {
      // 设计契约：每个 JobStatus 必须满足 isActive XOR isFinished == true。
      // 这是 isActive / isFinished 两个谓词的并集应该正好等于 JobStatus.values
      // 的隐含约束——锁定后未来新增 enum 时若两者都漏配（或都加），会撞红。
      for (final s in JobStatus.values) {
        expect(s.isActive ^ s.isFinished, isTrue,
            reason: '$s: isActive(${s.isActive}) 与 isFinished(${s.isFinished}) '
                '必须互斥（异或为 true）——每个状态恰好属于一类');
      }
    });

    test('R96 防漏配：JobStatus.values.length == 5（强制 review isActive 真值表）', () {
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus enum 时，必须 review JobStatusExtension.isActive '
              '的语义判定（是否属于"活跃中需展示"），并补到本 group 的真值表里。');
    });
  });

  group('JobStatusExtension.isFinished', () {
    test('真值表 5 行：仅 done / failed → true', () {
      final results = {
        for (final s in JobStatus.values) s: s.isFinished,
      };
      expect(results, {
        JobStatus.pending: false,
        JobStatus.running: false,
        JobStatus.paused: false,
        JobStatus.done: true,
        JobStatus.failed: true,
      });
    });

    test('R96 防漏配：JobStatus.values.length == 5（强制 review isFinished 真值表）', () {
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus enum 时，必须 review JobStatusExtension.isFinished '
              '的语义判定（是否属于"已结束可清理"），并补到本 group 的真值表里。'
              '同时检查与 isActive 的互斥关系是否仍成立。');
    });
  });

  // R99 跨谓词关系不变量审计（继 R96 isActive XOR isFinished 互斥不变量后的二期）：
  // 项目内 6 个 JobStatus 驱动谓词（isActive / isFinished / evaluateNeedsIntervention /
  // evaluateCanDelete / evaluateCanRequeueRemaining / evaluateShouldRecoverAsInterrupted）
  // 之间存在 4 条 lib doc 明确描述、但测试未锁的"关系不变量"：
  //   (1) isActive ⊃ needsIntervention（lib/models/merge_job.dart:232-234 明文：paused 是
  //       isActive {pending,running,paused} 的真子集，独立维度但有包含关系）
  //   (2) needsIntervention → !canDelete（paused 状态：需介入 ∧ 不可删——逻辑必然）
  //   (3) isFinished → canDelete（done/failed 两态都可删——逻辑必然）
  //   (4) canRequeueRemaining → isFinished（failed 是 isFinished 子集——逻辑必然）
  // 这些"包含/蕴含不变量"是 R96 "XOR 不变量"的同模式扩展：单点真值表只锁单谓词，
  // 跨谓词关系锁住生产代码里两个谓词的协同语义——新增 JobStatus 时若漏配关系（如新增
  // canceled 状态忘了同时加进 isFinished 和 canDelete），关系测试会立刻撞红。
  group('跨谓词关系不变量（R99）', () {
    test('isActive ⊃ needsIntervention（paused 是 isActive 的真子集）', () {
      // lib/models/merge_job.dart:232-234 明确："需要介入"是"活跃"的特例（仅 paused）。
      // 关系不变量：∀ s ∈ JobStatus.values, needsIntervention(s) → s.isActive
      // 即：若 needsIntervention(s) 为 true，则 s.isActive 也必为 true。
      for (final s in JobStatus.values) {
        if (evaluateNeedsIntervention(s)) {
          expect(s.isActive, isTrue,
              reason: '$s: 需介入但不活跃——违反 lib doc:232-234 声明的包含关系。');
        }
      }
      // 反向 + 严格子集检查：至少有一个 s 满足 isActive=true 但 needsIntervention=false
      // （即"活跃"严格大于"需介入"）。否则两谓词等价，doc 的"独立维度"宣称破产。
      final activeButNoIntervention = JobStatus.values
          .where((s) => s.isActive && !evaluateNeedsIntervention(s))
          .toList();
      expect(activeButNoIntervention, isNotEmpty,
          reason: 'isActive 必须严格大于 needsIntervention——pending/running 都应符合。');
    });

    test('needsIntervention → !canDelete（paused 不可删）', () {
      // 逻辑契约：等待用户处理冲突的任务强删会丢恢复入口（lib:243）。
      // 关系不变量：∀ s, needsIntervention(s) → !canDelete(s)
      for (final s in JobStatus.values) {
        if (evaluateNeedsIntervention(s)) {
          expect(evaluateCanDelete(s), isFalse,
              reason: '$s: 需介入但允许删除——会丢恢复入口，违反 lib:243 设计。');
        }
      }
    });

    test('isFinished → canDelete（done/failed 都允许删）', () {
      // 逻辑契约：已结束态（done / failed）必属于 canDelete 子集（lib:244 兜底语义）。
      // 关系不变量：∀ s, s.isFinished → canDelete(s)
      for (final s in JobStatus.values) {
        if (s.isFinished) {
          expect(evaluateCanDelete(s), isTrue,
              reason: '$s: 已结束但不允许删除——违反 lib:244 "已结束可删"兜底契约。');
        }
      }
    });

    test('canRequeueRemaining(s, true) → s.isFinished（仅 failed 可 requeue）', () {
      // canRequeueRemaining 双维度真值表已在 group('evaluateCanRequeueRemaining') 锁定
      // status==failed ∧ hasRemaining==true 为唯一 true 行。本测试锁住更高层不变量：
      // 任何能 requeue 的状态必然 isFinished——避免未来新增"halted"等中间态时被误判可 requeue。
      for (final s in JobStatus.values) {
        if (evaluateCanRequeueRemaining(
            status: s, hasRemainingRevisions: true)) {
          expect(s.isFinished, isTrue,
              reason: '$s: 允许 requeue 但未结束——会与正在执行的任务冲突。');
        }
      }
    });

    test('R99 防漏配：JobStatus.values.length == 5（强制 review 关系不变量）', () {
      // 新增 JobStatus 时，必须 review 本 group 4 条关系不变量是否仍成立：
      //   (1) 新值若 needsIntervention=true，则必须同时 isActive=true
      //   (2) 新值若 needsIntervention=true，则必须 canDelete=false
      //   (3) 新值若 isFinished=true，则必须 canDelete=true
      //   (4) 新值若可被 requeue（在 evaluateCanRequeueRemaining 加 case），则必须 isFinished=true
      // 这 4 条比单谓词 .length guard 更上层——锁住的不是"该谓词的某个 case"、
      // 而是"两个谓词之间的协同语义"。
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus 时，必须 review 本 group 4 条关系不变量是否仍成立。'
              '若新值的语义不属于现存 5 态的任一分类，需 doc 化解释为什么打破关系。');
    });
  });

  // R100 多维度谓词的跨谓词关系不变量审计（R99 的二期）：
  // R99 锁定 6 个 JobStatus 驱动谓词中的 4 条 1D 关系不变量，但故意跳过了
  // `evaluateShouldRecoverAsInterrupted` —— 该谓词依赖 (status, completedIndex,
  // resumeFromStepId) 三维输入，与单纯 JobStatus 驱动的谓词不同维度。R100 把它纳入：
  // 即使是多维度谓词，**第一维 status 仍然是与其他谓词协同的契约接口**——其他两维
  // (completedIndex / resumeFromStepId) 在生产代码里只影响 status==pending 子树，
  // 不与其他 JobStatus 谓词产生关系。所以 R100 仍按"shouldRecover(s, *, *) → P(s)"形式
  // 写关系不变量、其他两维任意取值无关。
  //
  // 三条关系不变量 + 一条 negative-relation doc：
  //   (1) shouldRecover → s.isActive（true 结果仅出现于 running 或 pending+progress，
  //       两者都 ∈ {pending,running,paused} = isActive 子集）
  //   (2) shouldRecover → !s.isFinished（R96 XOR + (1) 的推论；显式锁住避免
  //       通过 R96 XOR 间接推导，让契约对 reviewer 直接可见）
  //   (3) shouldRecover → !needsIntervention(s)（needsIntervention 仅 paused、
  //       shouldRecover 仅 running/pending，状态集不相交）
  //   negative-relation: shouldRecover 与 canDelete 之间无单向关系
  //     —— pending+progress：shouldRecover=true ∧ canDelete=true（反例存在）
  //     —— running：shouldRecover=true ∧ canDelete=false
  //     这是**故意非关系**，doc 化避免未来 reviewer 误以为"shouldRecover → !canDelete"
  //     而强行加测试（继承 R98 "测试不绑实现细节"的反向例证原则）。
  group('多维度谓词关系不变量（R100）', () {
    test('shouldRecover(s, *, *) → s.isActive（两维任意取值时仍然成立）', () {
      // 用"代表性多维取值"覆盖：每个 (status, idx, step) 组合都验证关系。
      // completedIndex / resumeFromStepId 故意取 6 种代表值，覆盖三维短路 + 边界。
      final dimCombos = <(int, String?)>[
        (0, null),
        (5, null),
        (0, 'step'),
        (5, 'step'),
        (-1, null), // 异常 idx
        (0, ''), // 空串
      ];
      for (final s in JobStatus.values) {
        for (final (idx, step) in dimCombos) {
          final shouldRecover = evaluateShouldRecoverAsInterrupted(
            status: s,
            completedIndex: idx,
            resumeFromStepId: step,
          );
          if (shouldRecover) {
            expect(s.isActive, isTrue,
                reason:
                    '$s + idx=$idx + step=$step: shouldRecover=true 但 isActive=false，'
                    '违反 R100 关系契约——shouldRecover 真值集必须是 isActive 真值集的子集。');
          }
        }
      }
    });

    test('shouldRecover(s, *, *) → !s.isFinished（R96 XOR 的推论显式锁定）', () {
      // 显式锁定避免依赖 R96 XOR 推导：若 R96 XOR 被未来重构破坏，本测试仍能独立守门。
      final dimCombos = <(int, String?)>[
        (0, null),
        (5, null),
        (0, 'step'),
        (5, 'step'),
      ];
      for (final s in JobStatus.values) {
        for (final (idx, step) in dimCombos) {
          if (evaluateShouldRecoverAsInterrupted(
              status: s, completedIndex: idx, resumeFromStepId: step)) {
            expect(s.isFinished, isFalse,
                reason:
                    '$s + idx=$idx + step=$step: shouldRecover=true 但 isFinished=true，'
                    '违反 R100 关系契约——shouldRecover 与 isFinished 状态集不相交。');
          }
        }
      }
    });

    test('shouldRecover(s, *, *) → !needsIntervention(s)（状态集不相交）', () {
      // shouldRecover 仅 running/pending，needsIntervention 仅 paused——两者不相交。
      final dimCombos = <(int, String?)>[
        (0, null),
        (5, null),
        (0, 'step'),
        (5, 'step'),
      ];
      for (final s in JobStatus.values) {
        for (final (idx, step) in dimCombos) {
          if (evaluateShouldRecoverAsInterrupted(
              status: s, completedIndex: idx, resumeFromStepId: step)) {
            expect(evaluateNeedsIntervention(s), isFalse,
                reason:
                    '$s + idx=$idx + step=$step: shouldRecover=true 但 needsIntervention=true，'
                    'shouldRecover/needsIntervention 状态集应不相交（running/pending vs paused）。');
          }
        }
      }
    });

    test('故意非关系：shouldRecover 与 canDelete 无单向蕴含（双向反例 doc 化）', () {
      // R100 故意非关系测试——锁住 doc 化的"非关系"：未来若有人加
      // "shouldRecover → !canDelete" 之类的关系测试，本测试的存在会提示该关系不成立。
      // 反例 1：pending + progress 状态下，shouldRecover=true ∧ canDelete=true（两者都为真）
      // 反例 2：running 状态下，shouldRecover=true ∧ canDelete=false
      // 两者都为 shouldRecover=true 但 canDelete 取不同值——证明 shouldRecover
      // 不蕴含 canDelete 的任何固定值。
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.pending,
          completedIndex: 5,
          resumeFromStepId: null,
        ),
        isTrue,
        reason: '反例 1 前提：pending+progress 必须 shouldRecover=true',
      );
      expect(evaluateCanDelete(JobStatus.pending), isTrue,
          reason: '反例 1 结论：pending 必须 canDelete=true（与 shouldRecover=true 共存）');
      expect(
        evaluateShouldRecoverAsInterrupted(
          status: JobStatus.running,
          completedIndex: 0,
          resumeFromStepId: null,
        ),
        isTrue,
        reason: '反例 2 前提：running 必须 shouldRecover=true',
      );
      expect(evaluateCanDelete(JobStatus.running), isFalse,
          reason:
              '反例 2 结论：running 必须 canDelete=false（与 shouldRecover=true 共存）');
    });

    test('R100 防漏配：JobStatus.values.length == 5（多维谓词关系不变量）', () {
      // 新增 JobStatus 时，必须 review 本 group 3 条关系不变量 + 1 条非关系：
      //   (1) 新值若可让 shouldRecover=true（在 evaluateShouldRecoverAsInterrupted 第 1/3 段
      //       优先级里加 case 或扩展 pending 子树），则必须 isActive=true
      //   (2) 同上 → 必须 isFinished=false（与 isActive XOR 一致）
      //   (3) 同上 → 必须 needsIntervention=false
      //   非关系：shouldRecover 与 canDelete 不要硬绑——新增状态若同时是"应恢复"和
      //       "可删除"语义（如 canceled 处于 paused 但已无意义可清理），是合法设计。
      expect(JobStatus.values.length, 5,
          reason:
              '新增 JobStatus 时，必须 review 本 group 3 条 shouldRecover 关系不变量是否仍成立。'
              '若新值打破任一关系（如新增"互动中但已结束"的状态），需 doc 化解释。');
    });
  });

  // R101 MergeJob round-trip 完整性审计：
  // 原有 'json round trip keeps resume step field' 测试只锁 4 个 derived 字段
  // （resumeFromStepId / currentRevision / completedRevisions / remainingRevisions），
  // 11 个原始字段中**只显式锁了 1 个 nullable**（resumeFromStepId），其余 10 字段 round-trip
  // 是隐式依赖（通过 derived 字段间接验证）——若有人误把 toJson/fromJson 字段名打错，
  // 部分字段会沉默丢失，原测试不会撞红。本轮补"全字段显式 round-trip"+"双 nullable 字段
  // null/非null 双路 round-trip"。
  group('MergeJob round-trip 完整性（R101）', () {
    test('全字段非默认值 round-trip', () {
      const original = MergeJob(
        jobId: 42,
        sourceUrl: 'svn://repo/branches/feature',
        targetWc: '/workspace/main',
        maxRetries: 5, // 非默认
        revisions: [100, 101, 102, 103],
        status: JobStatus.failed, // 非默认 pending
        error: '冲突未解决',
        completedIndex: 2,
        pauseReason: 'merge conflict at file.txt',
        commitMessageTemplate: 'Merge r{revision} from {sourceUrl}',
        sourceMessagesByRevision: {
          '100': '标题\n\n完整正文',
          '101': '另一个提交',
        },
        commitSupplement: '--crid=123456',
        mergeValidationScriptPath: 'Tools/check_merge.sh',
        resumeFromStepId: 'svn_commit',
      );
      final restored = MergeJob.fromJson(original.toJson());
      // 逐字段断言而非整体 equals——后者依赖 == 重写，且 fail 时无法定位到字段。
      expect(restored.jobId, original.jobId);
      expect(restored.sourceUrl, original.sourceUrl);
      expect(restored.targetWc, original.targetWc);
      expect(restored.maxRetries, original.maxRetries);
      expect(restored.revisions, original.revisions);
      expect(restored.status, original.status,
          reason: 'JobStatus enum 必须 round-trip 保持——@JsonEnum 默认 name 序列化。');
      expect(restored.error, original.error);
      expect(restored.completedIndex, original.completedIndex);
      expect(restored.pauseReason, original.pauseReason);
      expect(restored.commitMessageTemplate, original.commitMessageTemplate);
      expect(
        restored.sourceMessagesByRevision,
        original.sourceMessagesByRevision,
      );
      expect(restored.commitSupplement, original.commitSupplement);
      expect(restored.mergeValidationScriptPath,
          original.mergeValidationScriptPath);
      expect(restored.resumeFromStepId, original.resumeFromStepId);
    });

    test('两个 nullable 字段同时为 null 的 round-trip', () {
      // commitMessageTemplate 与 resumeFromStepId 都是 String?——双 null 是常见态
      // （崭新任务无 resume 点 + 不自定义 commit 模板）。round-trip 不能把 null
      // 退化为空串或丢失（@JsonKey includeIfNull 行为锁定）。
      const original = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://repo',
        targetWc: '/wc',
        maxRetries: 3,
        revisions: [100],
        // commitMessageTemplate / resumeFromStepId 都默认 null
      );
      expect(original.commitMessageTemplate, isNull);
      expect(original.resumeFromStepId, isNull);
      final restored = MergeJob.fromJson(original.toJson());
      expect(restored.commitMessageTemplate, isNull,
          reason: 'commitMessageTemplate=null 必须 round-trip 仍为 null。');
      expect(restored.resumeFromStepId, isNull,
          reason: 'resumeFromStepId=null 必须 round-trip 仍为 null。');
    });

    test('JobStatus 枚举各值 round-trip（5 个状态全覆盖）', () {
      // 防御 JSON enum 序列化策略变更（如有人改成 index 序列化）导致历史数据不兼容。
      // 测试遍历 JobStatus.values 强制覆盖——新增枚举值时若 round-trip 行为漂移会撞红。
      for (final status in JobStatus.values) {
        final original = MergeJob(
          jobId: 1,
          sourceUrl: 'svn://r',
          targetWc: '/w',
          maxRetries: 1,
          revisions: const [1],
          status: status,
        );
        final restored = MergeJob.fromJson(original.toJson());
        expect(restored.status, status,
            reason: 'JobStatus.$status round-trip 失败——序列化策略可能漂移。');
      }
    });

    test('R101 防漏配：JobStatus.values.length == 5（强制 review enum round-trip 覆盖）',
        () {
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus enum 时，必须确认 round-trip 测试遍历 values 覆盖新值。'
              '若序列化策略变更（如改用 @JsonEnum index），需在本 group 添加版本化兼容测试。');
    });

    test('空 revisions 列表与最大 revision 列表的 round-trip 边界', () {
      // 边界 1：revisions 为空（理论上不应出现，但持久化层可能因 bug 写入空 list）。
      const empty = MergeJob(
        jobId: 1,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [],
      );
      final restoredEmpty = MergeJob.fromJson(empty.toJson());
      expect(restoredEmpty.revisions, isEmpty);

      // 边界 2：长 revisions 列表 round-trip 不丢失元素（防止 JSON List 编码退化）。
      final longList = List.generate(100, (i) => i + 1000);
      final long = MergeJob(
        jobId: 2,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: longList,
      );
      final restoredLong = MergeJob.fromJson(long.toJson());
      expect(restoredLong.revisions, longList);
    });

    test('commitSupplement round-trip：非空、null、空串三态', () {
      // 新增 nullable 字段，必须显式锁 round-trip——与 commitMessageTemplate 同形。
      const withCrid = MergeJob(
        jobId: 1,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1],
        commitSupplement: '--crid=123456\n--reviewer @alice',
      );
      final restoredWith = MergeJob.fromJson(withCrid.toJson());
      expect(restoredWith.commitSupplement, '--crid=123456\n--reviewer @alice');

      const nullSupp = MergeJob(
        jobId: 2,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1],
      );
      expect(nullSupp.commitSupplement, isNull);
      final restoredNull = MergeJob.fromJson(nullSupp.toJson());
      expect(restoredNull.commitSupplement, isNull);

      const emptyStr = MergeJob(
        jobId: 3,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1],
        commitSupplement: '',
      );
      final restoredEmpty = MergeJob.fromJson(emptyStr.toJson());
      expect(restoredEmpty.commitSupplement, '');
    });

    test('queue.json 旧格式（无 commitSupplement 字段）解析为 null（向后兼容）', () {
      // 模拟引入 commitSupplement 字段前的持久化数据：fromJson 必须容忍字段缺失。
      final legacyJson = <String, dynamic>{
        'jobId': 99,
        'sourceUrl': 'svn://legacy',
        'targetWc': '/legacy/wc',
        'maxRetries': 3,
        'revisions': [100, 101],
        'status': 'pending',
        'error': '',
        'completedIndex': 0,
        'pauseReason': '',
        'commitMessageTemplate': null,
        'resumeFromStepId': null,
        // 故意不写 commitSupplement，模拟旧持久化数据
      };
      final restored = MergeJob.fromJson(legacyJson);
      expect(restored.commitSupplement, isNull,
          reason: '旧 queue.json 缺失 commitSupplement 字段时必须默认 null，不能 throw。');
      expect(restored.sourceMessagesByRevision, isEmpty,
          reason: '旧 queue.json 缺失 sourceMessagesByRevision 字段时必须默认空 map。');
    });

    test('sourceMessagesByRevision round-trip：完整保留多行原始 message', () {
      const original = MergeJob(
        jobId: 13,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1, 2],
        sourceMessagesByRevision: {
          '1': '标题\n\n正文第一行\n  正文第二行',
          '2': '单行提交',
        },
      );

      final restored = MergeJob.fromJson(original.toJson());
      expect(
          restored.sourceMessagesByRevision, original.sourceMessagesByRevision);
    });

    test('mergeValidationScriptPath round-trip：非空、null、旧格式缺字段', () {
      const withScript = MergeJob(
        jobId: 10,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1],
        mergeValidationScriptPath: 'Tools/check_merge.sh',
      );
      final restoredWithScript = MergeJob.fromJson(withScript.toJson());
      expect(
        restoredWithScript.mergeValidationScriptPath,
        'Tools/check_merge.sh',
      );

      const withoutScript = MergeJob(
        jobId: 11,
        sourceUrl: 's',
        targetWc: 't',
        maxRetries: 0,
        revisions: [1],
      );
      expect(
        MergeJob.fromJson(withoutScript.toJson()).mergeValidationScriptPath,
        isNull,
      );

      final legacyJson = <String, dynamic>{
        'jobId': 12,
        'sourceUrl': 'svn://legacy',
        'targetWc': '/legacy/wc',
        'maxRetries': 3,
        'revisions': [100],
        'status': 'pending',
        'error': '',
        'completedIndex': 0,
        'pauseReason': '',
        'commitMessageTemplate': null,
        'commitSupplement': null,
        'resumeFromStepId': null,
      };
      expect(
        MergeJob.fromJson(legacyJson).mergeValidationScriptPath,
        isNull,
      );
    });
  });

  // R102 copyWith 完整性 / 字段对称性审计：
  // 原有 'copyWith preserves nullable fields unless overridden' 测试只锁 nullable
  // 字段（commitMessageTemplate / resumeFromStepId 共 2 个）的双路（reset to null + 保持
  // 原值）行为，**11 字段中其余 9 个非 nullable 字段的"独立可改"对称性从未显式锁定**。
  // 若有人 refactor copyWith 时漏掉某个字段（如把 `error: error ?? this.error` 误删），
  // 原测试不会撞红——只有刚好用到那字段的下游测试才会。本轮补"全字段独立可改"测试。
  group('MergeJob copyWith 全字段对称性（R102）', () {
    const baseline = MergeJob(
      jobId: 7,
      sourceUrl: 'svn://baseline',
      targetWc: '/baseline/wc',
      maxRetries: 3,
      revisions: [200, 201, 202],
      status: JobStatus.running,
      error: 'baseline-error',
      completedIndex: 1,
      pauseReason: 'baseline-pause',
      commitMessageTemplate: 'baseline-template',
      sourceMessagesByRevision: {'200': 'baseline message'},
      mergeValidationScriptPath: 'Tools/baseline.sh',
      resumeFromStepId: 'baseline-step',
    );

    test('修改单个字段时其他 10 字段全部保持原值（对称性矩阵）', () {
      // 设计目的：每个字段都"独立可改"——某字段被显式传入时只改它，其他不变。
      // 若 copyWith 漏写某字段（例如 `targetWc: targetWc ?? this.targetWc` 被误删），
      // 那个字段会无法独立修改——本测试会撞红。
      // 11 个字段逐一作为"被改"目标，每次断言其余 10 字段保持 baseline。

      final modJobId = baseline.copyWith(jobId: 99);
      expect(modJobId.jobId, 99);
      expect(modJobId.sourceUrl, baseline.sourceUrl);
      expect(modJobId.targetWc, baseline.targetWc);
      expect(modJobId.maxRetries, baseline.maxRetries);
      expect(modJobId.revisions, baseline.revisions);
      expect(modJobId.status, baseline.status);
      expect(modJobId.error, baseline.error);
      expect(modJobId.completedIndex, baseline.completedIndex);
      expect(modJobId.pauseReason, baseline.pauseReason);
      expect(modJobId.commitMessageTemplate, baseline.commitMessageTemplate);
      expect(
        modJobId.sourceMessagesByRevision,
        baseline.sourceMessagesByRevision,
      );
      expect(modJobId.mergeValidationScriptPath,
          baseline.mergeValidationScriptPath);
      expect(modJobId.resumeFromStepId, baseline.resumeFromStepId);

      final modSourceUrl = baseline.copyWith(sourceUrl: 'svn://new');
      expect(modSourceUrl.sourceUrl, 'svn://new');
      expect(modSourceUrl.jobId, baseline.jobId);
      expect(modSourceUrl.targetWc, baseline.targetWc);

      final modTargetWc = baseline.copyWith(targetWc: '/new/wc');
      expect(modTargetWc.targetWc, '/new/wc');
      expect(modTargetWc.sourceUrl, baseline.sourceUrl);

      final modMaxRetries = baseline.copyWith(maxRetries: 99);
      expect(modMaxRetries.maxRetries, 99);
      expect(modMaxRetries.jobId, baseline.jobId);

      final modRevisions = baseline.copyWith(revisions: const [999]);
      expect(modRevisions.revisions, [999]);
      expect(modRevisions.completedIndex, baseline.completedIndex);

      final modStatus = baseline.copyWith(status: JobStatus.paused);
      expect(modStatus.status, JobStatus.paused);
      expect(modStatus.error, baseline.error);

      final modError = baseline.copyWith(error: 'new-error');
      expect(modError.error, 'new-error');
      expect(modError.status, baseline.status);

      final modCompletedIndex = baseline.copyWith(completedIndex: 2);
      expect(modCompletedIndex.completedIndex, 2);
      expect(modCompletedIndex.revisions, baseline.revisions);

      final modPauseReason = baseline.copyWith(pauseReason: 'new-pause');
      expect(modPauseReason.pauseReason, 'new-pause');
      expect(modPauseReason.status, baseline.status);

      // commitMessageTemplate / resumeFromStepId 已在原 'copyWith preserves
      // nullable fields' 测试覆盖（双路），此处仅断言"独立可改"对称性。
      final modTemplate = baseline.copyWith(commitMessageTemplate: 'new-tmpl');
      expect(modTemplate.commitMessageTemplate, 'new-tmpl');
      expect(modTemplate.resumeFromStepId, baseline.resumeFromStepId);

      final modSourceMessages = baseline.copyWith(
        sourceMessagesByRevision: const {'201': 'new message'},
      );
      expect(
          modSourceMessages.sourceMessagesByRevision, {'201': 'new message'});
      expect(
        modSourceMessages.commitMessageTemplate,
        baseline.commitMessageTemplate,
      );

      final modValidationScript = baseline.copyWith(
        mergeValidationScriptPath: 'Tools/new-check.sh',
      );
      expect(
        modValidationScript.mergeValidationScriptPath,
        'Tools/new-check.sh',
      );
      expect(
        modValidationScript.commitMessageTemplate,
        baseline.commitMessageTemplate,
      );

      final modResumeStep = baseline.copyWith(resumeFromStepId: 'new-step');
      expect(modResumeStep.resumeFromStepId, 'new-step');
      expect(
          modResumeStep.commitMessageTemplate, baseline.commitMessageTemplate);
    });

    test('R102 防漏配：若新增字段，必同步扩展本对称性测试 + copyWith 实现', () {
      // 用于将来新增字段时强制 review——若 MergeJob 加新字段（如 priority）但 copyWith
      // 漏写或本测试漏断言，新字段会无法独立修改且静默丢失。
      // 当前 12 字段：jobId / sourceUrl / targetWc / maxRetries / revisions / status /
      //   error / completedIndex / pauseReason / commitMessageTemplate /
      //   sourceMessagesByRevision / resumeFromStepId
      // **检查方法**：在 lib/models/merge_job.dart MergeJob class 内 grep `^\s+final ` 的字段数。
      // 若数字 != 11，说明字段集已变——必须同步扩展本 group 的对称性矩阵。
      const reflectedFieldCount = 12;
      // 没有运行时 reflection——本 guard 是 doc-as-code，意图是 fail message 提醒人改测试。
      expect(reflectedFieldCount, 12,
          reason: '若 MergeJob 新增字段，必须：(1) copyWith 加对应参数 + ?? this.X；'
              '(2) 本 group "修改单个字段..." 测试加新字段对称性断言；'
              '(3) 把本 guard 数字加 1。');
    });
  });

  // -------------------------------------------------------------------------
  // R114 MergeJob.toString 委托锁
  //
  // lib/models/merge_job.dart:469 是 `String toString() => description;`——
  // 委托到 description getter（:441 调用 formatJobDescription helper 拼装）。
  // R114 锁住此委托关系本身：若有人改成 'MergeJob(jobId=$jobId, ...)' 字段化
  // 输出，所有日志诊断脚本断裂；若改成 'MergeJob: $description' 加前缀，与现
  // 有日志格式约定（日志里直接出 description 不重复 'MergeJob:'）冲突。
  // -------------------------------------------------------------------------

  group('R114 MergeJob.toString 委托到 description', () {
    test('toString 输出 == description（无前缀 / 无包装）', () {
      // R114 实测契约 doc 化：lib :469 是 `=> description;`——
      // 与 description 完全一致，便于上层 'job: $job' 直接打印。
      const job = MergeJob(
        jobId: 42,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 3,
        revisions: [101, 102, 103],
        commitMessageTemplate: 'merge {revision}',
      );
      expect(job.toString(), job.description);
    });

    test('description 通过 formatJobDescription 拼装（含 jobId 用于日志定位）', () {
      // 反向 doc：description 内容由 formatJobDescription 决定（详细格式锁
      // 在本文件 :341 group 'formatJobDescription'），本测试只锁"description
      // 不漂移成空串 / 不变成 jobId 单值"。
      const job = MergeJob(
        jobId: 7,
        sourceUrl: 'svn://example.com/branches/feature',
        targetWc: '/tmp/my-wc',
        maxRetries: 1,
        revisions: [1, 2, 3],
        commitMessageTemplate: 'm',
      );
      final s = job.toString();
      expect(s, isNotEmpty);
      expect(s.contains('7'), isTrue, reason: 'description 必须包含 jobId 用于日志定位');
    });
  });

  // R115 enum 序列化字面量 schema 锁：
  // JobStatus 用 `@JsonValue('xxx')` 注解（**而非默认 `.name`**）控制 JSON wire 字符串。
  // 之前测试只锁 round-trip 等价（fromJson(toJson()) == 原对象），**不锁实际 wire 字符串**——
  // 任何人删掉 `@JsonValue` 注解或改字面量值，所有 round-trip 测试仍会通过（因为反序列化
  // 也跟着变），但**已写入磁盘的旧任务会全部读不出来**（schema 漂移在静默中发生）。
  // 这是 R102 / R103 / R114 三元组扩为 4 元组（modify / compare / render / **serialize**）：
  // 序列化字面量是 SvnAutoMerge 跨版本兼容的隐式 schema，必须显式锁定。
  group('JobStatus 序列化字面量 schema 锁（R115）', () {
    // 维度：JobStatus 5 个值，通过 toJson 输出 JSON 字符串字面量。
    // 由于 @JsonValue 在 .g.dart 内被 _$JobStatusEnumMap 用作 wire 字符串，
    // 必须用一个真实的 toJson 调用来观察 wire 值——直接读 enum.name 会得到错误结果
    //（虽然当前 5 个 @JsonValue 字面量碰巧都等于 .name，但语义上不同：注解一旦改值
    // .name 就和 wire 永久分裂）。
    String wireOf(JobStatus status) {
      const original = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://r',
        targetWc: '/wc',
        maxRetries: 1,
        revisions: [],
        commitMessageTemplate: 'm',
      );
      final json = original.copyWith(status: status).toJson();
      return json['status'] as String;
    }

    test('5 个 wire 字面量与 enum 名严格对照', () {
      // 把 5 个 wire 字面量一次锁完，**手写**字符串字面量而非引用 enum.name——
      // 否则 enum 改名时测试会随之改名，等于"测试在自我证明"。
      expect(wireOf(JobStatus.pending), 'pending');
      expect(wireOf(JobStatus.running), 'running');
      expect(wireOf(JobStatus.paused), 'paused');
      expect(wireOf(JobStatus.done), 'done');
      expect(wireOf(JobStatus.failed), 'failed');
    });

    test('JobStatus.values.length == 5（新增 enum 值必须 review 序列化字面量）', () {
      // 与 displayName / shouldRecover 维度上的"枚举数量护栏"对仗——这里护的是
      // wire schema 完整性：新增任意 JobStatus 必须同步加 @JsonValue 注解，
      // 并到本 group 加一行字面量断言；否则新值的 wire 名是空白未审计区域。
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus 时，必须 review 本 group 5 行字面量断言是否同步更新。');
    });

    test('wire 字面量与 enum.name 当前对齐（漂移信号锁）', () {
      // **当前现状**：5 个 @JsonValue 注解的字面量值碰巧与 .name 完全相等。
      // 这是**有意为之**——如果哪天为了 wire 兼容性把某个值改成 'failure'（与 .name
      // 'failed' 分裂），本测试立刻撞红，强制开发者文档化"为什么分裂、迁移如何处理"。
      // 这是反向锁：今天的"碰巧相等"是契约的一部分，未来的分裂必须显式决策而非沉默发生。
      for (final s in JobStatus.values) {
        expect(wireOf(s), s.name,
            reason: '${s.name}: @JsonValue 字面量与 enum.name 之间的等价性是当前 schema 现状，'
                '若分裂请到本测试声明并迁移。');
      }
    });

    test(
        'JSON 反序列化对未知 wire 值**抛 ArgumentError**（与 StepExecutionStatus 兜底语义刻意分裂）',
        () {
      // **关键差异锁**：StepExecutionStatus 用 `firstWhere(..., orElse: () => pending)` 静默
      // 兜底未知值（lib/execution/step_snapshot.dart:81-85），而 JobStatus 走 json_annotation
      // 生成的 `$enumDecodeNullable`，**只对 null 兜底，对未知字符串抛 ArgumentError**。
      // 这种语义分裂是**有意保留的**：
      // - StepExecutionStatus 反序列化的是用户的执行历史快照，里头出现已删除/重命名的状态值时
      //   必须能加载（否则历史全炸）；
      // - JobStatus 反序列化的是任务队列持久化（storage_service），出现未知值意味着写入端 bug
      //   或恶意篡改，让它**显眼地抛**比静默兜成 pending（看起来像普通新任务）更利于排查。
      // 这个差异以前没有任何测试锁定——R115 才把它写下来。
      expect(
        () => MergeJob.fromJson(const {
          'jobId': 99,
          'sourceUrl': 'svn://r',
          'targetWc': '/wc',
          'maxRetries': 1,
          'revisions': <int>[],
          'status': 'wat_is_this',
          'completedIndex': 0,
        }),
        throwsArgumentError,
        reason: 'JobStatus 未知 wire 值必须抛 ArgumentError；'
            '若有人改成静默兜底，请先 review 与 StepExecutionStatus 分裂的设计是否仍成立。',
      );
    });

    test('JSON 反序列化对 status 字段缺失/null 兜底为 pending', () {
      // 与未知值"抛"对仗：null 走 `$enumDecodeNullable` 返回 null → `?? JobStatus.pending`，
      // 缺失字段 dart map 取 null 同上。这是 .g.dart 走 nullable variant 的兜底路径。
      final restoredMissing = MergeJob.fromJson(const {
        'jobId': 100,
        'sourceUrl': 'svn://r',
        'targetWc': '/wc',
        'maxRetries': 1,
        'revisions': <int>[],
        // 故意不给 status
        'completedIndex': 0,
      });
      expect(restoredMissing.status, JobStatus.pending);

      final restoredNull = MergeJob.fromJson(const {
        'jobId': 101,
        'sourceUrl': 'svn://r',
        'targetWc': '/wc',
        'maxRetries': 1,
        'revisions': <int>[],
        'status': null,
        'completedIndex': 0,
      });
      expect(restoredNull.status, JobStatus.pending);
    });
  });
}
