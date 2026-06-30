/// MergeExecutionState 真实状态流单测——覆盖 happy path、暂停、继续、跳过
/// 推进、out-of-date 重试上限。通过构造函数注入 4 个服务的 fake 实现，避免触
/// 碰 SharedPreferences/文件系统/SVN CLI。
///
/// 测试目标：状态机层面的"对外可见状态变化"——
/// - `_status` (ExecutorStatus.idle/running/paused/completed)
/// - `_jobs` 中每个 MergeJob 的 status 与 completedIndex
/// - `notifyListeners()` 是否在状态推进的关键点触发
///
/// 不覆盖：日志字符串内容、_log 拼接细节（属于渲染层，已在其它测试覆盖）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/providers/merge_execution_state.dart';
import 'package:svn_auto_merge/services/mergeinfo_cache_service.dart';
import 'package:svn_auto_merge/services/storage_service.dart';
import 'package:svn_auto_merge/services/svn_service.dart';
import 'package:svn_auto_merge/services/svn_xml_parser.dart';
import 'package:svn_auto_merge/services/working_copy_manager.dart';

/// 内存版 StorageService —— 把 saveQueue 写入 list、loadQueue 直接返回。
class _FakeStorage extends StorageService {
  _FakeStorage({List<MergeJob>? initial})
      : _jobs = List.of(initial ?? const <MergeJob>[]),
        super.forTesting();

  List<MergeJob> _jobs;
  int saveCalls = 0;

  List<MergeJob> get currentJobs => List.unmodifiable(_jobs);

  @override
  Future<List<MergeJob>> loadQueue() async => List.of(_jobs);

  @override
  Future<void> saveQueue(List<MergeJob> jobs) async {
    saveCalls++;
    _jobs = List.of(jobs);
  }
}

/// 可编程的 WorkingCopyManager fake —— 每个动作都立即成功，merge / commit 可注
/// 入 throw 模拟失败。
class _FakeWcManager extends WorkingCopyManager {
  _FakeWcManager() : super.forTesting();

  /// 给每次 merge 调用的脚本：null = 成功；非 null = 抛 StateError(message)。
  /// 列表按调用顺序消费；用尽后默认成功。
  List<String?> mergeScript = const [];
  int _mergeCalls = 0;
  int get mergeCalls => _mergeCalls;

  /// 给每次 commit 调用的脚本：同上。
  List<String?> commitScript = const [];
  List<SvnProcessResult?> commitResultScript = const [];
  int _commitCalls = 0;
  int get commitCalls => _commitCalls;

  /// 给每次 update 调用的脚本：null = 成功（exitCode 0）；非 null = 失败
  /// （exitCode 1 + stderr=msg）。
  List<String?> updateScript = const [];
  int _updateCalls = 0;
  int get updateCalls => _updateCalls;

  int revertCalls = 0;
  int cleanupCalls = 0;
  final List<String> revertWorkingCopies = [];
  final List<String> updateWorkingCopies = [];
  final List<String> mergeWorkingCopies = [];
  final List<String> commitWorkingCopies = [];

  SvnProcessResult _ok({String stdout = ''}) => SvnProcessResult(
        exitCode: 0,
        stdout: stdout,
        stderr: '',
        pid: 0,
      );

  SvnProcessResult _fail(String stderr) => SvnProcessResult(
        exitCode: 1,
        stdout: '',
        stderr: stderr,
        pid: 0,
      );

  @override
  Future<SvnProcessResult> update(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    updateWorkingCopies.add(workingCopy);
    final i = _updateCalls++;
    final fail = i < updateScript.length ? updateScript[i] : null;
    if (fail != null) return _fail(fail);
    return _ok();
  }

  @override
  Future<SvnProcessResult> revert(
    String workingCopy, {
    bool recursive = true,
    String? sourceUrl,
    bool refreshMergeInfo = true,
  }) async {
    revertWorkingCopies.add(workingCopy);
    revertCalls++;
    return _ok();
  }

  @override
  Future<SvnProcessResult> cleanup(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    cleanupCalls++;
    return _ok();
  }

  @override
  Future<void> merge(
    String sourceUrl,
    int revision,
    String workingCopy, {
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    final i = _mergeCalls++;
    mergeWorkingCopies.add(workingCopy);
    final fail = i < mergeScript.length ? mergeScript[i] : null;
    if (fail != null) throw StateError(fail);
  }

  @override
  Future<SvnProcessResult> commit(
    String workingCopy,
    String message, {
    String? username,
    String? password,
  }) async {
    final i = _commitCalls++;
    commitWorkingCopies.add(workingCopy);
    final fail = i < commitScript.length ? commitScript[i] : null;
    if (fail != null) throw StateError(fail);
    final scriptedResult =
        i < commitResultScript.length ? commitResultScript[i] : null;
    if (scriptedResult != null) return scriptedResult;
    return _ok(stdout: 'Committed revision 123.');
  }
}

class _FakeMergeInfo extends MergeInfoCacheService {
  _FakeMergeInfo() : super.forTesting();

  int refreshCalls = 0;
  final List<String> refreshSourceUrls = [];
  final List<String> refreshTargetWcs = [];

  @override
  Future<Set<int>> getMergedRevisions(
    String sourceUrl,
    String targetWc, {
    bool forceRefresh = false,
    bool fullRefresh = false,
  }) async {
    refreshCalls++;
    refreshSourceUrls.add(sourceUrl);
    refreshTargetWcs.add(targetWc);
    return const <int>{};
  }
}

class _FakeSvn extends SvnService {
  _FakeSvn() : super.forTesting();

  /// 给每次 listConflictedFiles 调用的脚本：每条是该次返回的冲突文件列表。
  /// 用尽后默认返回空 list（无冲突 → merge 步成功推进）。
  List<List<String>> listConflictedFilesScript = const [];
  int _listConflictedFilesCalls = 0;
  int get listConflictedFilesCalls => _listConflictedFilesCalls;

  /// 给每次 countChangedFiles 调用的脚本（第四十五轮新增）：每条是该次返回的"实际改动文件数"。
  /// 用尽后默认返回 1（非空合并 → log 输出 "实际改动 1 个文件"），保持现有用例无需逐一改写脚本。
  /// 想测"空合并 / no-op" 的用例显式 push 0。
  List<int> countChangedFilesScript = const [];
  int _countChangedFilesCalls = 0;
  int get countChangedFilesCalls => _countChangedFilesCalls;

  final Map<int, List<SvnLogChangedPath>> changedPathsByRevision = {};
  final List<String> sparseCheckoutUrls = [];
  final List<String> sparseCheckoutRoots = [];
  final List<String> sparseUpdatePaths = [];
  Set<int>? mergedRevisions;
  final List<int> isRevisionMergedRevisions = [];
  final List<String> isRevisionMergedTargets = [];
  Object? isRevisionMergedError;

  @override
  Future<String> getInfo(
    String target, {
    String? item,
    String? username,
    String? password,
  }) async {
    if (item == 'url') {
      return target == '/tmp/wc' ? 'svn://src/branches/target' : target;
    }
    if (item == 'repos-root-url') {
      return 'svn://src';
    }
    return '';
  }

  @override
  Future<List<SvnLogChangedPath>> getRevisionChangedPaths({
    required String sourceUrl,
    required int revision,
    String? username,
    String? password,
  }) async {
    return List.of(changedPathsByRevision[revision] ?? const []);
  }

  @override
  Future<void> checkoutSparseRoot(
    String targetUrl,
    String targetPath, {
    String? username,
    String? password,
  }) async {
    sparseCheckoutUrls.add(targetUrl);
    sparseCheckoutRoots.add(targetPath);
    await Directory('$targetPath${Platform.pathSeparator}.svn')
        .create(recursive: true);
  }

  @override
  Future<void> updateSparsePath(
    String workingCopy,
    String relativePath, {
    String? setDepth,
    String? username,
    String? password,
  }) async {
    sparseUpdatePaths.add(
      setDepth == null ? relativePath : '$relativePath@$setDepth',
    );
    final path = relativePath.replaceAll('/', Platform.pathSeparator);
    final file = File('$workingCopy${Platform.pathSeparator}$path');
    if (setDepth == 'empty') {
      await Directory(file.path).create(recursive: true);
      return;
    }
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.writeAsString('');
    }
  }

  @override
  Future<List<String>> listConflictedFiles(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final i = _listConflictedFilesCalls++;
    if (i < listConflictedFilesScript.length) {
      return List.of(listConflictedFilesScript[i]);
    }
    return const [];
  }

  @override
  Future<int> countChangedFiles(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final i = _countChangedFilesCalls++;
    if (i < countChangedFilesScript.length) {
      return countChangedFilesScript[i];
    }
    return 1;
  }

  @override
  Future<bool> isRevisionMerged({
    required String sourceUrl,
    required int revision,
    required String target,
    String? username,
    String? password,
    bool throwOnError = false,
  }) async {
    isRevisionMergedRevisions.add(revision);
    isRevisionMergedTargets.add(target);
    if (isRevisionMergedError != null) {
      throw isRevisionMergedError!;
    }
    return mergedRevisions?.contains(revision) ?? true;
  }
}

/// 等待 MergeExecutionState 进入某状态——通过 listener 轮询；
/// timeout 后抛 TimeoutException。
Future<void> _waitFor(
  MergeExecutionState state,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (predicate()) return;
  final completer = Completer<void>();
  void listener() {
    if (predicate() && !completer.isCompleted) {
      completer.complete();
    }
  }

  state.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    state.removeListener(listener);
  }
}

MergeJob _job({
  int jobId = 1,
  List<int> revisions = const [101],
  int maxRetries = 0,
}) =>
    MergeJob(
      jobId: jobId,
      sourceUrl: 'svn://src/branches/feat',
      targetWc: '/tmp/wc',
      maxRetries: maxRetries,
      revisions: revisions,
    );

Future<String> _writeValidationScript(
  Directory dir,
  String relativePath,
  String body,
) async {
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
  await file.parent.create(recursive: true);
  if (relativePath.toLowerCase().endsWith('.bat')) {
    await file.writeAsString('@echo off\r\n$body\r\n');
  } else {
    await file.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', file.path]);
  }
  return relativePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MergeExecutionState 真实状态流（DI 后首发）', () {
    test(
        'happy path：addJob → 自动跑完单 revision → status=done / completed → mergeinfo 收录',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();

      final result = await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101, 102],
        maxRetries: 0,
      );
      expect(result.isApplied, isTrue);

      // 等到 ExecutorStatus.completed 或 idle（成功路径会经过 completed → idle）
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      expect(state.jobs, hasLength(1));
      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.completedIndex, 2);
      expect(job.error, isEmpty);
      expect(mergeInfo.refreshCalls, 2);
      // revert + cleanup 在每个 revision 的 prepare step 都走一次
      expect(wc.revertCalls, greaterThanOrEqualTo(2));
      expect(wc.cleanupCalls, greaterThanOrEqualTo(2));
      expect(wc.mergeCalls, 2);
      expect(wc.commitCalls, 2);
    });

    test('commit 返回后仓库未记录 mergeinfo → 暂停在 commit，且不写本地已合并缓存', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()..mergedRevisions = <int>{};
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      final result = await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      expect(result.isApplied, isTrue);

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('提交后未在仓库 mergeinfo 中检测到 r101'));
      expect(wc.commitCalls, 1);
      expect(svn.isRevisionMergedRevisions, [101]);
      expect(svn.isRevisionMergedTargets, ['svn://src/branches/target']);
      expect(mergeInfo.refreshCalls, 0);
    });

    test('temporary sparse working copy：只检出必要路径并在成功后清理', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
          SvnLogChangedPath(
            path: '/branches/feat/lib/new_file.dart',
            action: 'A',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.temporaryWorkingCopyPath, isNull);
      expect(svn.sparseCheckoutUrls, ['svn://src/branches/target']);
      expect(svn.sparseCheckoutRoots, hasLength(1));
      expect(await Directory(svn.sparseCheckoutRoots.single).exists(), isFalse);
      expect(svn.sparseUpdatePaths, contains('src@empty'));
      expect(svn.sparseUpdatePaths, contains('lib@empty'));
      expect(svn.sparseUpdatePaths, contains('src/a.dart'));
      expect(svn.sparseUpdatePaths, isNot(contains('lib/new_file.dart')));
      expect(
        wc.mergeWorkingCopies,
        everyElement(equals(svn.sparseCheckoutRoots.single)),
      );
      expect(
        wc.commitWorkingCopies,
        everyElement(equals(svn.sparseCheckoutRoots.single)),
      );
      expect(mergeInfo.refreshCalls, 1);
      expect(mergeInfo.refreshTargetWcs, ['svn://src/branches/target']);
    });

    test('temporary sparse working copy：targetWc 为空时使用 targetUrl 创建并执行',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      final result = await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      expect(result.isApplied, isTrue);
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.targetWc, isEmpty);
      expect(job.targetUrl, 'svn://src/branches/target');
      expect(job.temporaryWorkingCopyPath, isNull);
      expect(svn.sparseCheckoutUrls, ['svn://src/branches/target']);
      expect(wc.mergeWorkingCopies, [svn.sparseCheckoutRoots.single]);
      expect(wc.commitWorkingCopies, [svn.sparseCheckoutRoots.single]);
      expect(await Directory(svn.sparseCheckoutRoots.single).exists(), isFalse);
      expect(mergeInfo.refreshCalls, 1);
      expect(mergeInfo.refreshTargetWcs, ['svn://src/branches/target']);
    });

    test('temporary sparse working copy：跳过依赖完整目标 WC 的本地后验校验', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ]
        ..listConflictedFilesScript = const [
          ['update-conflict.dart'],
          ['merge-conflict.dart'],
        ]
        ..countChangedFilesScript = const [99];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
        mergeValidationScriptPath: 'Tools/check.py',
      );

      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(svn.listConflictedFilesCalls, 0);
      expect(svn.countChangedFilesCalls, 0);
      expect(svn.sparseUpdatePaths, isNot(contains('Tools/check.py')));
      expect(wc.commitCalls, 1);
      expect(mergeInfo.refreshCalls, 1);
      expect(state.log, contains('跳过更新后冲突检查'));
      expect(state.log, contains('跳过合并后冲突检查'));
      expect(state.log, contains('跳过本地变更数量统计'));
      expect(state.log, contains('跳过合并校验脚本'));
    });

    test('temporary sparse working copy：提交失败仍暂停在 commit，不按跳过校验误判成功', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()..commitScript = const ['svn: hook failed'];
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('svn: hook failed'));
      expect(wc.commitCalls, 1);
      expect(mergeInfo.refreshCalls, 0);
      expect(svn.isRevisionMergedRevisions, isEmpty);
    });

    test('temporary sparse working copy：commit 返回非 0 不能提示成功或推进状态', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()
        ..commitResultScript = [
          SvnProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'svn: E165001: hook failed',
            pid: 0,
          ),
        ];
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('提交失败'));
      expect(job.pauseReason, contains('退出码: 1'));
      expect(wc.commitCalls, 1);
      expect(mergeInfo.refreshCalls, 0);
      expect(svn.isRevisionMergedRevisions, isEmpty);
    });

    test('temporary sparse working copy：commit stderr 有明确失败不能提示成功', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()
        ..commitResultScript = [
          SvnProcessResult(
            exitCode: 0,
            stdout: 'Committed revision 123.',
            stderr: 'svn: E165001: hook failed',
            pid: 0,
          ),
        ];
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('提交输出包含明确失败信息'));
      expect(wc.commitCalls, 1);
      expect(mergeInfo.refreshCalls, 0);
      expect(svn.isRevisionMergedRevisions, isEmpty);
    });

    test('temporary sparse working copy：commit 成功但仓库 mergeinfo 未确认不能成功',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..mergedRevisions = <int>{}
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('提交后未在仓库 mergeinfo 中检测到 r101'));
      expect(wc.commitCalls, 1);
      expect(svn.isRevisionMergedRevisions, [101]);
      expect(mergeInfo.refreshCalls, 0);
    });

    test('temporary sparse working copy：仓库 mergeinfo 确认失败时显示无法确认提交成功',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..isRevisionMergedError = StateError('network unavailable')
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.resumeFromStepId, kCommitStepId);
      expect(job.pauseReason, contains('无法确认提交成功'));
      expect(wc.commitCalls, 1);
      expect(svn.isRevisionMergedRevisions, [101]);
      expect(mergeInfo.refreshCalls, 0);
    });

    test('temporary sparse working copy：commit 成功且仓库 mergeinfo 确认后才成功',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final svn = _FakeSvn()
        ..mergedRevisions = <int>{101}
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.completedIndex, 1);
      expect(wc.commitCalls, 1);
      expect(svn.isRevisionMergedRevisions, [101]);
      expect(mergeInfo.refreshCalls, 1);
    });

    test('temporary sparse working copy：targetUrl 缺失时暂停并要求配置目标 URL', () async {
      final storage = _FakeStorage();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();
      final result = await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      expect(result.isApplied, isTrue);
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.error, contains('目标 SVN URL'));
    });

    test('temporary sparse working copy：复杂变更暂停并提示使用完整工作副本', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/removed.dart',
            action: 'D',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.error, contains('请使用完整工作副本'));
      expect(job.temporaryWorkingCopyPath, isNull);
      expect(svn.sparseCheckoutRoots, isEmpty);
      expect(wc.mergeCalls, 0);
    });

    test('temporary sparse working copy：合并失败时保留临时目录', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()..mergeScript = const ['冲突'];
      final svn = _FakeSvn()
        ..changedPathsByRevision[101] = const [
          SvnLogChangedPath(
            path: '/branches/feat/src/a.dart',
            action: 'M',
            kind: 'file',
          ),
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        targetUrl: 'svn://src/branches/target',
        revisions: const [101],
        maxRetries: 0,
        useTemporarySparseWorkingCopy: true,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      final tempPath = job.temporaryWorkingCopyPath;
      expect(job.status, JobStatus.paused);
      expect(tempPath, isNotNull);
      expect(await Directory(tempPath!).exists(), isTrue);
      expect(wc.mergeWorkingCopies, [tempPath]);

      addTearDown(() async {
        final tempDir = Directory(tempPath);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    });

    test('paused：merge 抛错且无 maxRetries → 任务 paused，状态机停在 paused / 不自动续跑',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()
        ..mergeScript = const ['模拟合并冲突: conflict in foo.dart'];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );

      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      expect(state.hasPausedJob, isTrue);
      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.completedIndex, 0);
      expect(job.pauseReason, isNotEmpty);
      expect(mergeInfo.refreshCalls, 0);
    });

    test('cancelPausedJob：取消暂停任务 → job 变 failed，executor 回 idle', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()..mergeScript = const ['冲突'];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      await state.cancelPausedJob();

      expect(state.hasPausedJob, isFalse);
      final job = state.jobs.first;
      expect(job.status, JobStatus.failed);
      expect(state.status, ExecutorStatus.idle);
    });

    test(
        'skipCurrentRevision：暂停后跳过当前 revision → completedIndex+1，继续下一 revision',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()
        // r101 第一次 merge 抛错；后续（r102 merge）返回成功
        ..mergeScript = const ['第一次冲突'];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101, 102],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);
      expect(state.jobs.first.completedIndex, 0);

      await state.skipCurrentRevision();
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.completedIndex, 2);
      // 跳过的 r101 不刷新 mergeinfo 缓存；r102 成功后刷新仓库镜像。
      expect(mergeInfo.refreshCalls, 1);
    });

    test('resumePausedJob：暂停后修复 fake 让 merge 成功 → 任务 resume 后跑完', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager()
        // 第 1 次 merge 抛错；第 2 次（resume 后）成功
        ..mergeScript = const ['首次冲突'];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      await state.resumePausedJob();
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(job.completedIndex, 1);
      expect(mergeInfo.refreshCalls, 1);
    });

    test('maxRetries：commit 出现 out-of-date 但仍在配额内 → 自动 update + 重试，最终 done',
        () async {
      final storage = _FakeStorage();
      // 第 1 次 commit 失败（out-of-date）；第 2 次成功。maxRetries=2 允许 2 次重试。
      final wc = _FakeWcManager()
        ..commitScript = const ['svn: E160028: out-of-date'];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 2,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.idle,
          timeout: const Duration(seconds: 5));

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(wc.commitCalls, 2);
      expect(mergeInfo.refreshCalls, 1);
    });

    test('maxRetries 用尽：commit 反复 out-of-date 超过 maxRetries → 任务 paused',
        () async {
      final storage = _FakeStorage();
      // 多次失败，maxRetries=1 → 第 1 次原始 commit 失败 + 1 次重试仍失败 = pause
      final wc = _FakeWcManager()
        ..commitScript = const [
          'svn: E160028: out-of-date',
          'svn: E160028: out-of-date',
          'svn: E160028: out-of-date',
        ];
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 1,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      // 总 commit 调用次数应该等于 1 + maxRetries = 2
      expect(wc.commitCalls, 2);
      expect(state.jobs.first.status, JobStatus.paused);
    });

    test('merge 后校验脚本成功 → 继续 commit 并完成任务', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('merge-validate-ok-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final script = await _writeValidationScript(
        tempDir,
        Platform.isWindows ? 'Tools/check.bat' : 'Tools/check.sh',
        Platform.isWindows
            ? 'echo validate-ok\r\nexit /b 0'
            : 'echo validate-ok\nexit 0',
      );

      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: tempDir.path,
        revisions: const [101],
        maxRetries: 0,
        mergeValidationScriptPath: script,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(wc.commitCalls, 1);
      expect(mergeInfo.refreshCalls, 1);
    });

    test('merge 后校验脚本非 0 → 暂停在 validate，commit 不执行', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('merge-validate-exit-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final script = await _writeValidationScript(
        tempDir,
        Platform.isWindows ? 'Tools/check.bat' : 'Tools/check.sh',
        Platform.isWindows
            ? 'echo validate-failed\r\nexit /b 7'
            : 'echo validate-failed\nexit 7',
      );

      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: tempDir.path,
        revisions: const [101],
        maxRetries: 0,
        mergeValidationScriptPath: script,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.resumeFromStepId, kValidateStepId);
      expect(job.pauseReason, contains('合并校验脚本失败'));
      expect(wc.commitCalls, 0);
    });

    test('merge 后校验脚本 stderr 有输出 → 暂停在 validate，commit 不执行', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('merge-validate-stderr-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final script = await _writeValidationScript(
        tempDir,
        Platform.isWindows ? 'Tools/check.bat' : 'Tools/check.sh',
        Platform.isWindows
            ? 'echo ERROR: validate failed 1>&2\r\nexit /b 0'
            : 'echo "ERROR: validate failed" >&2\nexit 0',
      );

      final wc = _FakeWcManager();
      final state = MergeExecutionState(
        storageService: _FakeStorage(),
        wcManager: wc,
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: tempDir.path,
        revisions: const [101],
        maxRetries: 0,
        mergeValidationScriptPath: script,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      expect(job.resumeFromStepId, kValidateStepId);
      expect(job.pauseReason, contains('明确错误信息'));
      expect(wc.commitCalls, 0);
    });
  });

  group('init：从持久化恢复暂停任务（DI）', () {
    test('init 时检测到 paused 任务 → 不自动续跑，executor 保持 idle，hasPausedJob=true',
        () async {
      final pausedJob = _job().copyWith(
        status: JobStatus.paused,
        pauseReason: '手动暂停',
        completedIndex: 0,
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );

      await state.init();

      expect(state.hasPausedJob, isTrue);
      expect(state.status, ExecutorStatus.idle);
      expect(state.jobs.first.status, JobStatus.paused);
    });
  });

  group('updateJobMaxRetries（outOfDate 暂停态调整重试上限）', () {
    test('newMax > 当前 maxRetries → 持久化新值并 notifyListeners', () async {
      final pausedJob = _job(maxRetries: 1).copyWith(
        status: JobStatus.paused,
        pauseReason: 'svn: E160028 out-of-date',
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();
      var notified = 0;
      state.addListener(() => notified++);
      final priorSaveCalls = storage.saveCalls;

      final ok = await state.updateJobMaxRetries(1, 5);

      expect(ok, isTrue);
      expect(state.jobs.first.maxRetries, 5);
      expect(storage.saveCalls, priorSaveCalls + 1);
      expect(storage.currentJobs.first.maxRetries, 5);
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('newMax == 当前 maxRetries → 不持久化、不 notify、返回 false', () async {
      final pausedJob = _job(maxRetries: 3).copyWith(
        status: JobStatus.paused,
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();
      var notified = 0;
      state.addListener(() => notified++);
      final priorSaveCalls = storage.saveCalls;

      final ok = await state.updateJobMaxRetries(1, 3);

      expect(ok, isFalse);
      expect(state.jobs.first.maxRetries, 3);
      expect(storage.saveCalls, priorSaveCalls);
      expect(notified, 0);
    });

    test('newMax < 当前 maxRetries → 拒绝调低、返回 false', () async {
      final pausedJob = _job(maxRetries: 5).copyWith(
        status: JobStatus.paused,
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();
      final priorSaveCalls = storage.saveCalls;

      final ok = await state.updateJobMaxRetries(1, 2);

      expect(ok, isFalse);
      expect(state.jobs.first.maxRetries, 5);
      expect(storage.saveCalls, priorSaveCalls);
    });

    test('newMax 为负数 → 拒绝、返回 false', () async {
      final pausedJob = _job(maxRetries: 1).copyWith(
        status: JobStatus.paused,
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();

      expect(await state.updateJobMaxRetries(1, -1), isFalse);
      expect(state.jobs.first.maxRetries, 1);
    });

    test('jobId 不存在 → 返回 false、不动队列', () async {
      final pausedJob = _job(jobId: 1, maxRetries: 1).copyWith(
        status: JobStatus.paused,
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();
      final priorSaveCalls = storage.saveCalls;

      final ok = await state.updateJobMaxRetries(999, 10);

      expect(ok, isFalse);
      expect(state.jobs.first.maxRetries, 1);
      expect(storage.saveCalls, priorSaveCalls);
    });

    test('不动 status / completedIndex / pauseReason / resumeFromStepId',
        () async {
      final pausedJob = _job(maxRetries: 1).copyWith(
        status: JobStatus.paused,
        completedIndex: 0,
        pauseReason: 'svn: E160028 out-of-date',
        resumeFromStepId: 'commit',
      );
      final storage = _FakeStorage(initial: [pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: _FakeWcManager(),
        mergeInfoService: _FakeMergeInfo(),
        svnService: _FakeSvn(),
      );
      await state.init();

      final ok = await state.updateJobMaxRetries(1, 10);

      expect(ok, isTrue);
      final updated = state.jobs.first;
      expect(updated.maxRetries, 10);
      expect(updated.status, JobStatus.paused);
      expect(updated.completedIndex, 0);
      expect(updated.pauseReason, 'svn: E160028 out-of-date');
      expect(updated.resumeFromStepId, 'commit');
    });
  });

  group('_runMergeStep merge 后补 listConflictedFiles 后验（第三十三轮）', () {
    test(
        'merge 后 listConflictedFiles 返回非空 → 任务暂停归 merge 步而非 commit 步、wc.commitCalls=0',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager(); // merge / commit 默认全成功，不抛
      final svn = _FakeSvn()
        ..listConflictedFilesScript = const [
          [], // 第三十四轮：update 步后验先返回空（update 干净）
          ['lib/foo.dart', 'lib/bar.dart'], // merge 步后验返回 'C' 文件
        ];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      // 暂停归 merge 步 — resumeFromStepId 应为 merge 而非 commit
      expect(job.resumeFromStepId, kMergeStepId);
      // pauseReason 含本轮抛的 StateError 文案碎片
      expect(job.pauseReason, contains('合并 r101 产生'));
      expect(job.pauseReason, contains('2 个冲突文件'));
      // commit 不应被调用 — 错位归位锁
      expect(wc.commitCalls, 0);
      // listConflictedFiles 至少被调用 1 次（merge 后验）
      expect(svn.listConflictedFilesCalls, greaterThanOrEqualTo(1));
      // 未合并成功 → mergeinfo 不收录
      expect(mergeInfo.refreshCalls, 0);
    });

    test('merge 后 listConflictedFiles 返回空 → 正常进 commit 步，最终 done', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final svn = _FakeSvn(); // listConflictedFilesScript 为空 → 默认返回空 list
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(wc.commitCalls, 1);
      expect(svn.listConflictedFilesCalls, greaterThanOrEqualTo(1));
      expect(mergeInfo.refreshCalls, 1);
    });
  });

  group('_runMergeStep doc-as-test（第三十三轮）', () {
    final src =
        File('lib/providers/merge_execution_state.dart').readAsStringSync();
    final start = src.indexOf(
        'Future<Map<String, dynamic>> _runMergeStep(MergeJob job, int revision) async {');
    final body = start > 0 ? src.substring(start, start + 2600) : '';

    test('方法签名稳定', () {
      expect(start, greaterThan(0));
    });

    test('merge 后调用 listConflictedFiles 后验', () {
      expect(
          body.contains('await _svnService.listConflictedFiles(workingCopy)'),
          isTrue);
    });

    test('listConflictedFiles 非空时抛 StateError 含 "合并 r" + "冲突文件" 字面量', () {
      expect(body.contains('throw StateError('), isTrue);
      expect(body.contains("'合并 r"), isTrue);
      expect(body.contains('个冲突文件，请手动解决'), isTrue);
    });

    test('throw 含 conflicts.length 透传冲突数量', () {
      expect(body.contains(r'${conflicts.length} 个冲突文件'), isTrue);
    });

    test('listConflictedFiles 在 await _wcManager.merge 之后调用（顺序锁）', () {
      final mergeIdx = body.indexOf('await _wcManager.merge(');
      final listIdx = body.indexOf('await _svnService.listConflictedFiles(');
      expect(mergeIdx, greaterThan(0));
      expect(listIdx, greaterThan(0));
      expect(listIdx, greaterThan(mergeIdx));
    });

    test('throw 文案含"冲突"二字（_looksLikeConflict 匹配锚点）', () {
      // _runRevision catch 块通过 isMergeConflictMessage 判断 "冲突" / "conflict"
      // / "tree conflict"，本 throw 走"冲突"中文路径，确保暂停归 merge 步而非
      // 走默认 evaluateStepFailure → pause（行为一致但语义锚点不同）。
      expect(body.contains('冲突文件'), isTrue);
    });

    test('成功路径输出"r\$revision 合并成功"日志（第四十五轮：日志含变更数 / 空合并提示）', () {
      // 第四十五轮把单一 "r$revision 合并成功" 拆为两路：
      //   - changedCount > 0 → "r$revision 合并成功 — 实际改动 N 个文件"
      //   - changedCount == 0 → "r$revision 合并成功 — 但未产生任何差异（空合并 / no-op，源与目标可能无新增提交）"
      // 字面量"r$revision 合并成功"作为公共前缀仍存在；这里锁定前缀 + 两条分支字面量都在源码里，
      // 防止误回退到合并的"r$revision 合并成功"裸日志（用户从日志里就分辨不出"成功"是真有产出还是 no-op）。
      expect(body.contains("'[INFO] r\$revision 合并成功"), isTrue);
      expect(body.contains('实际改动'), isTrue);
      expect(body.contains('空合并'), isTrue);
    });

    test(
        '_runMergeStep 空合并提示（第四十五轮）：merge 后调 countChangedFiles，0 时打印 no-op 提示并写入 step output',
        () {
      // 锁定 svn_service.countChangedFiles 在 _runMergeStep 内被调用（merge 后、conflicts 检查之后）。
      expect(
        body.contains('await _svnService.countChangedFiles(workingCopy)'),
        isTrue,
      );
      // 锁定 step output 多了 changedFilesCount 字段（步骤快照对话框可见）。
      expect(body.contains("'changedFilesCount': changedCount"), isTrue);
      // 顺序：merge → listConflictedFiles → countChangedFiles → 日志 → return
      final mergeIdx = body.indexOf('await _wcManager.merge(');
      final listIdx = body.indexOf('await _svnService.listConflictedFiles(');
      final countIdx = body.indexOf('await _svnService.countChangedFiles(');
      final returnIdx = body.indexOf("'changedFilesCount': changedCount");
      expect(mergeIdx, greaterThan(0));
      expect(listIdx, greaterThan(mergeIdx));
      expect(countIdx, greaterThan(listIdx));
      expect(returnIdx, greaterThan(countIdx));
    });
  });

  group('_runUpdateStep update 后补 listConflictedFiles 后验（第三十四轮）', () {
    test(
        'update 后 listConflictedFiles 返回非空 → 任务暂停归 update 步而非 merge 步、wc.mergeCalls=0',
        () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager(); // update / merge / commit 默认全成功
      final svn = _FakeSvn()
        ..listConflictedFilesScript = const [
          ['lib/foo.dart', 'lib/bar.dart', 'lib/baz.dart'],
        ];
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.paused);

      final job = state.jobs.first;
      expect(job.status, JobStatus.paused);
      // 暂停归 update 步 — resumeFromStepId 应为 update 而非 merge / commit
      expect(job.resumeFromStepId, kUpdateStepId);
      // pauseReason 含本轮抛的 StateError 文案碎片
      expect(job.pauseReason, contains('更新工作副本产生'));
      expect(job.pauseReason, contains('3 个冲突文件'));
      // merge / commit 不应被调用 — 错位归位锁
      expect(wc.mergeCalls, 0);
      expect(wc.commitCalls, 0);
      // listConflictedFiles 至少被调用 1 次（update 后验）
      expect(svn.listConflictedFilesCalls, greaterThanOrEqualTo(1));
      // 未合并成功 → mergeinfo 不收录
      expect(mergeInfo.refreshCalls, 0);
    });

    test('update 后 listConflictedFiles 返回空 → 正常进 merge 步，最终 done', () async {
      final storage = _FakeStorage();
      final wc = _FakeWcManager();
      final svn = _FakeSvn(); // listConflictedFilesScript 为空 → 默认返回空 list
      final mergeInfo = _FakeMergeInfo();
      final state = MergeExecutionState(
        storageService: storage,
        wcManager: wc,
        mergeInfoService: mergeInfo,
        svnService: svn,
      );

      await state.init();
      await state.addJob(
        sourceUrl: 'svn://src/branches/feat',
        targetWc: '/tmp/wc',
        revisions: const [101],
        maxRetries: 0,
      );
      await _waitFor(state, () => state.status == ExecutorStatus.idle);

      final job = state.jobs.first;
      expect(job.status, JobStatus.done);
      expect(wc.mergeCalls, 1);
      expect(wc.commitCalls, 1);
      // listConflictedFiles 应被调用至少 2 次（update 后验 + merge 后验）
      expect(svn.listConflictedFilesCalls, greaterThanOrEqualTo(2));
      expect(mergeInfo.refreshCalls, 1);
    });
  });

  group('_runUpdateStep doc-as-test（第三十四轮）', () {
    final src =
        File('lib/providers/merge_execution_state.dart').readAsStringSync();
    final start = src.indexOf('Future<Map<String, dynamic>> _runUpdateStep(');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('方法签名稳定', () {
      expect(start, greaterThan(0));
    });

    test('update 成功后调用 listConflictedFiles 后验', () {
      expect(
          body.contains('await _svnService.listConflictedFiles(workingCopy)'),
          isTrue);
    });

    test('listConflictedFiles 非空时抛 StateError 含 "更新工作副本产生" + "冲突文件" 字面量', () {
      expect(body.contains('throw StateError('), isTrue);
      expect(body.contains("'更新工作副本产生 "), isTrue);
      expect(body.contains('个冲突文件，请手动解决'), isTrue);
    });

    test('throw 含 conflicts.length 透传冲突数量', () {
      expect(body.contains(r'${conflicts.length} 个冲突文件'), isTrue);
    });

    test('listConflictedFiles 在 result.isSuccess 之后调用（顺序锁）', () {
      final resultIdx = body.indexOf('await _wcManager.update(');
      final listIdx = body.indexOf('await _svnService.listConflictedFiles(');
      expect(resultIdx, greaterThan(0));
      expect(listIdx, greaterThan(0));
      expect(listIdx, greaterThan(resultIdx));
    });

    test('listConflictedFiles 后验在 "已更新到最新版本" 日志前（成功语义保护）', () {
      // 后验失败必须先抛错，不能让"已更新到最新版本"日志误导用户。
      final listIdx = body.indexOf('await _svnService.listConflictedFiles(');
      final logIdx = body.indexOf("'[INFO] 工作副本已更新到最新版本'");
      expect(listIdx, greaterThan(0));
      expect(logIdx, greaterThan(0));
      expect(logIdx, greaterThan(listIdx));
    });
  });
}
