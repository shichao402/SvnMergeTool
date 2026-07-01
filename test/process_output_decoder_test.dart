import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/utils/process_output_decoder.dart';

void main() {
  group('decodeUnicodeEscapes', () {
    test('returns input unchanged when no escapes present', () {
      expect(decodeUnicodeEscapes('hello world'), 'hello world');
      expect(decodeUnicodeEscapes(''), '');
    });

    test('decodes a single {U+xxxx} escape', () {
      expect(decodeUnicodeEscapes('hello {U+4F60}'), 'hello 你');
    });

    test('decodes multiple escapes in one string', () {
      expect(decodeUnicodeEscapes('{U+4F60}{U+597D}!'), '你好!');
    });

    test('decodes SVN warning message from logs', () {
      expect(
        decodeUnicodeEscapes(
          'svn:  {U+8B66}{U+544A}: W200017: Property missing',
        ),
        'svn:  警告: W200017: Property missing',
      );
    });

    test('leaves malformed escapes untouched', () {
      expect(decodeUnicodeEscapes('{U+ABC}'), '{U+ABC}');
      expect(decodeUnicodeEscapes('{4F60}'), '{4F60}');
    });
  });

  group('decodeProcessOutput', () {
    test('decodes UTF-8 bytes read via latin1', () {
      final latin1Mapped = String.fromCharCodes(utf8.encode('正在升级'));
      expect(decodeProcessOutput(latin1Mapped), '正在升级');
    });

    test('decodes legacy {U+xxxx} transport format directly', () {
      expect(
        decodeProcessOutput('{U+6B63}{U+5728}{U+5347}{U+7EA7}'),
        '正在升级',
      );
    });

    test('empty input returns empty', () {
      expect(decodeProcessOutput(''), '');
    });

    test('ASCII-only output passes through unchanged', () {
      expect(
        decodeProcessOutput('svn: E165001: Commit blocked'),
        'svn: E165001: Commit blocked',
      );
    });
  });

  group('containsUnicodeEscapes / looksLikeMojibake', () {
    test('detects {U+xxxx} markers', () {
      expect(containsUnicodeEscapes('{U+4F60}'), isTrue);
      expect(containsUnicodeEscapes('你好'), isFalse);
    });

    test('detects replacement characters as mojibake', () {
      expect(looksLikeMojibake('abc\uFFFDdef'), isTrue);
      expect(looksLikeMojibake('hello'), isFalse);
    });
  });
}
