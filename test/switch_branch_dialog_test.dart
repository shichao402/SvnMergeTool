import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/screens/components/dialogs/switch_branch_dialog.dart';

void main() {
  group('SVN URL browser helpers', () {
    test('trimSvnUrlTrailingSlash trims whitespace and trailing slashes', () {
      expect(
        trimSvnUrlTrailingSlash('  svn://host/repo/branches/v1///  '),
        'svn://host/repo/branches/v1',
      );
    });

    test(
        'joinSvnUrl joins base and child while removing duplicate edge slashes',
        () {
      expect(
        joinSvnUrl('svn://host/repo/branches/', '/feature-a/'),
        'svn://host/repo/branches/feature-a',
      );
    });

    test('parentSvnUrl returns repository parent without crossing host root',
        () {
      expect(
        parentSvnUrl('svn://host/repo/branches/feature-a'),
        'svn://host/repo/branches',
      );
      expect(parentSvnUrl('svn://host/repo'), isNull);
    });
  });
}
