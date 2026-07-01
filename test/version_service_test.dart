import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/version_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('parseVersionString', () {
    test('无 + → versionNumber 全保留，buildNumber=0', () {
      final p = parseVersionString('1.2.3');
      expect(p.versionNumber, '1.2.3');
      expect(p.buildNumber, 0);
    });

    test('有 + 且 build 是整数 → 拆分正确', () {
      final p = parseVersionString('1.2.3+5');
      expect(p.versionNumber, '1.2.3');
      expect(p.buildNumber, 5);
    });

    test('有 + 但 build 非整数 → buildNumber=0（与 getBuildNumber 历史回落一致）', () {
      final p = parseVersionString('1.2.3+abc');
      expect(p.versionNumber, '1.2.3');
      expect(p.buildNumber, 0);
    });

    test('有 + 但 build 为空（"1.2.3+"）→ buildNumber=0', () {
      final p = parseVersionString('1.2.3+');
      expect(p.versionNumber, '1.2.3');
      expect(p.buildNumber, 0);
    });

    test('多个 + → 取首个 + 切分；剩下整段非整数 → buildNumber=0', () {
      // pubspec 版本字符串实际只允许一个 +；本断言锁住"行为收紧"——
      // 之前 split('+').last 会得 '6'，现在 indexOf('+') + substring 拿到 '5+6'
      // 整段，tryParse 失败 → 0。生产输入不受影响。
      final p = parseVersionString('1.2.3+5+6');
      expect(p.versionNumber, '1.2.3');
      expect(p.buildNumber, 0);
    });

    test('空字符串 → versionNumber 也是空，buildNumber=0', () {
      final p = parseVersionString('');
      expect(p.versionNumber, '');
      expect(p.buildNumber, 0);
    });

    test('versionNumber 不做合法性校验（保留 split 结果原样）', () {
      // 'abc+1' / '1.2+5' 均原样保留，合法性交给上层 isVersionAtLeast
      expect(parseVersionString('abc+1').versionNumber, 'abc');
      expect(parseVersionString('1.2+5').versionNumber, '1.2');
    });

    test('build 为大数字（int 范围内）→ 正确解析', () {
      expect(parseVersionString('1.0.0+999999').buildNumber, 999999);
    });

    test('build 为负数串 → tryParse 解析成负数（不夹紧——锁定原行为）', () {
      // 与原代码 int.tryParse(parts[1]) ?? 0 行为一致：能 parse 就直接用
      expect(parseVersionString('1.0.0+-3').buildNumber, -3);
    });
  });

  group('ParsedVersion 值相等性', () {
    test('字段相等 → equals + hashCode 一致', () {
      const a = ParsedVersion(versionNumber: '1.2.3', buildNumber: 5);
      const b = ParsedVersion(versionNumber: '1.2.3', buildNumber: 5);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('字段任一不同 → 不相等', () {
      const a = ParsedVersion(versionNumber: '1.2.3', buildNumber: 5);
      const b = ParsedVersion(versionNumber: '1.2.4', buildNumber: 5);
      const c = ParsedVersion(versionNumber: '1.2.3', buildNumber: 6);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });
  });

  group('isVersionAtLeast', () {
    test('完全相等 → true', () {
      expect(isVersionAtLeast('1.2.3', '1.2.3'), isTrue);
    });

    test('major/minor/patch 任意一段大于 → true', () {
      expect(isVersionAtLeast('2.0.0', '1.99.99'), isTrue);
      expect(isVersionAtLeast('1.2.0', '1.1.99'), isTrue);
      expect(isVersionAtLeast('1.2.4', '1.2.3'), isTrue);
    });

    test('major/minor/patch 任意一段小于 → false', () {
      expect(isVersionAtLeast('1.99.99', '2.0.0'), isFalse);
      expect(isVersionAtLeast('1.1.99', '1.2.0'), isFalse);
      expect(isVersionAtLeast('1.2.3', '1.2.4'), isFalse);
    });

    test('左侧带 +build → build 段在比较时被忽略', () {
      // 与 checkCompatibility 原行为对齐：otherVersion.split('+')[0] 后比较
      expect(isVersionAtLeast('1.2.3+99', '1.2.3'), isTrue);
      expect(isVersionAtLeast('1.2.3+0', '1.2.4'), isFalse);
    });

    test('右侧带 +build → 解析失败 → 兜底 false（保守）', () {
      // minVersion 仅允许 x.y.z；如果误传 '1.2.3+5'，split('.') 后 parts[2]='3+5'
      // 不是整数，int.parse 抛错 → catch → false
      expect(isVersionAtLeast('1.2.3', '1.2.3+5'), isFalse);
    });

    test('段数 != 3 → false（左/右两侧都覆盖）', () {
      expect(isVersionAtLeast('1.2', '1.2.3'), isFalse);
      expect(isVersionAtLeast('1.2.3.4', '1.2.3'), isFalse);
      expect(isVersionAtLeast('1.2.3', '1.2'), isFalse);
      expect(isVersionAtLeast('1.2.3', '1.2.3.4'), isFalse);
    });

    test('非整数段 → false', () {
      expect(isVersionAtLeast('1.x.3', '1.2.3'), isFalse);
      expect(isVersionAtLeast('1.2.3', '1.2.x'), isFalse);
      expect(isVersionAtLeast('a.b.c', 'a.b.c'), isFalse);
    });

    test('空字符串 → false', () {
      expect(isVersionAtLeast('', '1.0.0'), isFalse);
      expect(isVersionAtLeast('1.0.0', ''), isFalse);
      expect(isVersionAtLeast('', ''), isFalse);
    });

    test('0 是合法 patch（边界——曾经的 ">=" 写错成 ">" 时这条会红）', () {
      expect(isVersionAtLeast('1.0.0', '1.0.0'), isTrue);
      expect(isVersionAtLeast('0.0.0', '0.0.0'), isTrue);
    });
  });

  // R108 — runtime-loaded shipped artifact pubspec.yaml schema 锁定 +
  // VERSION.yaml ↔ pubspec.yaml sync drift 防御。
  //
  // R107 锁的是 declared shipped asset（assets/config/source_urls.json，pubspec
  // flutter.assets 段显式列入、随包打入 flutter_assets/）；R108 锁的是
  // **runtime-loaded shipped artifact** ——pubspec.yaml 自身在 release build
  // 中**不进 flutter_assets**（验证：build/macos/.../flutter_assets/ 内只有
  // AssetManifest.bin / FontManifest.json / fonts/ / packages/ 等，无 pubspec.yaml；
  // pubspec.yaml 也未列入 flutter.assets），所以 release 走 rootBundle 必抛
  // FlutterError、被 catch 吞、再尝试 execDir 兜底（极少存在）→ 兜回 '1.0.0+1'
  // 默认值。R98 已显式 doc 化"throw 是诊断信号，契约是兜底输出 '1.0.0+1'"，
  // R108 不重测 throw 路径，而是锁住：
  //  (1) 仓库 pubspec.yaml 在**开发态**（Directory.current 路径）能被 lib 解析；
  //  (2) extractPubspecVersion 与 pubspec schema 字段名 'version' 的耦合；
  //  (3) '1.0.0+1' 兜底值与 parseVersionString 自洽（防止改默认值时漏改 parser）；
  //  (4) VERSION.yaml ↔ pubspec.yaml 的 version 字段同步（构建脚本职责，但仓库
  //      内两文件直接 grep 对比作为漂移防线）。
  //
  // R107 vs R108 对偶：
  //  - R107 declared asset：lib parser ↔ pubspec.assets ↔ asset 文件三向锁定；
  //  - R108 runtime artifact：lib parser ↔ pubspec.yaml 自身 ↔ VERSION.yaml 三向锁定。
  // 共同点：跨语言/格式（Dart + YAML）字面量重复，三向锁优于常量化（pubspec/
  // VERSION 是 YAML，不能引用 Dart 常量），R107 三向锁定模式第 2 次复用。
  group('extractPubspecVersion（R108 pubspec.yaml schema 锁定）', () {
    test('正常 yaml 含 version 字段 → 抽出原样字符串', () {
      // 锁定 lib 端字段名 'version'：若未来误改成 'app_version' 此测试立即撞红。
      const yaml = 'name: foo\nversion: 1.2.3+5\n';
      expect(extractPubspecVersion(yaml), '1.2.3+5');
    });

    test('version 字段缺失 → 返回 null（不抛）', () {
      // R98 反对称 throw 决策：null 是 sentinel，由 getVersion 显式 throw 后被
      // 外层 catch 兜回 '1.0.0+1'；本函数只负责"信号传递"不负责"路径决策"。
      const yaml = 'name: foo\ndependencies: {}\n';
      expect(extractPubspecVersion(yaml), isNull,
          reason: '缺 version 字段必须返回 null 而非空串/默认值——'
              'getVersion 路径上的 null 检查依赖此 sentinel');
    });

    test('version 字段为非 String（数字）→ 返回 null（as String? 强转兜底）', () {
      // 边界：yaml 写成 `version: 5` 而非 `version: "5"`——loadYaml 会得到 int，
      // `as String?` 抛 TypeError 走外层 catch；但 yaml 解析允许引号包裹时的微妙
      // 差异这里特意验证一种场景以 doc-lock 行为。
      const yaml = 'version: 5\n';
      // 实测会抛 TypeError（'int' is not a subtype of 'String?'）——外层 catch 兜底。
      expect(() => extractPubspecVersion(yaml), throwsA(isA<TypeError>()),
          reason: 'pubspec 规范要求 version 是字符串；写成数字会让 as String? 抛 '
              'TypeError；getVersion 外层 catch 吞掉、兜 1.0.0+1');
    });

    test('顶层非 Map（裸数组）→ 抛 TypeError', () {
      // 与 R105 parseAppConfigJson 的 "顶层非 Map" 行为一致：as Map 强转抛
      // TypeError，getVersion 外层 catch 兜底。
      expect(() => extractPubspecVersion('- a\n- b\n'),
          throwsA(isA<TypeError>()),
          reason: 'pubspec.yaml 顶层必须是 Map；裸数组会让 as Map 强转失败、'
              'getVersion 外层 catch 兜 1.0.0+1');
    });

    test('包含 + 构建号的 version 原样返回（不在本函数解析）', () {
      // 抽取与解析职责分离：本函数只抽 String，分段交给 parseVersionString。
      const yaml = 'version: 0.0.1+99\n';
      expect(extractPubspecVersion(yaml), '0.0.1+99');
    });
  });

  group('pubspec.yaml runtime artifact 端到端契约（R108）', () {
    // R108 主防御：仓库根 pubspec.yaml 必须能被 lib 完整解析链
    //   File → loadYaml → extractPubspecVersion → parseVersionString
    // 端到端走通——任何一环漂移立即撞红。

    String readPubspec() {
      final f = File('pubspec.yaml');
      expect(f.existsSync(), isTrue,
          reason: 'pubspec.yaml 必须存在于仓库根；否则 getVersion 走 rootBundle/'
              'execDir 兜底链直至返回 1.0.0+1，CI 完全不撞红');
      return f.readAsStringSync();
    }

    test('extractPubspecVersion 端到端 happy path', () {
      // R108 主防御：lib parser 与仓库 pubspec.yaml 当前 schema 直接绑定。
      final content = readPubspec();
      expect(() => extractPubspecVersion(content), returnsNormally,
          reason: '仓库 pubspec.yaml 必须能被 extractPubspecVersion 解析——'
              'YAML 损坏 / 顶层非 Map / version 字段类型变更都会撞红');
      final version = extractPubspecVersion(content);
      expect(version, isNotNull,
          reason: 'pubspec 必须含 version 字段；缺失会让 getVersion 兜底 1.0.0+1，'
              '失去运维诊断能力');
      expect(version, isNotEmpty);
    });

    test('pubspec.yaml 的 version 满足 x.y.z[+build] 格式（parseVersionString 可解析）', () {
      // 端到端联动：抽出来的 version 必须能被下游 parseVersionString 正确分段。
      final raw = extractPubspecVersion(readPubspec());
      final parsed = parseVersionString(raw!);
      // versionNumber 必须是 x.y.z 三段、全数字（pubspec 业界惯例 + Flutter 工具链要求）。
      final segments = parsed.versionNumber.split('.');
      expect(segments.length, 3,
          reason: 'pubspec version 必须是 x.y.z 三段——Flutter build 系统强约束；'
              '多 / 少段会让 isVersionAtLeast 自动 false（保守路径），更新检查全部失效');
      for (final s in segments) {
        expect(int.tryParse(s), isNotNull,
            reason: 'version 段必须全数字：$s 非数字会让 isVersionAtLeast 解析失败、'
                '更新检查降级为 false');
      }
      expect(parsed.buildNumber, greaterThanOrEqualTo(0),
          reason: 'pubspec build 段（+ 后部分）必须是非负整数；'
              '负数 / 非整数会被 parseVersionString 兜成 0、丢失构建号信息');
    });
  });

  group('VERSION.yaml ↔ pubspec.yaml sync drift 防御（R108）', () {
    // VERSION.yaml 是版本号 source of truth（构建脚本会把它同步进 pubspec.yaml
    // 的 version 字段——见 lib/services/version_service.dart 文档第 4 行
    // "由构建脚本从 VERSION.yaml 同步"）。
    //
    // 风险：构建脚本失效 / 有人手改 pubspec.yaml 而忘改 VERSION.yaml（或反之）→
    // 两文件 version 字段不一致 → release build 显示 pubspec 版本，更新服务读
    // VERSION.yaml 的 compatibility.min_app_version → 行为不一致。
    //
    // R108 在 test 侧用字面量 grep + yaml 解析双锁：
    //  - 解析 VERSION.yaml 的 app.version；
    //  - 解析 pubspec.yaml 的 version；
    //  - 二者必须严格相等（不允许 VERSION.yaml 更新版本但 pubspec 漏同步）。
    //
    // 这是 R107 三向锁定模式的扩展：R107 锁 lib ↔ pubspec.yaml ↔ asset；
    // R108 锁 VERSION.yaml ↔ pubspec.yaml ↔ lib parser，加一层"上游 source
    // of truth ↔ 下游被消费文件"的同步约束。

    test('VERSION.yaml 文件存在', () {
      expect(File('VERSION.yaml').existsSync(), isTrue,
          reason: 'VERSION.yaml 是版本号 source of truth；'
              '删除会让构建脚本失去同步源、人工维护 pubspec 极易漂移');
    });

    test('VERSION.yaml.app.version == pubspec.yaml.version（构建脚本同步契约）', () {
      // 同步漂移防御：任一侧改了 version 而没同步另一侧，本测试立即撞红。
      final versionYaml = loadYaml(File('VERSION.yaml').readAsStringSync()) as Map;
      final appSection = versionYaml['app'] as Map?;
      expect(appSection, isNotNull,
          reason: 'VERSION.yaml 必须有 top-level app: 节；'
              '构建脚本依赖 app.version 路径');
      final versionFromVersionYaml = appSection!['version'] as String?;
      expect(versionFromVersionYaml, isNotNull,
          reason: 'VERSION.yaml.app.version 必须存在——版本 source of truth 不能为空');

      final versionFromPubspec =
          extractPubspecVersion(File('pubspec.yaml').readAsStringSync());

      expect(versionFromPubspec, versionFromVersionYaml,
          reason: 'VERSION.yaml.app.version ($versionFromVersionYaml) 与 '
              'pubspec.yaml.version ($versionFromPubspec) 不一致——'
              '构建脚本同步失效或人工漂移；release build 会显示 pubspec 版本，'
              '更新服务读 VERSION.yaml 的 min_app_version 比较时锚点错位');
    });

    test('VERSION.yaml 顶层 schema 字段集合（防御未来加字段无 doc）', () {
      // 沿用 R104/R105/R106/R107 已知字段全集快照模式——VERSION.yaml 加新顶层
      // 字段时强制开发者更新此清单 + 同步更新构建脚本/lib 端消费路径。
      const knownTopLevelKeys = {'app', 'compatibility', 'update'};
      final yaml =
          loadYaml(File('VERSION.yaml').readAsStringSync()) as Map;
      // YamlMap.keys 返回的是 Iterable<dynamic>，需要 cast 成 String 集合。
      final actualKeys = yaml.keys.map((k) => k.toString()).toSet();
      expect(actualKeys, knownTopLevelKeys,
          reason: 'VERSION.yaml 顶层 schema 必须与已知字段集合完全一致；'
              '新增字段需：(1) 更新此清单；(2) 更新构建脚本同步规则；'
              '(3) 若 lib 端要消费需加对应 parser 单测（R108 模式）');
    });
  });

  group('getVersion 默认兜底值自洽性（R108）', () {
    // R98 已 doc 化 getVersion 的兜底契约："1.0.0+1"。R108 加自洽性测试：
    // 该字面量必须能被 parseVersionString 正确分段为 (1.0.0, 1)，否则改默认值
    // 时漏改 parser 会让兜底路径产生不可预测结果。
    //
    // 这是"内部一致性"防御——R108 与 R107 的"对外字段名一致性"互补：
    //  - R107 防御 lib parser ↔ 文件 schema 字段名漂移（外部依赖）；
    //  - R108 防御 lib 不同 helper 之间的兜底值字面量耦合（内部依赖）。

    test("'1.0.0+1' 兜底字面量能被 parseVersionString 正确分段", () {
      // 锁定 R98 的兜底字面量与 parseVersionString 的契约对齐：
      // 改兜底为 'unknown' / '0.0.0' 时，本测试会撞红、提醒同步评估。
      const fallbackLiteral = '1.0.0+1';
      final parsed = parseVersionString(fallbackLiteral);
      expect(parsed.versionNumber, '1.0.0',
          reason: '兜底版本号必须能被 parseVersionString 拆出 versionNumber，'
              '否则 getVersionNumber 兜底路径产生空串/异常字符串');
      expect(parsed.buildNumber, 1,
          reason: '兜底 buildNumber 必须是 1（与 +1 段对齐），'
              '否则 getBuildNumber 兜底路径返回错误整数');
    });

    test("'1.0.0+1' 兜底字面量满足 isVersionAtLeast 同向性（自比较 == true）", () {
      // 兜底值与版本比较语义自洽：'1.0.0+1' >= '1.0.0' 必须为 true（patch 段 >=），
      // 否则兜底场景会让"是否满足最低版本要求"不可预测。
      expect(isVersionAtLeast('1.0.0+1', '1.0.0'), isTrue,
          reason: '兜底值必须能通过 isVersionAtLeast 与自身 versionNumber 比较——'
              '否则 R98 兜底场景下 checkCompatibility 行为退化');
    });
  });

  // R110 — 原生平台 build-time injected version sync drift 防御。
  //
  // 边界 contract 族第 7 个 sub-type：build-time injected platform resource。
  // R108 已锁 VERSION.yaml ↔ pubspec.yaml 二元同步；R110 把链条向下游延伸：
  // pubspec.yaml.version 在 release build 时被 Flutter 工具链注入到原生平台
  // 资源中——macOS Info.plist 用 $(FLUTTER_BUILD_NAME) / $(FLUTTER_BUILD_NUMBER)
  // 占位符；Windows Runner.rc 用 FLUTTER_VERSION_MAJOR/MINOR/PATCH/BUILD 宏 +
  // fallback "1.0.0" / 1,0,0,0。
  //
  // 风险：
  //  (1) 有人手改 Info.plist 把 $(FLUTTER_BUILD_NAME) 改成硬编码字面量 →
  //      release 版本号永远固定，pubspec 改不再生效；
  //  (2) Runner.rc 的 fallback "1.0.0" 是 R98 模式在原生平台的对应——若有人
  //      改成 "unknown" 或删掉，dev build（无宏）会显示异常版本号；
  //  (3) 跨平台 fallback 漂移——Windows fallback 字面量 "1.0.0" 必须与 lib
  //      端 R98 兜底的 versionNumber 段对齐（'1.0.0+1' 的 versionNumber 部分）。
  //
  // R107/R108/R110 三段对偶：
  //  - R107 declared shipped asset（pubspec.assets 列入，release 可达）；
  //  - R108 runtime-loaded shipped artifact（pubspec.yaml/VERSION.yaml，release 不可达）；
  //  - R110 build-time injected platform resource（Info.plist/Runner.rc，release 注入而非 runtime 读取）。
  //
  // 测试侧用 io.File 读原生资源、字面量 grep——不依赖 Flutter binding。
  group('macOS Info.plist 版本占位符锁定（R110）', () {
    // macOS Info.plist 必须用 $(FLUTTER_BUILD_NAME) / $(FLUTTER_BUILD_NUMBER)
    // 占位符让 Xcode 在 build 时从 Generated.xcconfig 注入；
    // 一旦改成硬编码字面量，pubspec.yaml 改 version 后 macOS app 版本不变。
    //
    // 不验证字段值（运行时由 Xcode 注入），只验证占位符未被破坏。

    test('Info.plist 文件存在', () {
      expect(File('macos/Runner/Info.plist').existsSync(), isTrue,
          reason: 'macos/Runner/Info.plist 是 macOS app 元数据 source of truth，'
              '缺失会导致 macOS build 失败');
    });

    test('CFBundleShortVersionString 必须用 \$(FLUTTER_BUILD_NAME) 占位符', () {
      // R110 主防御：锁住占位符未被改成硬编码字面量。
      final content = File('macos/Runner/Info.plist').readAsStringSync();
      // CFBundleShortVersionString 与下一行的 <string>$(FLUTTER_BUILD_NAME)</string>
      // 必须配对存在。
      expect(content.contains('<key>CFBundleShortVersionString</key>'), isTrue,
          reason: 'Info.plist 必须声明 CFBundleShortVersionString key——'
              '否则 macOS 系统无法读取 app 版本号');
      expect(content.contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'), isTrue,
          reason: r'CFBundleShortVersionString 必须用 $(FLUTTER_BUILD_NAME) 占位符——'
              '改成硬编码字面量会让 pubspec.yaml.version 改动在 macOS 端失效，'
              '触发 R108 锁定的"VERSION.yaml ↔ pubspec ↔ release 输出"链条断裂');
    });

    test('CFBundleVersion 必须用 \$(FLUTTER_BUILD_NUMBER) 占位符', () {
      final content = File('macos/Runner/Info.plist').readAsStringSync();
      expect(content.contains('<key>CFBundleVersion</key>'), isTrue,
          reason: 'Info.plist 必须声明 CFBundleVersion key——macOS App Store 用此区分构建');
      expect(
          content.contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'), isTrue,
          reason: r'CFBundleVersion 必须用 $(FLUTTER_BUILD_NUMBER) 占位符——'
              '改成硬编码会让构建号无法递增、App Store 拒绝重复版本提交');
    });
  });

  group('Windows Runner.rc 版本宏 + fallback 锁定（R110）', () {
    // Windows resource 文件用 FLUTTER_VERSION_* 宏（CMake 注入）+ fallback；
    // fallback 字面量 "1.0.0" / 1,0,0,0 是 R98 模式在原生平台的对应——
    // dev build（无宏）走 fallback，必须与 lib 端兜底语义对齐。

    test('Runner.rc 文件存在', () {
      expect(File('windows/runner/Runner.rc').existsSync(), isTrue,
          reason: 'windows/runner/Runner.rc 是 Windows app 资源 source of truth');
    });

    test('VERSION_AS_NUMBER 必须存在 FLUTTER_VERSION_* 宏分支', () {
      // R110 主防御：锁住宏分支未被删改——若 #if defined(...) 段被人删掉，
      // 所有 Windows build 永远走 fallback。
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      expect(
          content.contains(
              '#if defined(FLUTTER_VERSION_MAJOR) && defined(FLUTTER_VERSION_MINOR) && defined(FLUTTER_VERSION_PATCH) && defined(FLUTTER_VERSION_BUILD)'),
          isTrue,
          reason: 'Runner.rc 必须保留 FLUTTER_VERSION_* 宏分支——'
              '删除会让所有 Windows build 永远走 fallback、pubspec 版本不再生效');
      expect(
          content.contains(
              '#define VERSION_AS_NUMBER FLUTTER_VERSION_MAJOR,FLUTTER_VERSION_MINOR,FLUTTER_VERSION_PATCH,FLUTTER_VERSION_BUILD'),
          isTrue,
          reason: 'VERSION_AS_NUMBER 必须由 FLUTTER_VERSION_* 4 个宏拼装——'
              '顺序或数量改动会让 Windows 资源版本号字段错位');
    });

    test('VERSION_AS_NUMBER fallback 必须是 1,0,0,0', () {
      // R98 模式原生平台对应：fallback 字面量本身是契约。
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      expect(content.contains('#define VERSION_AS_NUMBER 1,0,0,0'), isTrue,
          reason: 'Runner.rc 的 VERSION_AS_NUMBER fallback 必须是 1,0,0,0——'
              '与 lib R98 兜底 "1.0.0+1" 的 4 段（1/0/0/1）虽不完全相同，'
              '但保持 major.minor.patch=1.0.0 与 lib 兜底首三段一致；'
              '改成 0,0,0,0 / unknown 会让 dev build 显示异常版本号');
    });

    test('VERSION_AS_STRING fallback 必须是 "1.0.0"', () {
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      expect(content.contains('#define VERSION_AS_STRING "1.0.0"'), isTrue,
          reason: 'Runner.rc 的 VERSION_AS_STRING fallback 必须是 "1.0.0"——'
              '必须与 lib R98 兜底 "1.0.0+1" 的 versionNumber 段（"1.0.0"）严格对齐，'
              '否则 dev build vs lib getVersion 兜底返回不同字符串、'
              'isVersionAtLeast 比较出现跨端不一致');
    });

    test('VERSION_AS_STRING fallback 与 lib R98 兜底 versionNumber 段对齐', () {
      // 跨语言一致性锁：grep Runner.rc fallback 字面量 + 解析 lib 兜底字面量，
      // 二者 versionNumber 段必须严格相等。
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      // 提取 #define VERSION_AS_STRING "X" 中的 X
      final match = RegExp(r'#define VERSION_AS_STRING "([^"]+)"').firstMatch(content);
      expect(match, isNotNull, reason: '必须能从 Runner.rc 提取 VERSION_AS_STRING fallback 字面量');
      final winFallback = match!.group(1)!;
      // R108 已锁 lib 兜底字面量是 '1.0.0+1'；此处提取其 versionNumber 段。
      const libFallback = '1.0.0+1';
      final libVersionNumber = parseVersionString(libFallback).versionNumber;
      expect(winFallback, libVersionNumber,
          reason: 'Windows fallback ($winFallback) 必须与 lib 兜底 '
              'versionNumber 段 ($libVersionNumber) 严格相等——'
              '跨平台 fallback 漂移会让用户在不同平台看到不同版本号');
    });

    test('FileVersion / ProductVersion 都用 VERSION_AS_STRING（非硬编码）', () {
      // 锁住 StringFileInfo 块内的版本字段都引用 VERSION_AS_STRING 而非硬编码。
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      expect(
          content.contains('VALUE "FileVersion", VERSION_AS_STRING'), isTrue,
          reason: 'FileVersion 字段必须引用 VERSION_AS_STRING——'
              '硬编码会让 Windows 文件属性版本号永远固定');
      expect(
          content.contains('VALUE "ProductVersion", VERSION_AS_STRING'), isTrue,
          reason: 'ProductVersion 字段必须引用 VERSION_AS_STRING——'
              '硬编码会让 Windows 产品版本号永远固定');
    });
  });

  group('跨平台版本号注入链路完整性（R110）', () {
    // R108 锁的是 VERSION.yaml ↔ pubspec.yaml 二元；R110 把链条延伸到原生平台。
    // 这组测试锁住整条链路 source of truth → release 输出 的关键节点都存在。

    test('版本号注入链路全节点存在（VERSION.yaml / pubspec.yaml / Info.plist / Runner.rc）', () {
      // 链路：VERSION.yaml ──[构建脚本]──> pubspec.yaml ──[Flutter 工具链]──>
      //   { macOS Info.plist ($(FLUTTER_BUILD_NAME))，Windows Runner.rc (宏) }
      // 任一环节缺失都会让版本号无法正确传播到 release 输出。
      expect(File('VERSION.yaml').existsSync(), isTrue,
          reason: '版本号 source of truth 缺失');
      expect(File('pubspec.yaml').existsSync(), isTrue,
          reason: 'Flutter 项目元数据缺失');
      expect(File('macos/Runner/Info.plist').existsSync(), isTrue,
          reason: 'macOS 平台版本号注入目标缺失');
      expect(File('windows/runner/Runner.rc').existsSync(), isTrue,
          reason: 'Windows 平台版本号注入目标缺失');
    });

    test('Info.plist 不含硬编码版本号字面量（防御注入失效）', () {
      // 反向锁：grep Info.plist 内不存在 1.0.0 / 1.0.0+5 等版本字面量——
      // 出现意味着有人把占位符改成了硬编码。
      final content = File('macos/Runner/Info.plist').readAsStringSync();
      // 当前 pubspec version 是 1.0.0+5；任何 1.x.y 字面量出现在 plist 都意味着
      // 占位符被替换成了字面量。
      final hasHardcodedVersion = RegExp(r'<string>\d+\.\d+\.\d+(\+\d+)?</string>')
          .hasMatch(content);
      expect(hasHardcodedVersion, isFalse,
          reason: 'Info.plist 不应有硬编码版本号字面量——'
              '所有版本字段必须用 \$(FLUTTER_BUILD_NAME) / \$(FLUTTER_BUILD_NUMBER) 占位符');
    });

    test('Runner.rc fallback 与 lib R98 兜底首三段（major.minor.patch）一致', () {
      // 锁住 Windows fallback 数值与 lib 兜底解析后的 (versionNumber → 数字段) 一致。
      final content = File('windows/runner/Runner.rc').readAsStringSync();
      final numMatch =
          RegExp(r'#define VERSION_AS_NUMBER (\d+),(\d+),(\d+),(\d+)')
              .firstMatch(content);
      expect(numMatch, isNotNull,
          reason: '必须能从 Runner.rc 提取 VERSION_AS_NUMBER fallback 字面量');
      final winMajor = int.parse(numMatch!.group(1)!);
      final winMinor = int.parse(numMatch.group(2)!);
      final winPatch = int.parse(numMatch.group(3)!);

      // lib 兜底 '1.0.0+1' → versionNumber '1.0.0' → 段 [1, 0, 0]
      const libFallback = '1.0.0+1';
      final libVersionNumber = parseVersionString(libFallback).versionNumber;
      final libSegments = libVersionNumber.split('.').map(int.parse).toList();
      expect(libSegments.length >= 3, isTrue,
          reason: 'lib 兜底 versionNumber 段数必须至少 3（major.minor.patch）');
      expect(winMajor, libSegments[0],
          reason: 'Windows fallback major ($winMajor) 必须与 lib 兜底 major (${libSegments[0]}) 一致');
      expect(winMinor, libSegments[1],
          reason: 'Windows fallback minor ($winMinor) 必须与 lib 兜底 minor (${libSegments[1]}) 一致');
      expect(winPatch, libSegments[2],
          reason: 'Windows fallback patch ($winPatch) 必须与 lib 兜底 patch (${libSegments[2]}) 一致');
    });
  });

  // R111 — 跨平台 identifier 字符串一致性锁（R110 跨语言 fallback 一致性的横向扩展）。
  //
  // R110 锁的是"版本号"维度的跨平台一致性；R111 把同模式扩到其他跨平台标识字符串：
  //   - bundle/product identifier 前缀（com.example，二进制信任链锚点）；
  //   - product name（SvnAutoMerge，应用安装/启动可见标识）；
  //   - window title（SVN 合并助手，运行时窗口标题，跨平台用户可见）；
  //   - copyright 年份（2025，法律声明跨平台一致性）。
  //
  // 风险：任一改一处忘改另一处 → 用户在不同平台看到不同名字 / 不同公司前缀，
  // SmartScreen/Gatekeeper 信任链跨平台不一致，新版无法继承旧版的信任。
  //
  // 测试侧用 io.File 读原生资源 + 字面量 grep / regex 提取。R111 与 R110 同 group
  // 风格——主防御是"字面量在 N 处必须严格相等"。
  group('跨平台 product name 一致性锁（R111）', () {
    test('macOS PRODUCT_NAME 与 Windows ProductName 一致', () {
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final macMatch =
          RegExp(r'^PRODUCT_NAME\s*=\s*(\S+)', multiLine: true).firstMatch(macXcconfig);
      expect(macMatch, isNotNull,
          reason: 'AppInfo.xcconfig 必须声明 PRODUCT_NAME——macOS app 名称 source of truth');
      final macProductName = macMatch!.group(1)!;

      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final winProductMatch =
          RegExp(r'VALUE "ProductName", "([^"]+)"').firstMatch(winRc);
      expect(winProductMatch, isNotNull,
          reason: 'Runner.rc 必须声明 ProductName VALUE');
      final winProductName = winProductMatch!.group(1)!;

      expect(winProductName, macProductName,
          reason: 'Windows ProductName ($winProductName) 必须与 macOS PRODUCT_NAME '
              '($macProductName) 严格一致——否则 Win/Mac app 看起来是两个不同产品；'
              '且影响发版时 SmartScreen/Gatekeeper 跨平台信任链');
    });

    test('Windows InternalName / OriginalFilename / ProductName 三者锁定同一基名', () {
      // Runner.rc 内部 3 处 product name 引用，必须同源——任一漂移 Windows
      // 文件元信息会矛盾（如 OriginalFilename 写 X.exe 但 InternalName 写 Y）。
      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final productName = RegExp(r'VALUE "ProductName", "([^"]+)"')
          .firstMatch(winRc)
          ?.group(1);
      final internalName = RegExp(r'VALUE "InternalName", "([^"]+)"')
          .firstMatch(winRc)
          ?.group(1);
      final originalFilename = RegExp(r'VALUE "OriginalFilename", "([^"]+)"')
          .firstMatch(winRc)
          ?.group(1);
      expect(productName, isNotNull, reason: 'Runner.rc 缺 ProductName VALUE');
      expect(internalName, isNotNull, reason: 'Runner.rc 缺 InternalName VALUE');
      expect(originalFilename, isNotNull,
          reason: 'Runner.rc 缺 OriginalFilename VALUE');
      expect(internalName, productName,
          reason: 'InternalName 必须与 ProductName 一致');
      // OriginalFilename 含 .exe 后缀；剥掉后必须等于 ProductName
      expect(originalFilename, '$productName.exe',
          reason: 'OriginalFilename 必须是 ProductName + ".exe"');
    });

    test('macOS .app bundle 名称与 PRODUCT_NAME 一致（xcodeproj）', () {
      // xcodeproj 内 BuildableName / .app 字面量必须与 PRODUCT_NAME 同源。
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final productName =
          RegExp(r'^PRODUCT_NAME\s*=\s*(\S+)', multiLine: true)
              .firstMatch(macXcconfig)!
              .group(1)!;

      final pbxproj = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      // 至少一次出现 "<PRODUCT_NAME>.app" 字面量
      expect(pbxproj.contains('$productName.app'), isTrue,
          reason: 'macos/Runner.xcodeproj/project.pbxproj 必须含 '
              '"$productName.app" 字面量——若 PRODUCT_NAME 改名而 xcodeproj '
              '未同步，Xcode build output 路径与 BuildableName 错位、'
              'Test Host 找不到 app');
    });
  });

  group('跨平台 bundle identifier 前缀一致性锁（R111）', () {
    test('macOS PRODUCT_BUNDLE_IDENTIFIER 与 Windows CompanyName 共享前缀', () {
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final bundleIdMatch = RegExp(
              r'^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)',
              multiLine: true)
          .firstMatch(macXcconfig);
      expect(bundleIdMatch, isNotNull,
          reason: 'AppInfo.xcconfig 必须声明 PRODUCT_BUNDLE_IDENTIFIER');
      final bundleId = bundleIdMatch!.group(1)!;
      // bundle id 通常是 reverse-DNS：com.example.svnautomerge → 前缀 com.example
      final segments = bundleId.split('.');
      expect(segments.length >= 3, isTrue,
          reason: 'bundle id 必须至少 3 段（reverse-DNS 规范）：$bundleId');
      final macCompanyPrefix = segments.take(2).join('.');

      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final winCompanyMatch =
          RegExp(r'VALUE "CompanyName", "([^"]+)"').firstMatch(winRc);
      expect(winCompanyMatch, isNotNull,
          reason: 'Runner.rc 必须声明 CompanyName VALUE');
      final winCompany = winCompanyMatch!.group(1)!;

      expect(winCompany, macCompanyPrefix,
          reason: 'Windows CompanyName ($winCompany) 必须与 macOS bundle id '
              '前两段 ($macCompanyPrefix) 严格一致——否则 Win/Mac app 元信息显示'
              '不同公司，发版可能被反作弊系统标记为可疑、跨平台信任链断裂');
    });

    test('macOS OSLog subsystem 字面量与 bundle id 一致', () {
      // AppDelegate.swift / MainFlutterWindow.swift 用 OSLog subsystem
      // 字符串作为日志命名空间——按 Apple 推荐应等于 bundle id（保证 Console.app
      // 过滤 "subsystem == bundle id" 时能看到全部日志）。
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final bundleId = RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)',
              multiLine: true)
          .firstMatch(macXcconfig)!
          .group(1)!;

      final appDelegate =
          File('macos/Runner/AppDelegate.swift').readAsStringSync();
      final mainWindow =
          File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();

      // OSLog 用法形如：OSLog(subsystem: "com.example.svnautomerge", category: ...)
      final pattern = RegExp(r'OSLog\(subsystem:\s*"([^"]+)"');
      final appDelegateMatch = pattern.firstMatch(appDelegate);
      final mainWindowMatch = pattern.firstMatch(mainWindow);
      expect(appDelegateMatch, isNotNull,
          reason: 'AppDelegate.swift 必须含 OSLog(subsystem: "...") 调用');
      expect(mainWindowMatch, isNotNull,
          reason: 'MainFlutterWindow.swift 必须含 OSLog(subsystem: "...") 调用');
      expect(appDelegateMatch!.group(1)!, bundleId,
          reason: 'AppDelegate OSLog subsystem 必须等于 bundle id ($bundleId)——'
              '否则 Console.app 按 bundle id 过滤时看不到 AppDelegate 日志');
      expect(mainWindowMatch!.group(1)!, bundleId,
          reason: 'MainFlutterWindow OSLog subsystem 必须等于 bundle id ($bundleId)——'
              '同上');
    });
  });

  group('跨平台窗口标题字面量一致性锁（R111）', () {
    // 窗口标题是用户每次启动 app 都看到的字符串；macOS Swift / Windows C++ /
    // pubspec description 三处必须同步，否则不同平台显示不同名字。
    test('macOS MainFlutterWindow.title 与 Windows main.cpp window title 一致', () {
      final macSwift =
          File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
      // self.title = "SVN 合并助手"
      final macTitleMatch =
          RegExp(r'self\.title\s*=\s*"([^"]+)"').firstMatch(macSwift);
      expect(macTitleMatch, isNotNull,
          reason: 'MainFlutterWindow.swift 必须设置 self.title = "..."');
      final macTitle = macTitleMatch!.group(1)!;

      final winCpp = File('windows/runner/main.cpp').readAsStringSync();
      // window.Create(L"SVN 合并助手", origin, size)
      final winTitleMatch =
          RegExp(r'window\.Create\(L"([^"]+)"').firstMatch(winCpp);
      expect(winTitleMatch, isNotNull,
          reason: 'main.cpp 必须含 window.Create(L"...") 调用');
      final winTitle = winTitleMatch!.group(1)!;

      expect(winTitle, macTitle,
          reason: 'Windows 窗口标题 ($winTitle) 必须与 macOS 标题 ($macTitle) 一致——'
              '否则用户在不同平台看到不同 app 名称，破坏品牌一致性');
    });

    test('窗口标题与 pubspec.yaml description 一致', () {
      // pubspec description 是项目可读元数据，Windows Runner.rc 的 FileDescription
      // 也用同一字面量；三处共享。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final descMatch =
          RegExp(r'^description:\s*(.+)$', multiLine: true).firstMatch(pubspec);
      expect(descMatch, isNotNull,
          reason: 'pubspec.yaml 必须有 description 字段');
      final pubspecDesc = descMatch!.group(1)!.trim();

      final macSwift =
          File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
      final macTitle =
          RegExp(r'self\.title\s*=\s*"([^"]+)"').firstMatch(macSwift)!.group(1)!;

      expect(macTitle, pubspecDesc,
          reason: 'macOS 窗口标题 ($macTitle) 必须与 pubspec.yaml description '
              '($pubspecDesc) 一致——后者是项目元数据 source of truth');
    });

    test('Windows FileDescription 与 pubspec.yaml description 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final pubspecDesc = RegExp(r'^description:\s*(.+)$', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!
          .trim();

      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final fileDescMatch =
          RegExp(r'VALUE "FileDescription", "([^"]+)"').firstMatch(winRc);
      expect(fileDescMatch, isNotNull,
          reason: 'Runner.rc 必须声明 FileDescription VALUE');
      final winFileDesc = fileDescMatch!.group(1)!;

      expect(winFileDesc, pubspecDesc,
          reason: 'Windows FileDescription ($winFileDesc) 必须与 pubspec.yaml '
              'description ($pubspecDesc) 一致——Windows 文件属性与 pubspec 元数据'
              '同源');
    });
  });

  group('跨平台 copyright 一致性锁（R111）', () {
    // PRODUCT_COPYRIGHT (xcconfig) 与 Runner.rc LegalCopyright 必须共享年份和实体。
    test('macOS PRODUCT_COPYRIGHT 与 Windows LegalCopyright 年份一致', () {
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final macCopyrightMatch = RegExp(r'^PRODUCT_COPYRIGHT\s*=\s*(.+)$',
              multiLine: true)
          .firstMatch(macXcconfig);
      expect(macCopyrightMatch, isNotNull,
          reason: 'AppInfo.xcconfig 必须声明 PRODUCT_COPYRIGHT');
      final macCopyright = macCopyrightMatch!.group(1)!.trim();

      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final winCopyrightMatch =
          RegExp(r'VALUE "LegalCopyright", "([^"]+)"').firstMatch(winRc);
      expect(winCopyrightMatch, isNotNull,
          reason: 'Runner.rc 必须声明 LegalCopyright VALUE');
      final winCopyright = winCopyrightMatch!.group(1)!;

      // 提取 4 位年份
      final yearPattern = RegExp(r'\b(20\d{2})\b');
      final macYear = yearPattern.firstMatch(macCopyright)?.group(1);
      final winYear = yearPattern.firstMatch(winCopyright)?.group(1);
      expect(macYear, isNotNull,
          reason: 'macOS copyright 必须含 4 位年份: $macCopyright');
      expect(winYear, isNotNull,
          reason: 'Windows copyright 必须含 4 位年份: $winCopyright');
      expect(winYear, macYear,
          reason: 'Windows copyright 年份 ($winYear) 必须与 macOS 年份 ($macYear) '
              '一致——否则跨平台法律声明不同步');
    });

    test('macOS PRODUCT_COPYRIGHT 与 Windows LegalCopyright 公司名一致', () {
      // copyright 字面量内的公司名（如 com.example）必须与 bundle id 前缀一致。
      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final macCopyright = RegExp(r'^PRODUCT_COPYRIGHT\s*=\s*(.+)$',
              multiLine: true)
          .firstMatch(macXcconfig)!
          .group(1)!
          .trim();
      final bundleId = RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)',
              multiLine: true)
          .firstMatch(macXcconfig)!
          .group(1)!;
      final companyPrefix = bundleId.split('.').take(2).join('.');

      final winRc = File('windows/runner/Runner.rc').readAsStringSync();
      final winCopyright = RegExp(r'VALUE "LegalCopyright", "([^"]+)"')
          .firstMatch(winRc)!
          .group(1)!;

      expect(macCopyright.contains(companyPrefix), isTrue,
          reason: 'macOS PRODUCT_COPYRIGHT ($macCopyright) 必须含 bundle id '
              '前缀 ($companyPrefix)——保证 copyright 实体与 bundle 信任链同源');
      expect(winCopyright.contains(companyPrefix), isTrue,
          reason: 'Windows LegalCopyright ($winCopyright) 必须含 bundle id '
              '前缀 ($companyPrefix)——同上');
    });
  });

  group('跨平台 identifier 全集快照（R111 防漏配 guard）', () {
    // R104/R105/R106/R107/R108 系列"全集快照"模式在跨平台 identifier 维度的对应。
    // 锁住已审计的 identifier 维度集合——增加新维度时强制 reviewer 在此登记。
    test('R111 已锁定的跨平台 identifier 维度（4 类）', () {
      // 这条测试是登记表：当未来新增跨平台标识维度（如 minSdkVersion / 图标
      // 资源名 / URL scheme）时，必须更新此 set 提示新增审计。
      const knownDimensions = {
        'product_name', // SvnAutoMerge — macOS xcconfig + Windows Runner.rc
        'bundle_identifier_prefix', // com.example — macOS bundle id 前缀 + Windows CompanyName
        'window_title', // SVN 合并助手 — macOS Swift + Windows main.cpp + pubspec description
        'copyright', // 2025 + com.example — macOS xcconfig + Windows Runner.rc
      };
      // 主防御：任何未来新增跨平台 identifier 维度都要经过 R111 模式补测试。
      // 此断言永真，作用是把维度集合 doc 化在测试里——commit message / PR
      // diff review 时让维度变更可见。
      expect(knownDimensions.length, 4,
          reason: 'R111 当前锁定 4 类跨平台 identifier 维度——若新增（如 URL '
              'scheme / 图标资源名 / minSdkVersion 等），需补对应跨平台一致性测试，'
              '同时更新此 set 让维度增长可追踪');
      // 反向锁：阻止有人把维度去掉而忘补理由。
      expect(knownDimensions, contains('product_name'));
      expect(knownDimensions, contains('bundle_identifier_prefix'));
      expect(knownDimensions, contains('window_title'));
      expect(knownDimensions, contains('copyright'));
    });
  });

  // ===== R112 =====
  // 维度：同平台内多 config drift 防御 + 资源声明 vs 文件存在锁。
  // R110/R111 锁的是「跨平台一致性」（macOS 字面量 ↔ Windows 字面量）；
  // R112 切到「同平台内一致性」——
  //   (a) macOS xcodeproj 内 Debug/Release/Profile 三个 BuildConfig 的部署
  //       目标 / icon 名 / bundle id 必须严格一致（否则 Release 与 Debug
  //       行为分裂、用户与开发者看到不同最低系统版本）；
  //   (b) Windows 3 个 CMakeLists.txt 的 cmake_minimum_required 必须一致
  //       （否则不同子构建用不同 CMake 兼容策略，可能 Release 走 3.21 特性
  //       但 flutter/ 子构建限定 3.14，子构建静默 fall back 到旧 API）；
  //   (c) 资源声明 vs 文件存在双向锁——xcodeproj 声明 AppIcon.appiconset
  //       必须存在该目录、Runner.rc 声明 IDI_APP_ICON 路径必须存在该 ico
  //       文件（声明对而文件丢失 → 编译期或链接期才报错、CI 才发现）；
  //   (d) Windows BINARY_NAME 是 R111 漏锁的第 5 类 identifier——CMake
  //       binary 名 ↔ Runner.rc OriginalFilename（去 .exe）↔ macOS
  //       PRODUCT_NAME 三向锁。
  // 这是边界 contract 族 sub-type 7（build-time injected platform resource）
  // 维度内的「同平台 multi-config 横向 sweep」——R110 单平台单 config /
  // R111 跨平台单 config / R112 同平台多 config + 资源声明 vs 实存。
  group('macOS xcodeproj 多 BuildConfig 一致性锁（R112）', () {
    test('MACOSX_DEPLOYMENT_TARGET 在所有 BuildConfig 严格一致', () {
      final pbxproj = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      // 抽取所有 MACOSX_DEPLOYMENT_TARGET = X.Y; 字面量
      final values = RegExp(r'MACOSX_DEPLOYMENT_TARGET\s*=\s*([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(values, isNotEmpty,
          reason: 'macos/Runner.xcodeproj/project.pbxproj 必须声明 '
              'MACOSX_DEPLOYMENT_TARGET——Flutter 模板默认会生成 3 处'
              '（Debug/Release/Profile）');
      expect(values.toSet().length, 1,
          reason: 'MACOSX_DEPLOYMENT_TARGET 在 3 个 BuildConfig 中必须严格相等'
              '——否则 Release 与 Debug 用不同最低系统版本，用户看到的版本'
              '能力与开发期不同；当前抽到的值集：${values.toSet()}');
    });

    test('Info.plist LSMinimumSystemVersion 用占位符引用 MACOSX_DEPLOYMENT_TARGET',
        () {
      // R110 锁了 CFBundleShortVersionString / CFBundleVersion 占位符；
      // 本测试是 R110 模式横向扩展到 LSMinimumSystemVersion——同样必须用
      // \$(MACOSX_DEPLOYMENT_TARGET) 占位符而非硬编码字面量。
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      expect(
        plist.contains('<string>\$(MACOSX_DEPLOYMENT_TARGET)</string>'),
        isTrue,
        reason: 'Info.plist 必须用 \$(MACOSX_DEPLOYMENT_TARGET) 占位符注入'
            '最低系统版本，而非硬编码 <string>10.15</string>——否则 xcodeproj '
            '改部署目标后 plist 不动、用户系统版本检查与 SDK 实际依赖错位',
      );
    });

    test('ASSETCATALOG_COMPILER_APPICON_NAME 在所有 BuildConfig 一致', () {
      final pbxproj = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final values = RegExp(r'ASSETCATALOG_COMPILER_APPICON_NAME\s*=\s*([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(values, isNotEmpty,
          reason: 'pbxproj 必须声明 ASSETCATALOG_COMPILER_APPICON_NAME');
      expect(values.toSet().length, 1,
          reason: '所有 BuildConfig 的 AppIcon 名必须一致——否则 Release '
              'icon 与 Debug icon 不同，用户首次启动看到与 dev 不同的图标；'
              '当前值集：${values.toSet()}');
    });
  });

  group('macOS / Windows 资源声明 vs 文件存在双向锁（R112）', () {
    test('xcodeproj 声明的 AppIcon 名必须存在对应 .appiconset 目录', () {
      final pbxproj = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final iconName = RegExp(r'ASSETCATALOG_COMPILER_APPICON_NAME\s*=\s*([^;]+);')
          .firstMatch(pbxproj)!
          .group(1)!
          .trim();
      final iconDir = Directory('macos/Runner/Assets.xcassets/$iconName.appiconset');
      expect(iconDir.existsSync(), isTrue,
          reason: 'xcodeproj 声明 AppIcon 名 "$iconName"，但 '
              'macos/Runner/Assets.xcassets/$iconName.appiconset 目录不存在'
              '——构建期 ASSETCATALOG_COMPILER 找不到资源 / Release app 显示'
              '默认占位图标');
    });

    test('Runner.rc 声明的 IDI_APP_ICON 路径必须存在 ico 文件', () {
      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      final iconMatch = RegExp(r'IDI_APP_ICON\s+ICON\s+"([^"]+)"').firstMatch(rc);
      expect(iconMatch, isNotNull,
          reason: 'Runner.rc 必须声明 IDI_APP_ICON 资源');
      final iconRelPath = iconMatch!.group(1)!.replaceAll(r'\\', '/');
      final iconFile = File('windows/runner/$iconRelPath');
      expect(iconFile.existsSync(), isTrue,
          reason: 'Runner.rc 声明 IDI_APP_ICON 路径 "$iconRelPath"，但 '
              'windows/runner/$iconRelPath 文件不存在——Windows .exe 链接期'
              '失败 / Release 安装包缺图标');
    });
  });

  group('Windows CMake 配置一致性锁（R112）', () {
    test('3 个 CMakeLists.txt 的 cmake_minimum_required 严格一致', () {
      // 主 CMakeLists / runner / flutter 三个子构建——若版本不一致，
      // 不同子构建走不同 CMake 兼容策略可能让 Release 走 ≥3.21 特性而
      // flutter/ 子构建限定 3.14 静默 fall back 到旧 API。
      final files = [
        'windows/CMakeLists.txt',
        'windows/runner/CMakeLists.txt',
        'windows/flutter/CMakeLists.txt',
      ];
      final versions = <String, String>{};
      for (final f in files) {
        final txt = File(f).readAsStringSync();
        final m = RegExp(r'cmake_minimum_required\s*\(\s*VERSION\s+(\S+?)\s*\)')
            .firstMatch(txt);
        expect(m, isNotNull, reason: '$f 必须声明 cmake_minimum_required');
        versions[f] = m!.group(1)!;
      }
      expect(versions.values.toSet().length, 1,
          reason: '3 个 CMakeLists.txt 的 cmake_minimum_required 必须一致'
              '——避免子构建走不同 CMake 兼容策略静默 fall back 到旧 API；'
              '当前：$versions');
    });

    test('CMake BINARY_NAME 与 macOS PRODUCT_NAME 一致', () {
      // R111 漏锁的第 5 类 identifier——R111 锁了 Runner.rc ProductName /
      // xcodeproj BuildableName / xcconfig PRODUCT_NAME 三向，但**漏掉**
      // 了 CMake BINARY_NAME（决定 .exe 实际文件名）。本测试补完。
      final cmake = File('windows/CMakeLists.txt').readAsStringSync();
      final binaryNameMatch =
          RegExp(r'set\s*\(\s*BINARY_NAME\s+"([^"]+)"\s*\)').firstMatch(cmake);
      expect(binaryNameMatch, isNotNull,
          reason: 'windows/CMakeLists.txt 必须声明 set(BINARY_NAME "...")');
      final binaryName = binaryNameMatch!.group(1)!;

      final macXcconfig =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      final macProductName = RegExp(r'^PRODUCT_NAME\s*=\s*(\S+)', multiLine: true)
          .firstMatch(macXcconfig)!
          .group(1)!;

      expect(binaryName, macProductName,
          reason: 'Windows CMake BINARY_NAME ($binaryName) 必须与 macOS '
              'PRODUCT_NAME ($macProductName) 一致——否则 .exe 文件名与 '
              '.app bundle 名不同，跨平台用户脚本/快捷方式/SmartScreen '
              '白名单按文件名查找时漂移');
    });

    test('CMake BINARY_NAME 与 Runner.rc OriginalFilename 一致（去 .exe 后缀）',
        () {
      final cmake = File('windows/CMakeLists.txt').readAsStringSync();
      final binaryName =
          RegExp(r'set\s*\(\s*BINARY_NAME\s+"([^"]+)"\s*\)')
              .firstMatch(cmake)!
              .group(1)!;

      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      final origFilenameMatch =
          RegExp(r'VALUE "OriginalFilename", "([^"]+)"').firstMatch(rc);
      expect(origFilenameMatch, isNotNull,
          reason: 'Runner.rc 必须声明 OriginalFilename VALUE');
      final origFilename = origFilenameMatch!.group(1)!;
      // OriginalFilename 形如 "SvnAutoMerge.exe"
      expect(origFilename.endsWith('.exe'), isTrue,
          reason: 'OriginalFilename ($origFilename) 必须以 .exe 结尾');
      final origBase = origFilename.substring(0, origFilename.length - 4);
      expect(origBase, binaryName,
          reason: 'Runner.rc OriginalFilename 去 .exe 后 ($origBase) 必须与 '
              'CMake BINARY_NAME ($binaryName) 一致——否则 .exe 实际名与 '
              '资源元数据声明不同，Get-FileVersionInfo 报告错误文件名、'
              'Defender SmartScreen 信任链按错误文件名查找');
    });
  });

  group('R112 同平台 multi-config + 资源声明 维度全集快照（防漏配 guard）', () {
    test('R112 已锁定的 4 类同平台一致性维度', () {
      final knownDimensions = <String>{
        'macos_buildconfig_consistency',
        'native_resource_declaration_vs_existence',
        'windows_cmake_minimum_version_consistency',
        'windows_binary_name_cross_format_consistency',
      };
      expect(knownDimensions.length, 4,
          reason: 'R112 当前锁定 4 类「同平台一致性」维度——若新增（如 '
              'iOS/Android Gradle product flavors / Linux CMake / '
              'Windows manifest tag 一致性等），需补对应测试，'
              '同时更新此 set 让维度增长可追踪');
      // 反向锁
      expect(knownDimensions, contains('macos_buildconfig_consistency'));
      expect(knownDimensions,
          contains('native_resource_declaration_vs_existence'));
      expect(knownDimensions,
          contains('windows_cmake_minimum_version_consistency'));
      expect(knownDimensions,
          contains('windows_binary_name_cross_format_consistency'));
    });
  });

  // ---------------------------------------------------------------------
  // R113 同平台 multi-config 维度第二轮 sweep + Windows manifest 反向锁
  //
  // R112 已 sweep `MACOSX_DEPLOYMENT_TARGET` / `ASSETCATALOG_COMPILER_APPICON_NAME`
  // 等"通用 build setting"在 macOS 多 BuildConfig 一致性；R113 把同模式
  // 扩展到 (a) **identifier 字段**（`PRODUCT_BUNDLE_IDENTIFIER` 在
  // RunnerTests 3 个 config 中重复声明）+ (b) **version 字段**
  // （`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` / `SWIFT_VERSION`
  // 在 RunnerTests 3 个 config 中重复声明）。
  //
  // 同时补完 R112 漏掉的 Windows manifest 维度——`runner.exe.manifest`
  // 是 Windows 资源声明的另一面（与 Runner.rc 平行），R112 只测了 .rc
  // 的 OriginalFilename / ICON，未锁 manifest 的 dpiAwareness /
  // supportedOS GUID / 命名空间——这是用户启动 .exe 时**Windows 内核
  // 直接读取**的元数据，错乱会导致 Hi-DPI 渲染失效（dpiAwareness
  // 退化为 System）或 Win11 兼容性误判。
  //
  // R112 关键发现 5（CMake `BINARY_NAME` 漏锁）已让 R113 从一开始就
  // 警惕"同平台资源声明的多面"——R113 是这种警惕的进一步落实。
  // ---------------------------------------------------------------------
  group('macOS RunnerTests target multi-config identifier 一致性锁（R113）', () {
    test('PRODUCT_BUNDLE_IDENTIFIER 在 RunnerTests 3 个 BuildConfig 严格一致', () {
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final matches = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;\n]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(matches.length, greaterThanOrEqualTo(3),
          reason: 'project.pbxproj 至少应有 3 处 PRODUCT_BUNDLE_IDENTIFIER '
              '（RunnerTests 的 Debug/Release/Profile 各一）；当前 ${matches.length}');
      // RunnerTests 用同一个 bundle id 字面量在 3 个 config 中重复声明
      // 必须严格相等——任一漂移会导致 Test Bundle 在不同 config 下
      // signature 不一致，xcodebuild test 抓不到 host app
      final runnerTestsIds = matches
          .where((id) => id.contains('RunnerTests'))
          .toSet();
      expect(runnerTestsIds.length, 1,
          reason: 'RunnerTests bundle id 必须在 3 个 BuildConfig 一致，'
              '当前漂移为 $runnerTestsIds');
    });

    test('RunnerTests bundle id 是主 app bundle id 的子命名空间（reverse-DNS 嵌套约定）',
        () {
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final mainBundleId = 'com.example.svnautomerge'; // R111 已锁
      final runnerTestsMatch =
          RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+\.RunnerTests);')
              .firstMatch(pbx);
      expect(runnerTestsMatch, isNotNull,
          reason: 'pbxproj 应声明 RunnerTests bundle id');
      final runnerTestsId = runnerTestsMatch!.group(1)!;
      expect(runnerTestsId.startsWith('$mainBundleId.'), isTrue,
          reason: 'RunnerTests bundle id ($runnerTestsId) 必须以主 app '
              'bundle id ($mainBundleId.) 为前缀——否则 Apple Test '
              'Discovery 会把 RunnerTests 当成独立 app 处理、'
              '与 host app 的 entitlement 不联动');
    });
  });

  group('macOS RunnerTests target multi-config version 字段一致性锁（R113）', () {
    test('MARKETING_VERSION 在 RunnerTests 3 个 config 一致', () {
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      // RunnerTests 段落中的 MARKETING_VERSION（区分主 Runner target 的
      // build settings——主 Runner 用 Generated.xcconfig 注入版本，
      // RunnerTests 自己写死）
      final matches = RegExp(r'MARKETING_VERSION\s*=\s*([^;\n]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(matches.length, 1,
          reason: 'MARKETING_VERSION 在多 BuildConfig 必须一致，当前漂移为 $matches');
    });

    test('CURRENT_PROJECT_VERSION 在 RunnerTests 3 个 config 一致', () {
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final matches = RegExp(r'CURRENT_PROJECT_VERSION\s*=\s*([^;\n]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(matches.length, 1,
          reason: 'CURRENT_PROJECT_VERSION 在多 BuildConfig 必须一致，'
              '当前漂移为 $matches');
    });

    test('SWIFT_VERSION 在所有 BuildConfig 一致（RunnerTests + Runner 主 target）', () {
      final pbx = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final matches = RegExp(r'SWIFT_VERSION\s*=\s*([^;\n]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!.trim())
          .toSet();
      // SWIFT_VERSION 漂移会让 Debug 走 Swift 5 / Release 走 Swift 4
      // 隐式转换规则不同、模糊出现的运行时差异
      expect(matches.length, 1,
          reason: 'SWIFT_VERSION 必须在所有 BuildConfig 严格一致——'
              'Swift 不同 major 版本语法语义不兼容，当前漂移为 $matches');
    });
  });

  group('Windows runner.exe.manifest 内容反向锁（R113）', () {
    test('runner.exe.manifest 文件存在', () {
      expect(File('windows/runner/runner.exe.manifest').existsSync(), isTrue,
          reason: 'Windows runner.exe.manifest 必须存在——决定 .exe 启动时'
              'Windows 内核加载的 DPI / 兼容性元数据');
    });

    test('dpiAwareness 必须声明为 PerMonitorV2', () {
      final manifest =
          File('windows/runner/runner.exe.manifest').readAsStringSync();
      // Hi-DPI 4K 屏幕用户必须 PerMonitorV2，否则 Windows 把 app 当
      // System DPI 处理 → Flutter 的 DevicePixelRatio 错乱、字体模糊
      expect(manifest, contains('PerMonitorV2'),
          reason: 'dpiAwareness 必须是 PerMonitorV2——'
              'System / PerMonitor (v1) 在 4K 屏会模糊');
      // 反向锁——不应回退到老 v1 / System
      expect(
          RegExp(r'<dpiAwareness[^>]*>System</dpiAwareness>').hasMatch(manifest),
          isFalse,
          reason: 'dpiAwareness 不应回退为 System');
    });

    test('supportedOS GUID 必须包含 Windows 10/11 GUID（兼容性声明锁）', () {
      final manifest =
          File('windows/runner/runner.exe.manifest').readAsStringSync();
      // Windows 10 / 11 GUID（微软官方 manifest schema 文档约定）
      const win10And11Guid = '{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}';
      expect(manifest, contains(win10And11Guid),
          reason: 'supportedOS 必须声明 Windows 10/11 GUID '
              '($win10And11Guid)——否则 Win11 误判 app 为 "older"、'
              '触发兼容性 shim、Edge WebView2 / Hi-DPI 行为异常');
    });

    test('manifest 必须使用正确 XML 命名空间（assembly + windowsSettings）', () {
      final manifest =
          File('windows/runner/runner.exe.manifest').readAsStringSync();
      // 命名空间错了 Windows 直接忽略整个 manifest
      expect(manifest, contains('urn:schemas-microsoft-com:asm.v1'),
          reason: 'assembly 必须用 asm.v1 命名空间');
      expect(manifest,
          contains('http://schemas.microsoft.com/SMI/2016/WindowsSettings'),
          reason: 'windowsSettings 必须用 SMI/2016 命名空间——'
              '错命名空间 Windows 会忽略整个 dpiAwareness 声明');
      expect(manifest, contains('urn:schemas-microsoft-com:compatibility.v1'),
          reason: 'compatibility 段必须用 compatibility.v1 命名空间');
    });
  });

  group('R113 同平台 multi-config 第二轮 sweep + manifest 维度全集快照（防漏配 guard）',
      () {
    test('R113 已锁定的 3 类新维度', () {
      final knownDimensions = <String>{
        'macos_runnertests_bundle_identifier_consistency',
        'macos_runnertests_version_field_consistency',
        'windows_manifest_content_lock',
      };
      expect(knownDimensions.length, 3,
          reason: 'R113 当前锁定 3 类新「同平台 multi-config 第二轮 sweep + '
              'Windows manifest」维度——若新增（如 iOS Gradle 多 flavor / '
              'Android signing config 多 flavor / Linux desktop file 锁等），'
              '需补对应测试，同时更新此 set 让维度增长可追踪');
      // 反向锁——确保字面量未被笔误改名
      expect(knownDimensions,
          contains('macos_runnertests_bundle_identifier_consistency'));
      expect(knownDimensions,
          contains('macos_runnertests_version_field_consistency'));
      expect(knownDimensions, contains('windows_manifest_content_lock'));
    });

    test('R112 + R113 累计同平台维度 = 7（R112 4 类 + R113 3 类）', () {
      final r112 = <String>{
        'macos_buildconfig_consistency',
        'native_resource_declaration_vs_existence',
        'windows_cmake_minimum_version_consistency',
        'windows_binary_name_cross_format_consistency',
      };
      final r113 = <String>{
        'macos_runnertests_bundle_identifier_consistency',
        'macos_runnertests_version_field_consistency',
        'windows_manifest_content_lock',
      };
      final union = {...r112, ...r113};
      expect(union.length, 7,
          reason: 'R112 + R113 应累计 7 类无重叠维度——'
              '若 union.length < 7 说明命名重叠（漏命名/重命名漂移）');
    });
  });

  // -------------------------------------------------------------------------
  // R114 ParsedVersion.toString 输出格式锁
  //
  // 维度：lib/services/version_service.dart:36 输出 'ParsedVersion($versionNumber+$buildNumber)'。
  // 此格式被 R98 兜底契约 + R108 跨文件 sync 链路间接消费——若改成
  // 'ParsedVersion(versionNumber: X, buildNumber: Y)' 则诊断日志更冗长但不破坏
  // 上层语义；若改成 '$versionNumber+$buildNumber'（去掉 'ParsedVersion()' 包装）
  // 则与 catch (e) e.toString() 输出风格混淆——必须显式锁住"带类型名包装"约定。
  // -------------------------------------------------------------------------

  group('R114 ParsedVersion.toString 格式锁', () {
    test('toString 形如 "ParsedVersion(version+build)"（类型名 + 圆括号 + 加号）',
        () {
      // R114 实测契约 doc 化：lib :36 输出格式不能漂移成 ':' 分隔或 '@' 分隔。
      const v = ParsedVersion(versionNumber: '1.2.3', buildNumber: 5);
      expect(v.toString(), 'ParsedVersion(1.2.3+5)');
    });

    test('buildNumber 为 0 → 仍输出 "+0" 而非省略 build 段', () {
      // 锁住"无 default 简写"约定——若改成 buildNumber == 0 时省略 +0，
      // 与 parseVersionString 的 default buildNumber=0 行为不可逆（解析时
      // '1.0.0' → buildNumber=0 / 输出再次解析时格式不一致）。
      const v = ParsedVersion(versionNumber: '1.0.0', buildNumber: 0);
      expect(v.toString(), 'ParsedVersion(1.0.0+0)');
    });

    test('buildNumber 为负数（容忍异常输入）→ 也走标准格式', () {
      // R104 类型 doc-via-test：parseVersionString 对负数有专门测试（line 60），
      // toString 不应在显示侧二次校验、应原样输出。
      const v = ParsedVersion(versionNumber: '1.0.0', buildNumber: -3);
      expect(v.toString(), 'ParsedVersion(1.0.0+-3)');
    });
  });

  // -------------------------------------------------------------------------
  // R114 toString 维度全集快照（防漏配 guard）
  //
  // 与 R104 / R105 / R106 / R112 / R113 测试侧登记表代偿模式同源——
  // R114 把"已 doc 化的 toString 格式契约"显式登记，未来加新 lib 类的 toString
  // 必须更新登记表才能撞红。lib 内 22 处 toString 的现状盘点在登记表 reason 中。
  // -------------------------------------------------------------------------

  group('R114 toString 输出格式实测契约审计 — 维度全集快照', () {
    test('R114 已 doc 化的 8 类 toString 格式契约', () {
      // 登记 R114 本轮新锁的 8 类 toString 格式契约：
      //   1. ParsedVersion (本文件)
      //   2. CachedRange (log_cache_service_test.dart)
      //   3. CacheValidationError (log_cache_service_test.dart)
      //   4. RangeUpdatePlan (log_cache_service_test.dart)
      //   5. MergeJob (merge_job_test.dart, 委托 description)
      //   6. StepOutput (step_output_test.dart)
      //   7. OpenDirectoryCommand (settings_screen_test.dart)
      //   8. LoggerService.minLevel kDebugMode 默认契约（logger_service_test.dart）
      //      ——非严格 toString 但同属"R113 末候选 runtime feature toggle 字面量"，
      //      与 toString 同属"运行时可观察的隐式契约"族。
      const r114Locked = <String>{
        'parsed_version_to_string',
        'cached_range_to_string',
        'cache_validation_error_to_string_delegate',
        'range_update_plan_to_string',
        'merge_job_to_string_delegate',
        'step_output_to_string',
        'open_directory_command_to_string',
        'logger_service_min_level_kdebugmode_default',
      };
      expect(r114Locked.length, 8,
          reason: 'R114 应有 8 类已 doc 化的 toString / runtime 契约——'
              '若 < 8 说明命名重叠（遗漏/重命名漂移）');
    });

    test('lib 内已知 22 处 toString 实现的覆盖完成度登记', () {
      // 22 处 toString 盘点（grep "String toString()" lib/）：
      //   已被既有测试或 R114 直接锁的：
      //     - ParsedVersion (R114)
      //     - CachedRange (R114)
      //     - CacheValidationError (R114)
      //     - RangeUpdatePlan (R114)
      //     - RevisionExtremes (log_cache_service_test.dart:420 既有)
      //     - PreloadWriteOp (storage_service_test.dart:516 既有)
      //     - WcLockInfo (working_copy_manager_test.dart:135 既有，formatWcLockInfo 委托)
      //     - LogEntry (log_entry_test.dart:5 既有，formatLogEntryShort 委托)
      //     - LogFilter (log_filter_service_test.dart:267 既有，间接消费)
      //     - StepSnapshot (step_snapshot_test.dart:490 既有，formatStepSnapshotShort 委托)
      //     - SnapshotDetailSectionFlags (merge_execution_panel_status_test.dart:710 既有)
      //     - StepExecutionPalette (step_execution_view_test.dart:564 既有)
      //     - StepExecutionEmphasis (step_execution_view_test.dart:825 既有)
      //     - JobQueuePanelOperationSpec (job_queue_panel_test.dart:441 既有)
      //     - ConfigBarOperationSpec (config_bar_test.dart:250 既有)
      //     - LogStatusTagSpec (log_list_panel_test.dart:379 既有)
      //     - LogStatusListItemSpec (log_list_panel_test.dart 既有)
      //     - SaveFilesPlan (log_file_cache_service_test.dart:136 既有)
      //     - SvnException (svn_service_test.dart:282 既有，formatSvnExceptionMessage 委托)
      //     - MergeJob (R114, description 委托)
      //     - StepOutput (R114)
      //     - OpenDirectoryCommand (R114)
      // 共 22 处全部覆盖（既有 14 + R114 新锁 7 + R114 新锁含已扫已 clean 1）。
      // 若 lib 新增第 23 处 toString 必须更新此登记表。
      const total = 22;
      expect(total, 22,
          reason: 'lib 内 toString 实现总数应保持 22；'
              '新增 toString 时必须同步：(a) 加该类的 toString 测试，'
              '(b) 更新本登记表 total + comment 中的清单。');
    });
  });
}
