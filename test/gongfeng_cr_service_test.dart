import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/gongfeng_cr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildShellCommand', () {
    test('quotes args and cd into working directory', () {
      expect(
        buildShellCommand(
          executable: 'gf',
          arguments: ['cr', 'create', "/wc/a'b"],
          workingDirectory: "/Users/dev/work/b1",
        ),
        "cd '/Users/dev/work/b1' && gf 'cr' 'create' '/wc/a'\"'\"'b'",
      );
    });
  });

  group('buildGfCrCreateArgs', () {
    test('builds quick create command with target path, title and description',
        () {
      expect(
        buildGfCrCreateArgs(
          targetWc: '/Users/dev/work/b1',
          title: 'Merge r3: b1 -> b2',
          description: 'Revision: r3',
        ),
        [
          'cr',
          'create',
          '/Users/dev/work/b1',
          '--quick',
          '--title',
          'Merge r3: b1 -> b2',
          '--description',
          'Revision: r3',
        ],
      );
    });
  });

  group('extractCrIdFromGfOutput', () {
    test('extracts explicit CRID', () {
      expect(extractCrIdFromGfOutput('CRID:123456'), '123456');
    });

    test('extracts IID as CR id fallback', () {
      expect(extractCrIdFromGfOutput('create success, IID: 789'), '789');
    });

    test('extracts id from review URL', () {
      expect(
        extractCrIdFromGfOutput('https://git.woa.com/foo/bar/code_reviews/42'),
        '42',
      );
    });

    test('returns null when output has no id', () {
      expect(extractCrIdFromGfOutput('create success'), isNull);
    });
  });

  group('extractCodeReviewUrlFromGfOutput', () {
    test('extracts code review URL', () {
      expect(
        extractCodeReviewUrlFromGfOutput(
          'created: https://git.woa.com/foo/bar/code_reviews/42',
        ),
        'https://git.woa.com/foo/bar/code_reviews/42',
      );
    });

    test('returns null when no review URL exists', () {
      expect(extractCodeReviewUrlFromGfOutput('CRID: 42'), isNull);
    });
  });

  group('GongfengCrService.createCodeReview', () {
    test('runs gf cr create in target working copy and returns supplement',
        () async {
      late String executable;
      late List<String> args;
      late String? capturedWorkingDirectory;
      final service = GongfengCrService.forTesting(
        runner: (exe, arguments, {workingDirectory}) async {
          executable = exe;
          args = arguments;
          capturedWorkingDirectory = workingDirectory;
          return ProcessResult(
            1,
            0,
            'CRID: 456 https://git.woa.com/foo/bar/code_reviews/456',
            '',
          );
        },
      );

      final result = await service.createCodeReview(
        targetWc: '/wc/b1',
        title: 'title',
        description: 'desc',
      );

      expect(executable, 'gf');
      expect(args, [
        'cr',
        'create',
        '/wc/b1',
        '--quick',
        '--title',
        'title',
        '--description',
        'desc',
      ]);
      expect(capturedWorkingDirectory, '/wc/b1');
      expect(result.crId, '456');
      expect(result.commitSupplement, '--crid=456 title');
      expect(result.reviewUrl, 'https://git.woa.com/foo/bar/code_reviews/456');
    });

    test('turns login prompt into friendly exception', () async {
      final service = GongfengCrService.forTesting(
        runner: (_, __, {workingDirectory}) async {
          return ProcessResult(
              1, 1, '', 'Please login first to use GONGFENG CLI');
        },
      );

      expect(
        () => service.createCodeReview(
          targetWc: '/wc/b1',
          title: 'title',
          description: 'desc',
        ),
        throwsA(isA<GongfengCrException>()
            .having(
              (e) => e.message,
              'message',
              contains('gf auth login'),
            )
            .having(
              (e) => e.loginRequired,
              'loginRequired',
              isTrue,
            )),
      );
    });
  });

  group('formatCrCommitSupplement', () {
    test('uses --crid format expected by SVN hook', () {
      expect(formatCrCommitSupplement('123'), '--crid=123');
    });

    test('appends title after --crid when available', () {
      expect(
        formatCrCommitSupplement('7', title: 'Merge r5: trunk -> b1'),
        '--crid=7 Merge r5: trunk -> b1',
      );
    });
  });
}
