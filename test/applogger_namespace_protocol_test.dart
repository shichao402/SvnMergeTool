import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R137 复用，R138 沿用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// 列出 lib/ 下所有 .dart 文件（递归）。
List<File> _allLibDartFiles() {
  final dir = Directory('lib');
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// 统计某文件内 `AppLogger.<tag>` 出现的 tag 集合（剥离注释后）。
Set<String> _tagsInCodeOf(File f) {
  final code = _stripComments(f.readAsStringSync());
  final re = RegExp(r'AppLogger\.([a-zA-Z]+)');
  return re.allMatches(code).map((m) => m.group(1)!).toSet();
}

int _countTagInCode(File f, String tag) {
  final code = _stripComments(f.readAsStringSync());
  final re = RegExp(r'AppLogger\.' + tag + r'\b');
  return re.allMatches(code).length;
}

/// **R138 AppLogger tag namespace 协议审计**
///
/// 协议要点（详见 lib/services/logger_service.dart 内 `class AppLogger` 上方
/// R138 doc-block）：
/// - 8 tag 全集：svn / storage / app / ui / preload / config / merge / credential
/// - credential 故意 0 callsite（M4 negative space invariant，namespace 维度复用）
/// - 跨 tag 不变量 N1/N2/N3/N4
///   - N1 文件 tag 单一性
///   - N2 跨文件 tag 共享必为同 domain
///   - N3 tag 集合穷尽闭合（必先在 AppLogger 声明，0 处 ad-hoc `.tagged(`）
///   - N4 namespace 故意空 = 决策 doc 化
void main() {
  final logger = File('lib/services/logger_service.dart');

  group('R138 group 1：AppLogger 类声明锁（tag 全集快照）', () {
    test('AppLogger 类声明 8 个 tag 字段（svn/config/credential/storage/merge/ui/app/preload）', () {
      final code = _stripComments(logger.readAsStringSync());
      const expectedTags = [
        'svn',
        'config',
        'credential',
        'storage',
        'merge',
        'ui',
        'app',
        'preload',
      ];
      for (final t in expectedTags) {
        expect(
          code.contains('static final $t = logger.tagged('),
          isTrue,
          reason: 'AppLogger.$t 字段必须存在',
        );
      }
    });

    test('AppLogger 类无第 9 个 tag（穷尽闭合 N3）', () {
      final code = _stripComments(logger.readAsStringSync());
      final classStart = code.indexOf('class AppLogger {');
      expect(classStart, greaterThanOrEqualTo(0));
      final classEnd = code.indexOf('}', classStart);
      final classBody = code.substring(classStart, classEnd);
      final fieldRe = RegExp(r'static final (\w+) = logger\.tagged\(');
      final tags = fieldRe
          .allMatches(classBody)
          .map((m) => m.group(1)!)
          .toSet();
      expect(tags.length, 8,
          reason: '当前协议锁 8 个 tag——新增/删除必须同步本测试');
    });

    test('全 lib/ 内 0 处 ad-hoc `logger.tagged(` 字面量（强制走 AppLogger 入口）', () {
      var hits = 0;
      for (final f in _allLibDartFiles()) {
        // logger_service.dart 自身允许定义 .tagged，跳过
        if (f.path.endsWith('services/logger_service.dart')) continue;
        final code = _stripComments(f.readAsStringSync());
        hits += RegExp(r'logger\.tagged\(').allMatches(code).length;
      }
      expect(hits, 0,
          reason: 'N3 穷尽闭合：新增 tag 必先在 AppLogger 类声明，禁止 ad-hoc');
    });
  });

  group('R138 group 2：N1 文件 tag 单一性律（active 文件每个最多 1 tag）', () {
    test('每个 active 文件 AppLogger callsite 使用同一 tag（多 tag 文件 = 0）', () {
      final violations = <String>[];
      for (final f in _allLibDartFiles()) {
        if (f.path.endsWith('services/logger_service.dart')) continue;
        final tags = _tagsInCodeOf(f);
        if (tags.length > 1) {
          violations.add('${f.path}: $tags');
        }
      }
      expect(violations, isEmpty,
          reason: 'N1 文件 tag 单一性律——多 tag 文件应被拆分而非允许混用');
    });
  });

  group('R138 group 3：tag → 文件域 mapping 快照锁（N2 跨文件共享时机）', () {
    test('svn tag 域 = {log_sync_service, svn_service, svn_xml_parser, working_copy_manager}', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('svn'))
          .map((f) => f.path)
          .toSet();
      expect(files, {
        'lib/services/log_sync_service.dart',
        'lib/services/svn_service.dart',
        'lib/services/svn_xml_parser.dart',
        'lib/services/working_copy_manager.dart',
      });
    });

    test('storage tag 域 = {log_cache_service, mergeinfo_cache_service, log_filter_service, log_file_cache_service, storage_service}', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('storage'))
          .map((f) => f.path)
          .toSet();
      expect(files, {
        'lib/services/log_cache_service.dart',
        'lib/services/mergeinfo_cache_service.dart',
        'lib/services/log_filter_service.dart',
        'lib/services/log_file_cache_service.dart',
        'lib/services/storage_service.dart',
      });
    });

    test('app tag 域 = {main, app_state, version_service}', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('app'))
          .map((f) => f.path)
          .toSet();
      expect(files, {
        'lib/main.dart',
        'lib/providers/app_state.dart',
        'lib/services/version_service.dart',
      });
    });

    test('ui tag 域 = {main_screen_v3, settings_screen}（screens/ 子树）', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('ui'))
          .map((f) => f.path)
          .toSet();
      expect(files, {
        'lib/screens/main_screen_v3.dart',
        'lib/screens/settings_screen.dart',
      });
    });

    test('preload tag 域 = {preload_service}（专属 service）', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('preload'))
          .map((f) => f.path)
          .toSet();
      expect(files, {'lib/services/preload_service.dart'});
    });

    test('config tag 域 = {config_service}（专属 service）', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('config'))
          .map((f) => f.path)
          .toSet();
      expect(files, {'lib/services/config_service.dart'});
    });

    test('merge tag 域 = {merge_execution_state}（fanout-by-helper 模式）', () {
      final files = _allLibDartFiles()
          .where((f) =>
              !f.path.endsWith('services/logger_service.dart') &&
              _tagsInCodeOf(f).contains('merge'))
          .map((f) => f.path)
          .toSet();
      expect(files, {'lib/providers/merge_execution_state.dart'});
    });
  });

  group('R138 group 4：N4 negative space invariant — credential tag 0 callsite', () {
    test('全 lib/ 内 0 处 AppLogger.credential（namespace bookmark 故意预留）', () {
      var hits = 0;
      for (final f in _allLibDartFiles()) {
        if (f.path.endsWith('services/logger_service.dart')) continue;
        hits += _countTagInCode(f, 'credential');
      }
      expect(hits, 0,
          reason: 'N4 namespace 故意空——credential tag 是 future-proofing bookmark');
    });

    test('AppLogger.credential 字段仍存在（bookmark 不删除）', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(
          code.contains("static final credential = logger.tagged('CRED')"),
          isTrue);
    });
  });

  group('R138 group 5：fanout-by-helper 模式（merge tag 单 callsite）', () {
    test('merge_execution_state 内 AppLogger.merge 仅 1 个直接 callsite', () {
      final f = File('lib/providers/merge_execution_state.dart');
      expect(_countTagInCode(f, 'merge'), 1,
          reason: '所有业务日志通过 _appendLog helper funnel 到单点');
    });

    test('merge_execution_state 内 _appendLog helper 被 ≥30 次调用（fanout 标志）', () {
      final f = File('lib/providers/merge_execution_state.dart');
      final code = _stripComments(f.readAsStringSync());
      final calls = RegExp(r'\b_appendLog\(').allMatches(code).length;
      expect(calls, greaterThanOrEqualTo(30),
          reason: 'fanout-by-helper 模式：业务侧多调用、tag 侧单出口');
    });
  });

  group('R138 group 6：R138 doc-block 锚点锁', () {
    test('logger_service.dart 内 R138 doc-block keywords 全部出现', () {
      final src = logger.readAsStringSync();
      const keywords = [
        'R138',
        'AppLogger tag namespace',
        'N1 文件 tag 单一性',
        'N2 跨文件 tag 共享',
        'N3 tag 集合穷尽闭合',
        'N4 namespace 故意空',
        'fanout-by-helper',
        'credential',
        'negative space invariant',
      ];
      for (final k in keywords) {
        expect(src.contains(k), isTrue,
            reason: 'R138 doc-block 必须含关键字 "$k"');
      }
    });

    test('R138 doc-block 提及与 R136/R137 接合面', () {
      final src = logger.readAsStringSync();
      expect(src.contains('R136'), isTrue);
      expect(src.contains('R137'), isTrue);
      expect(src.contains('信号家族三维') || src.contains('三维'), isTrue,
          reason: 'R136 cancel × R137 error × R138 namespace 三维闭合');
    });
  });
}
