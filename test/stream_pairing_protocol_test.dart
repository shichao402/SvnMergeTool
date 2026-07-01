import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R142 复用，R143 第 13 次复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R143 Stream / StreamController / StreamSubscription 配对协议审计**
///
/// 协议要点（详见 lib/services/working_copy_manager.dart 文件头 R143 doc-block）：
/// - lib 全集：1 个 StreamController（broadcast，working_copy_manager.dart:291）
/// - .listen / StreamSubscription / StreamBuilder：lib 内 0 个
/// - 三档框架（producer lifecycle）：sync / broadcast / cold —— lib 仅档 2
/// - B1 Owner 单点律 / B2 Sink 内聚律 / B3 Close-once 律 / B4 Schema 单值律
/// - R121 ↔ R143 正交叠加（站点 A dispose 同时承担两协议不同档位号）
void main() {
  final wcSrc =
      File('lib/services/working_copy_manager.dart').readAsStringSync();
  final wcCode = _stripComments(wcSrc);

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

  group('R143 G1: API 全集穷尽闭合 (B1 Owner 单点律)', () {
    test('lib/ 下 StreamController 总站点数 = 1（仅 working_copy_manager 持有）', () {
      // 形态：`StreamController<...>(...)` / `StreamController(...)` / `.broadcast(`
      // 我们计 `StreamController` 在 stripped code 中作为构造调用的命中
      final ctorRe = RegExp(r'\bStreamController\b');
      final owners = <String>[];
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (ctorRe.hasMatch(stripped)) {
          owners.add(f.path);
        }
      }
      expect(owners.length, 1,
          reason: 'R143 B1 Owner 单点律：lib/ 仅允许 1 处 StreamController owner。命中文件：$owners');
      expect(owners.single.endsWith('working_copy_manager.dart'), true,
          reason: 'R143 B1：唯一 owner 必须是 working_copy_manager.dart');
    });

    test('lib/ 下任何 .dart 文件都不得使用 .listen(', () {
      // R143 lib 全集断言：无 .listen 即无 StreamSubscription 字段，
      // 无 cancel 配对验证负担
      final re = RegExp(r'\.listen\s*\(');
      final hits = <String>[];
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (re.hasMatch(stripped)) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason: 'R143：lib/ 禁止 .listen( —— 引入消费端会触发 StreamSubscription cancel 配对协议。命中：$hits');
    });

    test('lib/ 下任何 .dart 文件都不得使用 StreamSubscription 字段类型', () {
      final re = RegExp(r'\bStreamSubscription\b');
      final hits = <String>[];
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (re.hasMatch(stripped)) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason: 'R143：lib/ 禁止 StreamSubscription 字段——引入即需 cancel 配对档位。命中：$hits');
    });

    test('lib/ 下任何 .dart 文件都不得使用 StreamBuilder', () {
      final re = RegExp(r'\bStreamBuilder\b');
      final hits = <String>[];
      for (final f in allLibFiles) {
        final stripped = _stripComments(f.readAsStringSync());
        if (re.hasMatch(stripped)) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason:
              'R143：lib/ 禁止 StreamBuilder—— 当前消费端约定在 widget 树外（外部 ChangeNotifier 桥接），引入需新协议档位。命中：$hits');
    });
  });

  group('R143 G2: 站点 A producer lifecycle 档 2 (broadcast)', () {
    test('站点 A 是 broadcast controller', () {
      // working_copy_manager.dart:291: StreamController<WcLockInfo?>.broadcast()
      final re = RegExp(
          r'StreamController\s*<\s*WcLockInfo\?\s*>\s*\.\s*broadcast\s*\(\s*\)');
      expect(re.hasMatch(wcCode), true,
          reason: 'R143 档 2：站点 A 必须是 .broadcast()，禁止改成 single-listener');
    });

    test('站点 A 暴露只读 Stream view（statusStream getter）', () {
      // 形态：Stream<WcLockInfo?> get statusStream => _statusController.stream;
      final re = RegExp(
          r'Stream\s*<\s*WcLockInfo\?\s*>\s+get\s+statusStream\s*=>\s*_statusController\.stream\s*;');
      expect(re.hasMatch(wcCode), true,
          reason: 'R143 B2 Sink 内聚律：外部只能见只读 Stream view，禁止暴露 controller 本身');
    });

    test('B2 Sink 内聚律：_statusController.add 全部在 owner 类内（仅 acquire/release 两站点）', () {
      // wcCode 已 strip 注释；统计 .add( 命中数（其它文件应该 0 命中）
      final addRe = RegExp(r'_statusController\.add\s*\(');
      final wcAdds = addRe.allMatches(wcCode).length;
      expect(wcAdds, 2,
          reason:
              'R143 B2：仅允许 _acquireLock + _releaseLock 两处 add（broadcast event 入口）');

      // 全 lib 内不能在 working_copy_manager 之外见到 _statusController
      final extOwners = <String>[];
      for (final f in allLibFiles) {
        if (f.path.endsWith('working_copy_manager.dart')) continue;
        final stripped = _stripComments(f.readAsStringSync());
        if (RegExp(r'_statusController\b').hasMatch(stripped)) {
          extOwners.add(f.path);
        }
      }
      expect(extOwners, isEmpty,
          reason: 'R143 B2：private controller 不得跨文件访问。外漏文件：$extOwners');
    });

    test('B4 Schema 单值律：addError 全 lib 0 站点（错误不灌进 stream）', () {
      // 防止未来 controller.addError(...) 把异常路径走 stream
      // 当前 Schema：WcLockInfo? —— null = released / 非 null = active；不带 error 通道
      final re = RegExp(r'_statusController\.addError\s*\(|_statusController\.sink\b');
      expect(re.hasMatch(wcCode), false,
          reason: 'R143 B4 Schema 单值律：禁止 addError / .sink 直接写入；error 走 throw + 日志');
    });
  });

  group('R143 G3: B3 Close-once 律 (dispose 单点 close)', () {
    test('dispose 内仅 1 处 _statusController.close()', () {
      final closeRe = RegExp(r'_statusController\.close\s*\(\s*\)');
      final closeCount = closeRe.allMatches(wcCode).length;
      expect(closeCount, 1,
          reason: 'R143 B3 Close-once 律：close() 必须单点调用（在 dispose 内）');
    });

    test('dispose 签名是 void（fire-and-forget，对齐 R121 档 3）', () {
      // 形态：void dispose() { _statusController.close(); }
      // 用宽容匹配：函数体内含 close() 且签名为 void
      final re =
          RegExp(r'void\s+dispose\s*\(\s*\)\s*\{[^}]*_statusController\.close\s*\(\s*\)\s*;[^}]*\}');
      expect(re.hasMatch(wcCode), true,
          reason: 'R143 B3 + R121 档 3：dispose 必须 void 签名 + fire-and-forget close');
    });

    test('B1 Owner 单点律：_statusController 是 final private 字段', () {
      // 形态：final _statusController = StreamController<WcLockInfo?>.broadcast();
      final re = RegExp(
          r'final\s+_statusController\s*=\s*StreamController\s*<\s*WcLockInfo\?\s*>\s*\.\s*broadcast\s*\(\s*\)\s*;');
      expect(re.hasMatch(wcCode), true,
          reason: 'R143 B1：必须是 final 单点持有，禁止 late / 多处赋值');
    });
  });

  group('R143 G4: U4 档位标注双向律 + R121 ↔ R143 正交叠加', () {
    test('R143 文件头 doc-block 含三档定义锚点', () {
      expect(wcSrc.contains('R143 Stream'), true);
      expect(wcSrc.contains('档 1：sync producer'), true);
      expect(wcSrc.contains('档 2：broadcast producer'), true);
      expect(wcSrc.contains('档 3：cold stream producer'), true);
    });

    test('R143 doc-block 含 B 系四律锚点', () {
      expect(wcSrc.contains('B1 Owner 单点律'), true);
      expect(wcSrc.contains('B2 Sink 内聚律'), true);
      expect(wcSrc.contains('B3 Close-once 律'), true);
      expect(wcSrc.contains('B4 Schema 单值律'), true);
    });

    test('R143 doc-block 含 R121 ↔ R143 正交叠加锚点', () {
      expect(wcSrc.contains('R121 ↔ R143 正交叠加'), true);
      // 站点 A 是双协议同站点不同档位号实例
      expect(wcSrc.contains('R121 档 3'), true);
      expect(wcSrc.contains('R143 档 2'), true);
    });

    test('R143 doc-block 含 lib 全集表（仅 1 个 StreamController）', () {
      // 矩阵中应列出 working_copy_manager.dart:291
      expect(wcSrc.contains('working_copy_manager.dart:291'), true);
      expect(wcSrc.contains('broadcast'), true);
    });

    test('R143 doc-block 含"故意不做"边界声明（4 项）', () {
      expect(wcSrc.contains('故意不做'), true);
      expect(wcSrc.contains('WcLockStatusBroadcaster'), true);
      expect(wcSrc.contains('IOSink'), true);
      expect(wcSrc.contains('buffer/replay'), true);
      expect(wcSrc.contains('single-subscription'), true);
    });

    test('R143 doc-block 含 N-tuple 第 23 次 / 第 7 次维度切换元说明', () {
      expect(wcSrc.contains('N-tuple invariance 模板第 23 次复用 / 第 7 次维度切换'), true);
      expect(wcSrc.contains('Stream producer'), true);
    });

    test('R143 doc-block 含 R85+ N+20 / _stripComments 第 13 次复用元说明', () {
      expect(wcSrc.contains('R85+ N+20'), true);
      expect(wcSrc.contains('_stripComments') &&
              wcSrc.contains('第 13 次复用'),
          true);
    });
  });
}
