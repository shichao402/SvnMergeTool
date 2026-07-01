/// `svn_failure_kind.dart` 分类与展示信息单测。
///
/// 测试维度：
/// - 每个 kind 至少 1 条代表性错误样本（错误码 + 关键词都验）；
/// - 边界：null / 空串 / 仅空白 → unknown；
/// - 优先级：tree conflict 必须先于 text conflict（含 'conflict' 不抢）；
/// - presentationFor 对 enum 全集都有非空映射。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';

void main() {
  group('classifySvnFailure 边界', () {
    test('null → unknown', () {
      expect(classifySvnFailure(null), SvnFailureKind.unknown);
    });
    test('空串 → unknown', () {
      expect(classifySvnFailure(''), SvnFailureKind.unknown);
    });
    test('仅空白 → unknown', () {
      expect(classifySvnFailure('   \n  '), SvnFailureKind.unknown);
    });
    test('完全无关字符串 → unknown', () {
      expect(classifySvnFailure('某种神秘错误'), SvnFailureKind.unknown);
    });
  });

  group('classifySvnFailure tree conflict 优先级', () {
    test('"tree conflict" 字面量 → treeConflict', () {
      expect(
        classifySvnFailure("svn: warning: W155010: 'a/b' is a 'tree conflict'"),
        SvnFailureKind.treeConflict,
      );
    });
    test('错误码 E195020 → treeConflict', () {
      expect(
        classifySvnFailure('svn: E195020: tree conflict at path'),
        SvnFailureKind.treeConflict,
      );
    });
    test('中文 "目录冲突" → treeConflict', () {
      expect(classifySvnFailure('合并时遇到目录冲突'), SvnFailureKind.treeConflict);
    });
    test('"tree conflict" 与 "conflict" 共存 → treeConflict 抢到（优先级保证）', () {
      expect(
        classifySvnFailure('Found tree conflict and other conflict markers'),
        SvnFailureKind.treeConflict,
      );
    });
  });

  group('classifySvnFailure text conflict', () {
    test('<<<<<<< marker → textConflict', () {
      expect(
        classifySvnFailure('Conflict in file:\n<<<<<<< .mine'),
        SvnFailureKind.textConflict,
      );
    });
    test('"Conflict discovered in" → textConflict', () {
      expect(
        classifySvnFailure('Conflict discovered in foo.dart'),
        SvnFailureKind.textConflict,
      );
    });
    test('"text conflict" 字面量 → textConflict', () {
      expect(classifySvnFailure('text conflict in foo'),
          SvnFailureKind.textConflict);
    });
    test('中文 "文本冲突" → textConflict', () {
      expect(classifySvnFailure('发生文本冲突'), SvnFailureKind.textConflict);
    });
    test('中文 "冲突" 但不含 "目录" → textConflict（兜底归本类）', () {
      expect(classifySvnFailure('合并产生冲突'), SvnFailureKind.textConflict);
    });
  });

  group('classifySvnFailure out-of-date', () {
    test('错误码 E160028 → outOfDate', () {
      expect(
        classifySvnFailure("svn: E160028: File '/foo' is out of date"),
        SvnFailureKind.outOfDate,
      );
    });
    test('"out-of-date" 连字符 → outOfDate', () {
      expect(
          classifySvnFailure('item is out-of-date'), SvnFailureKind.outOfDate);
    });
    test('"out of date" 空格 → outOfDate', () {
      expect(classifySvnFailure('resource is out of date'),
          SvnFailureKind.outOfDate);
    });
  });

  group('classifySvnFailure missing CRID', () {
    test('"CRID" → missingCrid', () {
      expect(
        classifySvnFailure('pre-commit hook failed: missing CRID'),
        SvnFailureKind.missingCrid,
      );
    });

    test('"Code-Review-Rule" → missingCrid', () {
      expect(
        classifySvnFailure(
            'Code-Review-Rule: commit message requires review id'),
        SvnFailureKind.missingCrid,
      );
    });
  });

  group('classifySvnFailure auth', () {
    test('错误码 E170001 → authFailed', () {
      expect(
        classifySvnFailure('svn: E170001: Authentication failed'),
        SvnFailureKind.authFailed,
      );
    });
    test('"authentication failed" → authFailed', () {
      expect(classifySvnFailure('Authentication failed'),
          SvnFailureKind.authFailed);
    });
    test('"authorization failed" → authFailed', () {
      expect(classifySvnFailure('Authorization failed'),
          SvnFailureKind.authFailed);
    });
    test('"access denied" → authFailed', () {
      expect(classifySvnFailure('Access denied'), SvnFailureKind.authFailed);
    });
    test('中文 "认证失败" → authFailed', () {
      expect(classifySvnFailure('SVN 认证失败'), SvnFailureKind.authFailed);
    });
  });

  group('classifySvnFailure locked', () {
    test('错误码 E155004 → locked', () {
      expect(
        classifySvnFailure("svn: E155004: '/wc' is locked"),
        SvnFailureKind.locked,
      );
    });
    test('"is locked" → locked', () {
      expect(
          classifySvnFailure("path '/foo' is locked"), SvnFailureKind.locked);
    });
    test('"svn cleanup" 提示 → locked', () {
      expect(
        classifySvnFailure("run 'svn cleanup' to remove locks"),
        SvnFailureKind.locked,
      );
    });
    test('中文 "已被锁定" → locked', () {
      expect(classifySvnFailure('工作副本已被锁定'), SvnFailureKind.locked);
    });
  });

  group('classifySvnFailure working copy corrupt', () {
    test('错误码 E155017 → workingCopyCorrupt', () {
      expect(
        classifySvnFailure('svn: E155017: working copy needs upgrade'),
        SvnFailureKind.workingCopyCorrupt,
      );
    });
    test('"is not a working copy" → workingCopyCorrupt', () {
      expect(
        classifySvnFailure("'/tmp/foo' is not a working copy"),
        SvnFailureKind.workingCopyCorrupt,
      );
    });
    test('"missing or not a directory" → workingCopyCorrupt', () {
      expect(
        classifySvnFailure("'/foo' is missing or not a directory"),
        SvnFailureKind.workingCopyCorrupt,
      );
    });
  });

  group('classifySvnFailure not found', () {
    test('错误码 E170000 → notFound', () {
      expect(
        classifySvnFailure('svn: E170000: Path not found'),
        SvnFailureKind.notFound,
      );
    });
    test('"path not found" → notFound', () {
      expect(classifySvnFailure('Path not found in repo'),
          SvnFailureKind.notFound);
    });
    test('"no such revision" → notFound', () {
      expect(classifySvnFailure('No such revision 12345'),
          SvnFailureKind.notFound);
    });
    test('"does not exist" → notFound', () {
      expect(
        classifySvnFailure("URL '/foo' does not exist"),
        SvnFailureKind.notFound,
      );
    });
    test('中文 "不存在" → notFound', () {
      expect(classifySvnFailure('指定的 revision 不存在'), SvnFailureKind.notFound);
    });
  });

  group('classifySvnFailure network', () {
    test('"Connection refused" → network', () {
      expect(classifySvnFailure('Connection refused'), SvnFailureKind.network);
    });
    test('"Could not connect" → network', () {
      expect(
        classifySvnFailure('Could not connect to server'),
        SvnFailureKind.network,
      );
    });
    test('"timed out" → network', () {
      expect(
          classifySvnFailure('Connection timed out'), SvnFailureKind.network);
    });
    test('中文 "无法连接" → network', () {
      expect(classifySvnFailure('无法连接 SVN 服务器'), SvnFailureKind.network);
    });
  });

  group('presentationFor', () {
    test('每个 kind 都有非空 label / hint', () {
      for (final kind in SvnFailureKind.values) {
        final p = presentationFor(kind);
        expect(p.label, isNotEmpty, reason: '$kind 缺 label');
        expect(p.hint, isNotEmpty, reason: '$kind 缺 hint');
      }
    });

    test('severe 与 normal 双 severity 都有覆盖（避免全 normal 退化）', () {
      final sev = SvnFailureKind.values
          .map(presentationFor)
          .map((p) => p.severity)
          .toSet();
      expect(sev.contains(SvnFailureSeverity.severe), isTrue);
      expect(sev.contains(SvnFailureSeverity.normal), isTrue);
    });

    test('label 长度 <= 6 字（chip 渲染约束）', () {
      for (final kind in SvnFailureKind.values) {
        expect(presentationFor(kind).label.length, lessThanOrEqualTo(6),
            reason: '$kind label 过长');
      }
    });
  });
}
