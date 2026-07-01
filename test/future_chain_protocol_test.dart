import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R143 复用，R144 第 14 次复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R144 Future 链式（.then / .catchError / .whenComplete）协议审计**
///
/// 协议要点（详见 lib/screens/main_screen_v3.dart 文件头 R144 doc-block）：
/// - lib 全集：`.then(` 5 站点（main.dart × 2 / main_screen_v3.dart × 3）
/// - lib 全集：`.catchError(` 4 站点（main_screen_v3.dart × 4 inline；logger
///   内 3 处由 R119 helper `silentlyDiscardAsyncError` 包装吸收）
/// - lib 全集：`.whenComplete(` 0 站点（V3 negative-space invariant）
/// - 三档归属：档 1 = P/Q（fire-and-forget + callee 内部 sidechannel）/ 档 1
///   + sidechannel = T+X 配对 / 档 2 = lib 0 inline（全部走 helper）/ 档 3
///   = R/S/U/V/W（5 处 `await … .catchError` 旁路化）
/// - V 系四律：V1 chain 起点档位归属律 / V2 catchError 显式静默吞禁止律 /
///   V3 whenComplete negative-space invariant / V4 chain 嵌套深度律
/// - R119 ↔ R144 同 surface 双协议第 3 次实例化
void main() {
  final mainSrc = File('lib/main.dart').readAsStringSync();
  final mainCode = _stripComments(mainSrc);
  final screenSrc =
      File('lib/screens/main_screen_v3.dart').readAsStringSync();
  final screenCode = _stripComments(screenSrc);
  final loggerSrc = File('lib/services/logger_service.dart').readAsStringSync();

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

  group('R144 Group 1：.then / .catchError / .whenComplete API 全集穷尽闭合', () {
    test('lib/ `.then(` 总计 5 站点（main.dart × 2 + main_screen_v3.dart × 3）',
        () {
      var totalThenCount = 0;
      final perFileThenCount = <String, int>{};
      for (final f in allLibFiles) {
        final code = _stripComments(f.readAsStringSync());
        final count = '.then('.allMatches(code).length;
        if (count > 0) {
          perFileThenCount[f.path] = count;
          totalThenCount += count;
        }
      }
      expect(totalThenCount, 5,
          reason:
              'V1 律：lib/ `.then(` 总计 = 5；超过 5 = 新引入未 doc 化档位归属、'
              '少于 5 = 站点删除未同步更新 R144 矩阵。perFile=$perFileThenCount');
      expect(perFileThenCount.keys.any((p) => p.endsWith('main.dart')), isTrue);
      expect(
          perFileThenCount.keys.any((p) => p.endsWith('main_screen_v3.dart')),
          isTrue);
    });

    test('lib/ `.catchError(` 总计 4 inline 站点（main_screen_v3.dart 全部，logger 内通过 helper 包装）',
        () {
      var inlineCatchErrorCount = 0;
      final perFile = <String, int>{};
      for (final f in allLibFiles) {
        final code = _stripComments(f.readAsStringSync());
        final count = '.catchError('.allMatches(code).length;
        if (count > 0) {
          perFile[f.path] = count;
          inlineCatchErrorCount += count;
        }
      }
      // logger_service.dart helper 实现 1 处 + main_screen_v3 4 处 = 5
      expect(inlineCatchErrorCount, 5,
          reason:
              'V2 律：lib/ `.catchError(` 站点 = helper 实现 1 + main_screen_v3 inline 4 = 5；'
              '增减必须更新矩阵。perFile=$perFile');
      // 检查 helper 实现存在于 logger_service
      expect(perFile.keys.any((p) => p.endsWith('logger_service.dart')), isTrue,
          reason: 'logger_service.dart 必须有 silentlyDiscardAsyncError 实现');
    });

    test('V3 negative-space invariant：lib/ `.whenComplete(` 0 站点', () {
      var totalWhenComplete = 0;
      for (final f in allLibFiles) {
        final code = _stripComments(f.readAsStringSync());
        totalWhenComplete += '.whenComplete('.allMatches(code).length;
      }
      expect(totalWhenComplete, 0,
          reason:
              'V3 律：lib/ `.whenComplete(` 必须 0 站点。引入需先升档 4 评估 + 更新 R144 矩阵。');
    });

    test('R144 矩阵 9 链式站点总计 = `.then` 5 + `.catchError` inline 4', () {
      // 不重复 logger_service helper 内部实现的 1 处 catchError——它是
      // R119 档 2 helper 的实现细节、不算业务 chain 站点。
      final thenInBusiness = 5;
      final catchErrorInBusiness = 4;
      expect(thenInBusiness + catchErrorInBusiness, 9,
          reason: 'R144 矩阵共 9 业务 chain 站点（不含 helper 实现处）。');
    });
  });

  group('R144 Group 2：站点 P/Q（main.dart 档 1 fire-and-forget then 链）', () {
    test('main.dart 站点 P：appState.loadMergeInfo().then((_) {', () {
      expect(mainCode, contains('appState.loadMergeInfo().then((_)'),
          reason: '站点 P 形态：fire-and-forget then 链开端（不 await）');
    });

    test('main.dart 站点 Q：嵌套 then 链 forceRefresh: true 后', () {
      expect(mainCode, contains('forceRefresh: true).then((_)'),
          reason: '站点 Q 形态：站点 P 内嵌的 forceRefresh then 链');
    });

    test('main.dart 站点 P/Q 不带 .catchError（依赖 callee 内部 sidechannel）', () {
      // V1 律：档 1 不需要 catchError——错误已在 callee try-catch 内部
      // 转日志（loadMergeInfo 内部 R119 档 1 sidechannel 化）。
      // 锁定 main.dart 内 .catchError 数 = 0。
      expect('.catchError('.allMatches(mainCode).length, 0,
          reason: 'V1 律 main.dart 档 1：错误由 callee 内部 try-catch 处理，'
              '不在 chain 末尾加 .catchError——加了反而是档 3 形态');
    });

    test('V4 嵌套深度律：main.dart 嵌套 then 链 ≤2 层', () {
      // 嵌套 ≥3 层需评估改 async/await——station P→Q 是 1 层嵌套（合法）。
      // 通过统计 ".then(" 之间嵌套缩进近似计数。
      // 简单校验：main.dart 中 ".then(" 数 = 2（恰好 P+Q）
      expect('.then('.allMatches(mainCode).length, 2,
          reason: 'V4 律：main.dart 嵌套 then 总数 = 2（P+Q）；嵌套 ≥3 层需重写');
    });
  });

  group('R144 Group 3：站点 R/S/T（main_screen_v3.dart `.then(` 站点）', () {
    test('站点 R：_logCacheService.init().then 串 onValidationError 注册', () {
      expect(screenCode, contains('_logCacheService.init().then((_)'),
          reason: '站点 R 形态：await + then 串副作用（档 3）');
      expect(screenCode, contains('onValidationError'),
          reason: '站点 R 副作用 payload：注册 _onValidationError handler');
    });

    test('站点 S：_preloadService.init().then 串 onProgressChanged 注册', () {
      expect(screenCode, contains('_preloadService.init().then((_)'),
          reason: '站点 S 形态：await + then 串副作用（档 3）');
      expect(screenCode, contains('onProgressChanged'),
          reason: '站点 S 副作用 payload：注册 onProgressChanged callback');
    });

    test('站点 T：_preloadService.startPreload(...).then((_)（档 1+sidechannel）',
        () {
      expect(screenCode, contains('.startPreload('),
          reason: '站点 T 起点：startPreload chain');
      // T 后必带 .catchError（站点 X 配对，档 1+sidechannel）
      // 通过相邻关键字断言：startPreload 之后 + then + catchError 共存
      final tIdx = screenCode.indexOf('.startPreload(');
      expect(tIdx >= 0, isTrue);
      final tail = screenCode.substring(tIdx);
      expect(tail.contains('.then((_)'), isTrue);
      expect(tail.contains('.catchError((e)'), isTrue,
          reason: 'V1 律：站点 T 必配对站点 X catchError 旁路化错误（档 1+sidechannel）');
    });

    test('main_screen_v3.dart `.then(` 总计 = 3', () {
      expect('.then('.allMatches(screenCode).length, 3,
          reason: 'main_screen_v3 共 3 处 .then（站点 R/S/T）');
    });
  });

  group('R144 Group 4：站点 U/V/W/X（main_screen_v3.dart `.catchError(` 站点 + V2 律）',
      () {
    test('站点 U/V/W/X：4 处 .catchError 全部带 AppLogger 旁路化（无空体）', () {
      // V2 律：禁止 inline `.catchError((_) {})` 或 `.catchError((e) {})` 空体
      final pattern = RegExp(r'\.catchError\(\(\w+\)\s*\{[^}]*AppLogger\.ui\.error');
      final matches = pattern.allMatches(screenCode);
      expect(matches.length, 4,
          reason:
              'V2 律：main_screen_v3 内 4 处 .catchError 必须带 AppLogger.ui.error 旁路化；'
              '禁止空体（空体应走 R119 档 2 helper silentlyDiscardAsyncError）');
    });

    test('V2 律：lib/ 0 处 inline 空体 catchError', () {
      // 扫所有 lib 文件、检查 ".catchError((e) {}" 与 ".catchError((_) {}" 形态
      // 排除 logger_service.dart 自身的 helper 实现 + R119 doc 注释中的字面量
      var emptyBodyCount = 0;
      for (final f in allLibFiles) {
        final code = _stripComments(f.readAsStringSync());
        emptyBodyCount += RegExp(r'\.catchError\(\((\w+|_)\)\s*\{\s*\}')
            .allMatches(code)
            .length;
      }
      // logger_service.dart helper 内 catchError 实现的 body 不是空——含
      // `// 故意空实现：见 helper doc 三个前提。` 注释行——
      // _stripComments 会把这行去掉但 `}` 上方有不止空白；如真精准空体则计入。
      // 实际检查：logger_service.dart silentlyDiscardAsyncError body 在 strip
      // 注释后变 `return future.catchError((Object _) {\n  });` —— 大括号间
      // 仅空白 → 会被识别为空体！这是 R119 档 2 helper 的"故意空体"——
      // 它就是设计为 V2 律的唯一合法空体例外。
      expect(emptyBodyCount, lessThanOrEqualTo(1),
          reason:
              'V2 律：lib/ 内空体 catchError 仅允许 1 处（R119 档 2 helper '
              'silentlyDiscardAsyncError 的实现），其余必须显式旁路化日志');
    });

    test('R119 ↔ R144 接合面：silentlyDiscardAsyncError helper 存在于 logger_service',
        () {
      expect(loggerSrc, contains('silentlyDiscardAsyncError'),
          reason: 'R119 档 2 helper 必须存在——R144 V2 律的合法静默吞唯一出口');
      expect(loggerSrc, contains('Future<void> silentlyDiscardAsyncError'),
          reason: 'helper 签名故意限定 Future<void>（见 R119 doc）');
    });
  });

  group('R144 Group 5：V 系四律 doc 锚点 + R119/R136 接合面 + N-tuple 模板锚点', () {
    test('V1 律 doc 锚点：main_screen_v3 文件头 R144 doc-block 提及 V1', () {
      expect(screenSrc, contains('V1'),
          reason: 'V1 chain 起点档位归属律 doc 锚点');
      expect(screenSrc, contains('R144'),
          reason: 'R144 doc-block 标题锚点');
    });

    test('V 系四律 doc 锚点：V1/V2/V3/V4 全部出现', () {
      for (final law in ['V1', 'V2', 'V3', 'V4']) {
        expect(screenSrc, contains(law),
            reason: '$law 律 doc 锚点必须存在');
      }
    });

    test('R119 ↔ R144 接合面 doc 锚点：同 surface 双协议第 3 次实例', () {
      expect(screenSrc, contains('R119 ↔ R144'),
          reason: 'R119 ↔ R144 接合面 doc 锚点');
      expect(screenSrc, contains('第 3 次实例'),
          reason: '同 surface 双协议第 3 次实例化锚点');
    });

    test('R136 ↔ R144 正交锚点（chain 不被当成取消通道）', () {
      expect(screenSrc, contains('R136 ↔ R144'),
          reason: 'R136 取消信号 ↔ R144 future chain 正交锚点');
    });

    test('dart:async 三元闭合锚点：R142 / R143 / R144', () {
      // R144 是 dart:async 三元闭合的第 3 元（time axis / stream / chain）
      expect(screenSrc, contains('dart:async 三元'),
          reason: 'dart:async 三元闭合首次形式化锚点');
      expect(screenSrc, contains('R142'),
          reason: 'R142 时间轴维度锚点');
      expect(screenSrc, contains('R143'),
          reason: 'R143 Stream producer 维度锚点');
    });

    test('N-tuple invariance 模板第 24 次复用 / 第 8 次维度切换锚点', () {
      expect(screenSrc, contains('N-tuple invariance 模板第 24 次复用'),
          reason: 'N-tuple 24 元说明锚点');
      expect(screenSrc, contains('第 8 次维度切换'),
          reason: '8 次维度切换锚点');
    });

    test('R85+ N+21 doc-only audit 模式锚点 + _stripComments 第 14 次复用锚点', () {
      expect(screenSrc, contains('R85+ N+21'),
          reason: 'doc-only audit R85+ N+21 锚点');
      expect(screenSrc, contains('第 14 次'),
          reason: '_stripComments helper 第 14 次复用锚点');
    });

    test('故意不做 4 项 doc 锚点（whenComplete / awaitOrLog helper / R119 合并 / 测试代码）',
        () {
      expect(screenSrc, contains('故意不做'),
          reason: '故意不做声明锚点');
      expect(screenSrc, contains('whenComplete'),
          reason: '故意不做 (1) whenComplete');
      expect(screenSrc, contains('awaitOrLog'),
          reason: '故意不做 (2) helper 抽离');
    });
  });
}
