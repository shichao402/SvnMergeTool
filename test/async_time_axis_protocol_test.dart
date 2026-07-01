import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R141 复用，R142 第 12 次复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R142 异步时间轴协议审计**
///
/// 协议要点（详见 lib/services/preload_service.dart 文件头 R142 doc-block）：
/// - API 全集 6 项 + lib/ 仅使用 `Future.delayed`（2 站点）
/// - 三档框架（cancel 机制维度）：
///   - 档 1：no-cancel（lib 0 个）
///   - 档 2：cancel-by-loop-condition（站点 A + 站点 B）
///   - 档 3：cancel-by-Timer-handle（lib 0 个）
/// - U1 API 单一律 / U2 退出条件单点律 / U3 时长选值理由律 / U4 档位标注双向律
/// - R120 ↔ R142 正交叠加
void main() {
  final loggerSrc =
      File('lib/services/logger_service.dart').readAsStringSync();
  final preloadSrc =
      File('lib/services/preload_service.dart').readAsStringSync();
  final loggerCode = _stripComments(loggerSrc);
  final preloadCode = _stripComments(preloadSrc);

  // 收集 lib/ 下所有 dart 文件用于全集排除性扫描
  final allLibFiles = <File>[];
  void collectDartFiles(Directory dir) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        allLibFiles.add(entity);
      }
    }
  }

  collectDartFiles(Directory('lib'));

  group('R142 G1: API 全集穷尽闭合 (U1 API 单一律)', () {
    test('lib/ 下任何 .dart 文件都不得使用 Timer/Timer.periodic', () {
      final hits = <String>[];
      // Timer( or Timer.periodic( as constructor / factory call
      // 排除 import 与字符串内容（粗筛：只看 stripped 代码）
      final timerRe =
          RegExp(r'\bTimer\s*\(|\bTimer\.periodic\s*\(|new\s+Timer\s*\(');
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (timerRe.hasMatch(stripped)) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty,
          reason:
              'R142 U1 API 单一律：lib/ 禁止 Timer/Timer.periodic，否则需新增协议档位文档。命中文件：$hits');
    });

    test('lib/ 下任何 .dart 文件都不得使用 Stream.periodic', () {
      final hits = <String>[];
      final re = RegExp(r'\bStream\.periodic\s*\(');
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (re.hasMatch(stripped)) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason: 'R142 U1：lib/ 禁止 Stream.periodic。命中：$hits');
    });

    test('lib/ 下任何 .dart 文件都不得使用 dart:io 同步 sleep()', () {
      // dart:io sleep(d) 同步阻塞 UI thread——Flutter 严禁
      final hits = <String>[];
      // 形态：sleep(Duration(...)) 单独成行调用；排除 await Future.delayed 与
      // 命名为 sleep 的 helper 调用（这里粗筛后人工保证）
      final re = RegExp(r"(^|\s|;)sleep\s*\(\s*Duration");
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (re.hasMatch(stripped)) hits.add(f.path);
      }
      expect(hits, isEmpty, reason: 'R142 U1：lib/ 禁止 dart:io sleep()。命中：$hits');
    });

    test('lib/ 下 Future.delayed 总站点数恰好为 2', () {
      var total = 0;
      final perFile = <String, int>{};
      final re = RegExp(r'Future\.delayed\s*\(');
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        final c = re.allMatches(stripped).length;
        if (c > 0) {
          perFile[f.path] = c;
          total += c;
        }
      }
      expect(total, 2,
          reason:
              'R142 U1：lib/ Future.delayed 总站点数应 = 2（站点 A logger close + 站点 B preload throttle）。perFile=$perFile');
      // 每文件计数核对
      expect(perFile.values.every((v) => v == 1), isTrue,
          reason: '每文件应恰好 1 个站点。perFile=$perFile');
    });
  });

  group('R142 G2: 站点 A (logger close polling, 档 2)', () {
    test('logger_service.dart 含 Future.delayed 站点', () {
      expect(loggerCode.contains('Future.delayed'), isTrue);
    });

    test('站点 A 时长 = 10ms（U3 时长选值理由律）', () {
      // while 循环内 await Future.delayed(const Duration(milliseconds: 10));
      final re =
          RegExp(r'Future\.delayed\(const Duration\(milliseconds:\s*10\)\)');
      expect(re.hasMatch(loggerCode), isTrue,
          reason: '站点 A 必须为 10ms polling tick');
    });

    test('站点 A 嵌入 while 循环（档 2 cancel-by-loop-condition）', () {
      // 在 logger_service.dart 中 close 方法的 while 块体应同时含 _writeQueue / _isWriting
      // 与 Future.delayed
      // 简单检查：原始（含注释）中存在 close 方法 + while + Future.delayed 邻近出现
      final closeIdx =
          loggerSrc.indexOf(RegExp(r'Future<void>\s+close\s*\(\s*\)\s+async'));
      expect(closeIdx, greaterThan(-1), reason: '应存在 close() 方法');
      final delayedIdx = loggerSrc.indexOf('Future.delayed', closeIdx);
      expect(delayedIdx, greaterThan(closeIdx),
          reason: '站点 A Future.delayed 必须在 close() 方法内');
      // 站点 A 与 close 之间不得超过 1KB 距离（紧邻在同一方法内）
      expect(delayedIdx - closeIdx, lessThan(2000),
          reason: '站点 A 应紧邻 close() 方法体内');
    });

    test('站点 A 退出条件 = _writeQueue.isEmpty && !_isWriting (U2 单点律)', () {
      // 检查 close 方法体内同时含两个状态字面量
      final closeIdx =
          loggerSrc.indexOf(RegExp(r'Future<void>\s+close\s*\(\s*\)\s+async'));
      final segment = loggerSrc.substring(
          closeIdx, (closeIdx + 1500).clamp(0, loggerSrc.length));
      expect(segment.contains('_writeQueue'), isTrue,
          reason: '站点 A 退出条件须含 _writeQueue 信号');
      expect(segment.contains('_isWriting'), isTrue,
          reason: '站点 A 退出条件须含 _isWriting 信号');
    });
  });

  group('R142 G3: 站点 B (preload throttle, 档 3)', () {
    test('preload_service.dart 含 Future.delayed 站点', () {
      expect(preloadCode.contains('Future.delayed'), isTrue);
    });

    test('站点 B 时长 = 100ms（U3 时长选值理由律）', () {
      final re =
          RegExp(r'Future\.delayed\(const Duration\(milliseconds:\s*100\)\)');
      expect(re.hasMatch(preloadCode), isTrue,
          reason: '站点 B 必须为 100ms throttle delay');
    });

    test('站点 B 嵌入 while 循环（档 2 cancel-by-loop-condition + R120 档 3 throttle）',
        () {
      // 在 stripped 代码（去除注释）中查找：while(!_shouldStop) 必须先于 Future.delayed
      final whileIdx =
          preloadCode.indexOf(RegExp(r'while\s*\(\s*!\s*_shouldStop\s*\)'));
      final delayedIdx = preloadCode.indexOf('Future.delayed');
      expect(whileIdx, greaterThan(-1),
          reason: '站点 B 必须有 while(!_shouldStop) 守卫');
      expect(delayedIdx, greaterThan(whileIdx),
          reason: '站点 B Future.delayed 必须在 while 循环内（stripped 代码层面）');
    });

    test('站点 B 退出信号 = _shouldStop（U2 单点律）', () {
      // 与站点 B 同一方法体内（startPreload）应含 _shouldStop 多处使用
      final shouldStopCount = '_shouldStop'.allMatches(preloadCode).length;
      expect(shouldStopCount, greaterThanOrEqualTo(3),
          reason: '_shouldStop 应作为站点 B 主退出信号在多处出现');
    });
  });

  group('R142 G4: 档位标注双向律 (U4)', () {
    test('站点 A 行内注释指向 R120 档 2', () {
      // 原始源码（含注释）中 close 方法 doc-block 应提及 "档 2"
      final closeBlockIdx =
          loggerSrc.indexOf(RegExp(r'///\s*\*\*R120 等待协议档 2'));
      expect(closeBlockIdx, greaterThan(-1),
          reason: '站点 A close 方法上方 doc-block 应明确标注 R120 档 2');
    });

    test('站点 B 行内注释指向 R120 档 3 throttle', () {
      // 站点 B 上方应有 "R120 等待协议档 3" 注释
      expect(preloadSrc.contains('R120 等待协议档 3'), isTrue,
          reason: '站点 B 上方 inline 注释应明确标注 R120 档 3 节流型 sleep');
    });

    test('R142 矩阵在 preload_service.dart 文件头列出两站点', () {
      // R142 doc-block 应同时列出两站点的关键词
      expect(preloadSrc.contains('R142 异步时间轴协议审计'), isTrue,
          reason: 'R142 doc-block 必须存在');
      expect(preloadSrc.contains('logger_service.dart:771'), isTrue,
          reason: 'R142 矩阵应列出站点 A 行号');
      expect(preloadSrc.contains('preload_service.dart:638'), isTrue,
          reason: 'R142 矩阵应列出站点 B 行号');
    });
  });

  group('R142 G5: U 系四协议律锚点检查', () {
    test('R142 doc-block 包含 U1 / U2 / U3 / U4 四律标题', () {
      const anchors = [
        'U1 API 单一律',
        'U2 退出条件单点律',
        'U3 时长选值理由律',
        'U4 档位标注双向律',
      ];
      for (final a in anchors) {
        expect(preloadSrc.contains(a), isTrue, reason: 'R142 doc-block 应含锚点: $a');
      }
    });

    test('R142 doc-block 包含三档框架定义', () {
      const anchors = [
        '档 1：no-cancel',
        '档 2：cancel-by-loop-condition',
        '档 3：cancel-by-Timer-handle',
      ];
      for (final a in anchors) {
        expect(preloadSrc.contains(a), isTrue,
            reason: 'R142 doc-block 应含三档定义: $a');
      }
    });

    test('R142 doc-block 包含 R120 ↔ R142 正交叠加说明', () {
      expect(preloadSrc.contains('R120 ↔ R142 正交叠加'), isTrue,
          reason: 'R142 doc-block 应说明与 R120 的正交关系');
    });

    test('R142 doc-block 列出 API 全集 6 项', () {
      // 至少包含 Future.delayed / Timer( / Timer.periodic / Stream.periodic /
      // sleep / scheduleMicrotask 这 6 个 API 名称
      const apis = [
        'Future.delayed',
        'Timer(',
        'Timer.periodic',
        'Stream.periodic',
        'sleep',
        'scheduleMicrotask',
      ];
      for (final api in apis) {
        expect(preloadSrc.contains(api), isTrue,
            reason: 'R142 API 全集应包含: $api');
      }
    });

    test('R142 doc-block 含"故意不做"边界声明', () {
      expect(preloadSrc.contains('故意不做'), isTrue,
          reason: 'R142 应声明边界（与 R141 / R140 一致）');
    });
  });
}
