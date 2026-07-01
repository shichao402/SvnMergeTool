import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R138 复用，R139 沿用）。
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

/// 统计某文件内某档 `AppLogger.<tag>.<level>(` 出现次数（剥离注释后）。
int _countLevelCallsiteIn(File f, String level) {
  if (f.path.endsWith('services/logger_service.dart')) return 0;
  final code = _stripComments(f.readAsStringSync());
  final re = RegExp(r'AppLogger\.\w+\.' + level + r'\(');
  return re.allMatches(code).length;
}

int _totalLevelCallsites(String level) {
  var total = 0;
  for (final f in _allLibDartFiles()) {
    total += _countLevelCallsiteIn(f, level);
  }
  return total;
}

/// **R139 AppLogger log level 维度协议审计**
///
/// 协议要点（详见 lib/services/logger_service.dart 内 `enum LogLevel` 上方
/// R139 doc-block）：
/// - 4 档穷尽全集：debug / info / warn / error
/// - L1 签名档位律：低档拒绝附属，高档允许 (error, stackTrace)
/// - L2 kDebugMode 分流律：debug 仅 dev build 出现
/// - L3 error 携带 cause 完整律（catch+error 必带 stackTrace；2 类合法豁免）
/// - L4 量轴档位穷尽闭合律
void main() {
  final logger = File('lib/services/logger_service.dart');

  group('R139 group 1：LogLevel 枚举声明锁（4 档穷尽 L4）', () {
    test('LogLevel enum 含且仅含 debug/info/warn/error 4 档', () {
      final code = _stripComments(logger.readAsStringSync());
      final enumStart = code.indexOf('enum LogLevel {');
      expect(enumStart, greaterThanOrEqualTo(0));
      final enumEnd = code.indexOf('}', enumStart);
      final body = code.substring(enumStart, enumEnd);
      const expected = ['debug', 'info', 'warn', 'error'];
      for (final lvl in expected) {
        expect(body.contains(lvl), isTrue,
            reason: 'LogLevel.$lvl 必须存在');
      }
      // 穷尽：枚举体内只允许这 4 个标识符（剥离注释后）
      final identRe = RegExp(r'\b([a-z]+)\b');
      final idents = identRe
          .allMatches(body.replaceFirst('enum LogLevel', ''))
          .map((m) => m.group(1)!)
          .where((s) => expected.contains(s))
          .toSet();
      expect(idents.length, 4,
          reason: 'L4 量轴档位穷尽闭合——禁止 trace/verbose/fatal/notice 等扩展');
    });
  });

  group('R139 group 2：TaggedLogger 入口签名档位律 L1', () {
    test('debug 签名 = (String, [StackTrace?])——只接堆栈不接 error', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(
          code.contains('void debug(String message, [StackTrace? stackTrace])'),
          isTrue,
          reason: 'L1：debug 不允许接 error 对象（debug 语义不应包含异常）');
    });

    test('info 签名 = (String)——纯消息无附属', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(code.contains('void info(String message) =>'), isTrue,
          reason: 'L1：info 拒绝附属，附属意味偏离正常应升档');
    });

    test('warn 签名 = (String)——纯消息无附属', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(code.contains('void warn(String message) =>'), isTrue,
          reason: 'L1：warn 表达"可继续"，附属意味不可恢复应升 error');
    });

    test('error 签名 = (String, [Object? error, StackTrace? stackTrace])', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(
          code.contains(
              'void error(String message, [Object? error, StackTrace? stackTrace])'),
          isTrue,
          reason: 'L1：error 是唯一携带异常对象的入口');
    });
  });

  group('R139 group 3：kDebugMode 分流律 L2', () {
    test('LoggerService.minLevel 默认 = kDebugMode ? debug : info', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(
          code.contains(
              'LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info'),
          isTrue,
          reason: 'L2：production build 中 debug 档静默剥离，info 起步');
    });

    test('shouldLogAtLevel 包含 enabled && level.index >= minLevel.index 短路', () {
      final code = _stripComments(logger.readAsStringSync());
      expect(
          code.contains(
              'return enabled && level.index >= minLevel.index'),
          isTrue);
    });
  });

  group('R139 group 4：4 档 lib/ 分布快照（量轴定量锁）', () {
    test('debug 档 lib/ 总 callsites ≥ 5（极稀，开发期跟踪）', () {
      final n = _totalLevelCallsites('debug');
      expect(n, greaterThanOrEqualTo(5),
          reason: 'debug 极稀基线——若大幅减少需检查是否被误删');
      expect(n, lessThanOrEqualTo(20),
          reason: 'debug 不应膨胀——若超 20 检查是否该升档为 info');
    });

    test('info 档 lib/ 总 callsites ≥ 100（业务流水主导）', () {
      final n = _totalLevelCallsites('info');
      expect(n, greaterThanOrEqualTo(100),
          reason: 'info 是日常业务正常分支主导档，应占绝对多数');
    });

    test('warn 档 lib/ 总 callsites 在 [10, 60] 区间', () {
      final n = _totalLevelCallsites('warn');
      expect(n, greaterThanOrEqualTo(10));
      expect(n, lessThanOrEqualTo(60),
          reason: 'warn 区间——下限防丢失、上限防"信号失真"（警告太多 = 噪音）');
    });

    test('error 档 lib/ 总 callsites 在 [40, 150] 区间', () {
      final n = _totalLevelCallsites('error');
      expect(n, greaterThanOrEqualTo(40));
      expect(n, lessThanOrEqualTo(150),
          reason: 'error 区间——上限防"灾难性错误"被掩盖在大量错误中');
    });

    test('档位单调性：debug < warn < error < info（当前业务画像锁定）', () {
      final d = _totalLevelCallsites('debug');
      final i = _totalLevelCallsites('info');
      final w = _totalLevelCallsites('warn');
      final e = _totalLevelCallsites('error');
      expect(d < w, isTrue, reason: '画像：debug 比 warn 稀');
      expect(w < e, isTrue, reason: '画像：warn 比 error 稀（catch 出口主导）');
      expect(e < i, isTrue, reason: '画像：error 比 info 稀（业务流水占大头）');
    });
  });

  group('R139 group 5：L3 error 携带 cause 完整律（catch+error 必带 stackTrace）', () {
    test('lib/ 内 ≥ 60 处 .error( 调用第三参为 stackTrace（catch 块出口主流形态）', () {
      var hits = 0;
      final re = RegExp(
          r'AppLogger\.\w+\.error\s*\([^)]*?stackTrace[^)]*?\)',
          dotAll: true);
      for (final f in _allLibDartFiles()) {
        if (f.path.endsWith('services/logger_service.dart')) continue;
        final code = _stripComments(f.readAsStringSync());
        hits += re.allMatches(code).length;
      }
      expect(hits, greaterThanOrEqualTo(60),
          reason: 'L3：catch (e, stackTrace) 必透传——主流形态计数下限');
    });

    test('带 stackTrace 的 .error( 占比 ≥ 70%（豁免 ≤ 30%）', () {
      var total = 0;
      var withSt = 0;
      final reAll = RegExp(r'AppLogger\.\w+\.error\s*\(', dotAll: true);
      final reSt = RegExp(
          r'AppLogger\.\w+\.error\s*\([^;]*?stackTrace[^;]*?\)',
          dotAll: true);
      for (final f in _allLibDartFiles()) {
        if (f.path.endsWith('services/logger_service.dart')) continue;
        final code = _stripComments(f.readAsStringSync());
        total += reAll.allMatches(code).length;
        withSt += reSt.allMatches(code).length;
      }
      expect(total, greaterThan(0));
      final ratio = withSt / total;
      expect(ratio, greaterThanOrEqualTo(0.7),
          reason:
              'L3 豁免上限——剩余 ≤ 30% 必属 CLI stderr / 状态断言 2 类合法豁免');
    });
  });

  group('R139 group 6：R139 doc-block 锚点锁', () {
    test('logger_service.dart 内 R139 doc-block keywords 全部出现', () {
      final src = logger.readAsStringSync();
      const keywords = [
        'R139',
        'AppLogger log level',
        'L1 签名档位律',
        'L2 kDebugMode 分流律',
        'L3 error 携带 cause 完整律',
        'L4 量轴档位穷尽闭合律',
        '二维闭合矩阵',
        'fanout-by-helper',
      ];
      for (final k in keywords) {
        expect(src.contains(k), isTrue,
            reason: 'R139 doc-block 必须含关键词: $k');
      }
    });

    test('R138 doc-block 仍存在（R139 不替换 R138，二轮叠加）', () {
      final src = logger.readAsStringSync();
      expect(src.contains('R138 AppLogger tag namespace'), isTrue);
      expect(src.contains('N1 文件 tag 单一性'), isTrue);
    });
  });
}
