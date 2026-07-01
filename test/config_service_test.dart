import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/app_config.dart';
import 'package:svn_auto_merge/services/config_service.dart';

void main() {
  group('formatConfigAssetsLoadFailedLine', () {
    test('正常情况：异常对象按 toString 拼接', () {
      // 锁定字面：'预置配置加载失败：' + error.toString()。
      final error = Exception('asset bundle missing');
      expect(
        formatConfigAssetsLoadFailedLine(error),
        '预置配置加载失败：Exception: asset bundle missing',
      );
    });

    test('与 formatConfigLoadFailedLine 在动词上刻意区分（assets 子流程 vs 整体兜底）', () {
      // 配对契约：两条 warn 日志在同一次失败时双重打出，前缀必须不同，
      // 不能因为"看着像"被合并成同一条渲染函数。
      final inner = formatConfigAssetsLoadFailedLine('boom');
      final outer = formatConfigLoadFailedLine('boom');
      expect(inner.startsWith('预置配置加载失败：'), isTrue);
      expect(outer.startsWith('加载配置文件失败：'), isTrue);
      expect(inner, isNot(equals(outer)));
    });

    test('错误对象为字符串：直接拼接，不加引号', () {
      // 不引用 String 的字面值——避免日志行突然多出引号干扰运维 grep。
      expect(formatConfigAssetsLoadFailedLine('plain'), '预置配置加载失败：plain');
    });

    test('错误为空字符串也直接拼接（暴露上游传空 bug）', () {
      // 故意非防御：让 '预置配置加载失败：' （冒号后空白）作为信号出现在日志，
      // 而不是被吞成"加载成功"的样子。
      expect(formatConfigAssetsLoadFailedLine(''), '预置配置加载失败：');
    });
  });

  group('formatConfigLoadedSummaryLine', () {
    test('正常情况：source + 数量', () {
      expect(
        formatConfigLoadedSummaryLine(source: '用户配置', sourceUrlCount: 3),
        '配置加载成功（用户配置）：3 个源 URL',
      );
    });

    test('source 是任意字符串都直接拼接（不校验枚举）', () {
      // 让"未来新增的来源名"零成本走这里，函数不充当字典守卫。
      expect(
        formatConfigLoadedSummaryLine(source: '远端拉取', sourceUrlCount: 0),
        '配置加载成功（远端拉取）：0 个源 URL',
      );
    });

    test('sourceUrlCount = 0 是合法状态（用户清空了配置）', () {
      // 不对 0 做"无源 URL"特殊文案——保持渲染纯字面拼接。
      final line = formatConfigLoadedSummaryLine(
        source: '预置配置',
        sourceUrlCount: 0,
      );
      expect(line.contains('：0 个源 URL'), isTrue);
    });

    test('sourceUrlCount 为负数原样透传（暴露上游 bug）', () {
      // List.length 永远 ≥ 0；传负数 = 上层假传，应该让 -1 显眼出现。
      expect(
        formatConfigLoadedSummaryLine(source: 'X', sourceUrlCount: -1),
        '配置加载成功（X）：-1 个源 URL',
      );
    });
  });

  group('formatConfigLoadFailedLine', () {
    test('正常情况：异常按 toString', () {
      expect(
        formatConfigLoadFailedLine(Exception('parse error')),
        '加载配置文件失败：Exception: parse error',
      );
    });

    test('错误对象为 null 也不抛 NPE，按字面 "null" 出现', () {
      // Dart 字符串插值会把 null 转成 'null'。这不是期望路径，但发生时
      // '加载配置文件失败：null' 比静默吞要好。
      // 注意：参数类型是 Object（非可空），调用 null 需要强转，这里只验证
      // toString 路径。
      expect(formatConfigLoadFailedLine('null'), '加载配置文件失败：null');
    });

    test('与 formatConfigLoadFromUserLine 字面无相互污染', () {
      // 两条都带"配置"二字，必须依然各自唯一可 grep。
      final loadFail = formatConfigLoadFailedLine('e');
      final loadOk = formatConfigLoadFromUserLine('/p');
      expect(loadFail.contains('失败'), isTrue);
      expect(loadOk.contains('失败'), isFalse);
    });
  });

  group('formatConfigLoadFromAssetsLine', () {
    test('字面常量', () {
      expect(formatConfigLoadFromAssetsLine(), '从预置配置加载（assets）');
    });

    test('括号是全角"（）"（与项目中文标点一致）', () {
      // 锁定全角，防止被随手改半角后影响日志检索。
      final line = formatConfigLoadFromAssetsLine();
      expect(line.contains('（'), isTrue);
      expect(line.contains('）'), isTrue);
      expect(line.contains('('), isFalse);
      expect(line.contains(')'), isFalse);
    });

    test('与 formatConfigLoadFromUserLine 形成"加载来源"枚举对', () {
      // 两条都以"从...加载"为模式，但字面不能完全相同。
      final assets = formatConfigLoadFromAssetsLine();
      final user = formatConfigLoadFromUserLine('/p');
      expect(assets.startsWith('从'), isTrue);
      expect(user.startsWith('从'), isTrue);
      expect(assets, isNot(equals(user)));
    });
  });

  group('formatConfigLoadFromUserLine', () {
    test('正常情况：路径原样拼接', () {
      expect(
        formatConfigLoadFromUserLine('/Users/foo/Library/Application Support/svn_auto_merge/config/source_urls.json'),
        '从用户配置加载：/Users/foo/Library/Application Support/svn_auto_merge/config/source_urls.json',
      );
    });

    test('空路径透传（"空"作为 bug 信号）', () {
      // 让上游"路径计算返回空字符串"的 bug 在日志里立即可见。
      expect(formatConfigLoadFromUserLine(''), '从用户配置加载：');
    });

    test('Windows 路径含反斜杠不做转义', () {
      expect(
        formatConfigLoadFromUserLine(r'C:\Users\foo\config.json'),
        r'从用户配置加载：C:\Users\foo\config.json',
      );
    });

    test('与 formatConfigSavedLine 共享路径但动词刻意拉开', () {
      // 读侧 "从用户配置加载：" / 写侧 "配置已保存到用户目录："，
      // 不能因为路径相同就被合并。
      const p = '/p';
      expect(formatConfigLoadFromUserLine(p), isNot(equals(formatConfigSavedLine(p))));
    });
  });

  group('formatConfigSavedLine', () {
    test('正常情况：路径原样拼接', () {
      expect(
        formatConfigSavedLine('/p/source_urls.json'),
        '配置已保存到用户目录：/p/source_urls.json',
      );
    });

    test('空路径透传', () {
      expect(formatConfigSavedLine(''), '配置已保存到用户目录：');
    });

    test('与读侧字面互斥（grep 时不会误中）', () {
      final saved = formatConfigSavedLine('/p');
      expect(saved.contains('已保存到'), isTrue);
      expect(saved.contains('从用户配置加载'), isFalse);
    });
  });

  group('formatConfigSourceUrlEntryLine', () {
    test('正常情况：两空格缩进 + "- name: url"', () {
      const url = SourceUrlConfig(name: '主干', url: 'svn://repo/trunk');
      expect(formatConfigSourceUrlEntryLine(url), '  - 主干: svn://repo/trunk');
    });

    test('开头必须是恰好两个空格的 "  - "（结构性缩进契约）', () {
      // 这是日志层次感的核心：列表项视觉挂在汇总行下方。
      // 任何"清理"这个前缀（去缩进、改成 tab、改成 4 空格）都会破坏排版。
      const url = SourceUrlConfig(name: 'n', url: 'u');
      final line = formatConfigSourceUrlEntryLine(url);
      expect(line.startsWith('  - '), isTrue);
      expect(line.startsWith('   - '), isFalse); // 不是 3 空格
      expect(line.startsWith('\t- '), isFalse); // 不是 tab
    });

    test('name 与 url 之间用 ": "（半角冒号 + 空格）分隔', () {
      // 与中文全角"："不同——这里是英文"key: value"风格，与 URL 的英文上下文匹配。
      const url = SourceUrlConfig(name: 'a', url: 'b');
      final line = formatConfigSourceUrlEntryLine(url);
      expect(line.endsWith(': b'), isTrue);
      expect(line.contains('：'), isFalse); // 没有全角冒号
    });

    test('name 含换行不做转义（让格式错误的配置被运维直观看见）', () {
      // 多行输出 → 配置文件被人手动编辑成错误格式的信号。
      const url = SourceUrlConfig(name: 'a\nb', url: 'u');
      expect(formatConfigSourceUrlEntryLine(url), '  - a\nb: u');
    });

    test('description 与 enabled 字段不参与渲染（只用 name + url）', () {
      // 列表项契约：只展示 name 与 url；description / enabled 状态不属于
      // "加载摘要"层级——加载成功能列出来本身就意味着 enabled=true。
      const a = SourceUrlConfig(name: 'n', url: 'u', description: 'desc-A');
      const b = SourceUrlConfig(name: 'n', url: 'u', description: 'desc-B');
      expect(
        formatConfigSourceUrlEntryLine(a),
        formatConfigSourceUrlEntryLine(b),
      );
    });
  });

  group('配置文件 JSON schema 持久化（R105）', () {
    // R105：JSON file format 持久化兼容审计——锁定配置文件（user_config.json）
    // 的顶层 schema 字段名与序列化格式。背景：原 loadConfig / saveConfig 直接
    // inline JSON 处理（`jsonDecode(...) as Map<String, dynamic>` 后调
    // `AppConfig.fromJson`），任何对顶层结构的误改都会让磁盘上已有的用户配置
    // 在下次启动时无法解析、回退到 defaultConfig（用户的自定义 sourceUrls 全部消失）。
    //
    // 与队列文件（R105 sibling）的对偶：
    // - 队列文件损坏 → 强制全空 + 用户重建（recovery 不安全）
    // - 配置文件损坏 → 走 defaultConfig 兜底（recovery 安全，仅丢自定义 URL）
    // 两类文件的容错策略对偶，本 group 在 doc 文案里互相引用。

    AppConfig makeConfig() => AppConfig.defaultConfig();

    group('serializeAppConfigJson 输出格式', () {
      test("顶层固定为 'source_urls' + 'settings' 两字段对象", () {
        final content = serializeAppConfigJson(makeConfig());
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded.keys.toSet(), {'source_urls', 'settings', 'version'},
            reason: 'AppConfig 顶层 schema 必须与 @JsonKey 声明一致；'
                '新增字段需同步更新此清单 + 加 fromJson default 路径测试');
      });

      test('使用 2 空格缩进（与队列文件视觉风格统一）', () {
        final content = serializeAppConfigJson(makeConfig());
        final lines = content.split('\n');
        expect(lines.length, greaterThan(1),
            reason: 'JsonEncoder.withIndent 输出必带换行');
        // 第二行必须以 2 空格起头（任意顶层字段）
        expect(lines[1].startsWith('  "'), isTrue,
            reason: '缩进格式：与 serializeQueueJson 保持一致（"  "）；'
                '改成无缩进会让两个文件风格分裂');
      });
    });

    group('parseAppConfigJson 解析契约', () {
      test('round-trip：default config → 等价 AppConfig', () {
        final original = makeConfig();
        final content = serializeAppConfigJson(original);
        final parsed = parseAppConfigJson(content);
        // AppConfig 没有 operator ==，逐字段比较（R101 lib 实测契约 doc 化原则）
        expect(parsed.version, original.version);
        expect(parsed.sourceUrls.length, original.sourceUrls.length);
        expect(parsed.sourceUrls[0].name, original.sourceUrls[0].name);
        expect(parsed.sourceUrls[0].url, original.sourceUrls[0].url);
        expect(parsed.sourceUrls[0].enabled, original.sourceUrls[0].enabled);
      });

      test('round-trip：自定义 sourceUrls 多条', () {
        const customConfig = AppConfig(
          version: '2.0.0',
          sourceUrls: [
            SourceUrlConfig(name: 'a', url: 'svn://a', enabled: true),
            SourceUrlConfig(name: 'b', url: 'svn://b', enabled: false),
            SourceUrlConfig(name: 'c', url: 'svn://c', enabled: true),
          ],
          settings: AppSettings(),
        );
        final content = serializeAppConfigJson(customConfig);
        final parsed = parseAppConfigJson(content);
        expect(parsed.sourceUrls.length, 3);
        expect(parsed.sourceUrls.map((s) => s.name).toList(), ['a', 'b', 'c'],
            reason: 'sourceUrls 顺序必须保留——UI 列表展示顺序就是用户配置顺序');
        expect(parsed.sourceUrls.map((s) => s.enabled).toList(),
            [true, false, true]);
      });

      test('异常：非 JSON 字符串 → 抛 FormatException', () {
        expect(() => parseAppConfigJson('not-json'),
            throwsA(isA<FormatException>()),
            reason: 'jsonDecode 失败抛 FormatException；'
                'loadConfig 用 try/catch 吞掉、回退 AppConfig.defaultConfig()');
      });

      test('异常：顶层非 Map（裸数组）→ 抛 TypeError', () {
        expect(() => parseAppConfigJson('[]'), throwsA(isA<TypeError>()),
            reason: '顶层必须是对象 {...}；裸数组会让 as Map<String, dynamic> 强转失败');
      });

      test("异常：缺 'source_urls' 字段 → 抛 TypeError", () {
        expect(() => parseAppConfigJson('{"settings":{},"version":"1.0.0"}'),
            throwsA(isA<TypeError>()),
            reason: "AppConfig.fromJson 中 json['source_urls'] as List 强转抛 TypeError——"
                'loadConfig 走 catch 回退 defaultConfig');
      });

      test("异常：缺 'settings' 字段 → 抛 TypeError", () {
        expect(
            () => parseAppConfigJson(
                '{"source_urls":[],"version":"1.0.0"}'),
            throwsA(isA<TypeError>()),
            reason: "AppConfig.fromJson 中 json['settings'] as Map 强转抛 TypeError");
      });
    });

    group('config 文件 JSON 字段名字面量锁定', () {
      test("'source_urls' 字面量锁定（snake_case 不要改成 camelCase）", () {
        final content = serializeAppConfigJson(makeConfig());
        expect(content.contains('"source_urls"'), isTrue,
            reason: "'source_urls' 是 @JsonKey 声明的磁盘字段名（snake_case）；"
                "与 lib 内 Dart 字段 sourceUrls（camelCase）刻意拉开。"
                '改 @JsonKey(name:) 必须配合迁移路径（读旧 key + 删旧 key + 写新 key）——'
                '参考 R104 preload_settings 旧 key 清理模式');
        // 反向锁：误改成 camelCase 必撞红
        expect(content.contains('"sourceUrls"'), isFalse,
            reason: "反向锁：JSON 不应出现 Dart 字段名 sourceUrls——@JsonKey 必须生效");
      });

      test("'settings' 字面量锁定", () {
        final content = serializeAppConfigJson(makeConfig());
        expect(content.contains('"settings"'), isTrue,
            reason: "'settings' 是 AppConfig 顶层 settings 字段的 JSON key");
      });

      test('已知 JSON schema 字段全集快照', () {
        // R104 在 prefs 维度建立"已知 key 全集"代偿登记表；R105 在 file
        // schema 维度做同样的事——锁定 AppConfig 顶层字段集合，新增字段必撞红
        // 并提示同步更新 fromJson default 路径（R101 模式）。
        const knownTopLevelKeys = {'source_urls', 'settings', 'version'};
        final content = serializeAppConfigJson(makeConfig());
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded.keys.toSet(), knownTopLevelKeys,
            reason: 'AppConfig 顶层 schema 必须与已知字段集合完全一致；'
                '新增字段需：(1) 更新此清单；(2) 给 @JsonKey(defaultValue:) 加 hydrate 测试；'
                '(3) 考虑旧配置文件无该字段时的兼容路径');
      });
    });
  });

  // R107 — shipped asset 配置文件 schema 锁定
  //
  // 维度族：R104 KV store 协议 / R105 文件 schema（用户运行时文件） /
  // R106 进程 argv → R107 **shipped artifact**（assets/ 目录下随包发布的配置文件）。
  //
  // R105 锁的是用户运行时写出的 `~/.config/.../config.json` schema；R107 锁的是
  // 仓库内 `assets/config/source_urls.json`——前者用户可编辑、错了走 defaultConfig
  // 兜底；后者**随包发布**、错了用户首次启动直接落到 defaultConfig 而看不到任何
  // 预置示例（"shipped asset"的 silent regression 比用户文件更隐蔽：CI 不会撞红、
  // pubspec 也不会报错——asset 文件本身不在测试覆盖里时，编辑者无任何反馈）。
  //
  // 防御目标 4 条：
  //  (1) 仓库内 asset 文件**实际可被 parseAppConfigJson 解析**——任何字段名漂移
  //      （`source_urls` → `sourceUrls` / `enabled` → `is_enabled`）撞红；
  //  (2) pubspec.yaml 把 asset 列入 flutter.assets——漏列会让 rootBundle 在生产
  //      抛 FlutterError，CI 不撞；
  //  (3) asset 顶层字段集合 = R105 已知集合 + 仅人类可读字段（`description`）；
  //      防御未来有人在 asset 加新字段但忘记加 @JsonKey；
  //  (4) asset 例子 entry 的字段集合 = SourceUrlConfig 期望字段集合（`name`/
  //      `url`/`description`/`enabled`）——例子缺字段会被 fromJson 用 default
  //      静默兜过去（`description=''`/`enabled=true`），用户永远看不到 bug。
  //
  // 实现要点：测试侧不走 `rootBundle.loadString`（需要 Flutter binding），改为
  // 直接 `File('assets/config/source_urls.json')` 从仓库根读——`flutter test` 的
  // 工作目录就是项目根。这是 R104 logger.enabled=false 之后的第二条 service 单测
  // 环境前置共识。
  group('shipped asset assets/config/source_urls.json schema 锁定（R107）', () {
    // assets 文件路径——固定字面量，pubspec.yaml:66 也写死同一路径，
    // 任何一侧改动都会撞红另一侧（双向锁定）。
    const assetPath = 'assets/config/source_urls.json';

    Map<String, dynamic> readAssetJson() {
      final file = File(assetPath);
      expect(file.existsSync(), isTrue,
          reason: 'shipped asset 必须存在于仓库根；删除或改名会让 rootBundle 抛 FlutterError、'
              '生产环境用户首次启动失去预置示例（静默回退 defaultConfig）');
      final content = file.readAsStringSync();
      return jsonDecode(content) as Map<String, dynamic>;
    }

    test('asset 文件实际可被 parseAppConfigJson 解析（端到端 happy path）', () {
      // R107 主防御：把 lib parser 与 asset 文件 schema 直接绑定——任何字段名
      // 漂移（如 enabled → is_enabled / source_urls → sourceUrls）撞红。
      final content = File(assetPath).readAsStringSync();
      expect(() => parseAppConfigJson(content), returnsNormally,
          reason: 'shipped asset 必须能被生产 parser 直接解析——'
              '若 asset 改了字段名而未同步 @JsonKey，此处撞红是唯一防线');
      final config = parseAppConfigJson(content);
      expect(config.sourceUrls, isNotEmpty,
          reason: 'asset 必须包含至少 1 个示例 sourceUrl 条目；'
              '空 list 会让首次启动用户看不到任何预置项、UX 退化');
      expect(config.version, isNotEmpty,
          reason: 'asset version 字段必须非空；defaultConfig 同样设为 "1.0.0"，'
              '便于运维诊断"用户用的是 default 还是 shipped asset"');
    });

    test('pubspec.yaml 把 asset 列入 flutter.assets（漏列会让 rootBundle 抛 FlutterError）', () {
      // R107 关键防御：asset 文件存在于磁盘但漏列 pubspec 时，rootBundle.loadString
      // 抛 FlutterError；config_service.dart:200 catch 后走 defaultConfig——CI/单测
      // 完全不撞红。本测试是唯一防线。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains(assetPath), isTrue,
          reason: 'pubspec.yaml 必须列入 $assetPath；'
              '漏列时 rootBundle 抛 FlutterError、loadConfig 静默走 defaultConfig，'
              'CI 不撞红——本测试是唯一防御');
    });

    test('asset 顶层字段 ⊇ R105 已知 schema 集合（缺任一字段 parser 直接 fail）', () {
      // R105 锁的是 serializer 输出的 3 字段；R107 反向锁——asset 输入端必须
      // 含同样 3 字段（缺 source_urls 或 settings 会被 fromJson 强转抛 TypeError）。
      const requiredKeys = {'source_urls', 'settings', 'version'};
      final keys = readAssetJson().keys.toSet();
      for (final k in requiredKeys) {
        expect(keys, contains(k),
            reason: 'asset 顶层缺 "$k" 会让 parseAppConfigJson 抛 TypeError、'
                'loadConfig 静默走 defaultConfig——必须保留');
      }
    });

    test('asset 顶层字段 ⊆ 已知 schema ∪ 仅人类可读字段（防御未来加无 @JsonKey 的新字段）', () {
      // 反向防御：asset 加新字段时，要么是 lib 端有对应 @JsonKey 的字段（进入
      // R105 knownTopLevelKeys），要么是仅人类可读注释字段（如 'description'，
      // json_serializable 默认会忽略未知字段——不会报错但也不会被消费）。
      // 本测试的 known set 覆盖前者；human-only set 覆盖后者，两者并集为白名单。
      const parserKnownKeys = {'source_urls', 'settings', 'version'};
      const humanOnlyKeys = {'description'};
      final allowedKeys = parserKnownKeys.union(humanOnlyKeys);
      final actualKeys = readAssetJson().keys.toSet();
      expect(actualKeys.difference(allowedKeys), isEmpty,
          reason: 'asset 出现未登记字段：${actualKeys.difference(allowedKeys)}；'
              '若 lib 端已加 @JsonKey 请把该 key 加入 parserKnownKeys（同步更新 R105 测试）；'
              '若是注释/元数据请加入 humanOnlyKeys 并 doc 化用途');
    });

    test('asset 中 sourceUrl entry 的字段 = SourceUrlConfig 期望集合（防默认值静默兜底）', () {
      // R107 隐蔽风险：SourceUrlConfig 给 description / enabled 设了默认值
      // （description='' / enabled=true）——asset 例子若漏写 enabled 字段，
      // fromJson 静默用 true 兜底；用户首次启动看到的是"已启用"的示例配置，
      // 与 asset 设计意图（enabled=false 让用户主动启用）相反。
      const expectedFields = {'name', 'url', 'description', 'enabled'};
      final json = readAssetJson();
      final urls = json['source_urls'] as List;
      expect(urls, isNotEmpty);
      for (var i = 0; i < urls.length; i++) {
        final entry = urls[i] as Map<String, dynamic>;
        final entryKeys = entry.keys.toSet();
        expect(entryKeys, expectedFields,
            reason: 'sourceUrls[$i] 字段集合必须 == SourceUrlConfig 全字段；'
                '缺字段会被 @JsonKey default 静默兜底（如 enabled 缺省 → true，'
                '与 asset 设计的"用户主动启用"意图相反——本测试在 asset 端锁定显式声明）');
      }
    });

    test('asset settings 块包含 R105 AppSettings 的 2 个字段（svn_log_limit / log_page_size）', () {
      // 同上隐蔽风险：AppSettings 两字段都有默认值（200 / 50），asset 漏写时
      // fromJson 静默兜底——用户拿到的"预置配置"实际等同 defaultConfig，与
      // asset 显式声明 svn_log_limit=200 的意图无差异、但 doc 信号丢失。
      const requiredSettingsKeys = {'svn_log_limit', 'log_page_size'};
      final settings = readAssetJson()['settings'] as Map<String, dynamic>;
      expect(settings.keys.toSet(), requiredSettingsKeys,
          reason: 'asset settings 必须显式声明 ${requiredSettingsKeys.toList()..sort()}；'
              '漏字段会被 @JsonKey default 静默兜底，让"预置配置"退化为 defaultConfig 而无诊断信号');
    });

    test('asset 解析后的 sourceUrl entry 默认应 enabled=false（"用户主动启用"约定）', () {
      // R107 与 R105 的语义对偶 doc：用户文件（R105）默认所有 entry enabled=true
      // 是用户的真实配置；shipped asset（R107）作为示例 placeholder 必须默认
      // enabled=false——避免用户首次启动看到一堆 example.com 假地址被误用。
      // 此约定在 asset 文件 line 9 显式声明 `"enabled": false`，本测试锁住该决策。
      final config = parseAppConfigJson(File(assetPath).readAsStringSync());
      for (var i = 0; i < config.sourceUrls.length; i++) {
        final entry = config.sourceUrls[i];
        expect(entry.enabled, isFalse,
            reason: 'shipped asset 的 sourceUrls[$i] (name=${entry.name}) '
                '必须默认 enabled=false——asset 是 placeholder 示例，'
                '若默认 enabled=true 会让 main_screen_v3 把假 URL 当真实配置使用');
      }
    });
  });

  // R109 — R98 反对称 throw 兜底自洽测试补完（AppConfig.defaultConfig 兜底契约）
  //
  // R108 把 R98 反对称 throw 决策的"正面契约"形式化为"兜底字面量自洽性测试"
  // 模式（version_service 的 `'1.0.0+1'` → 必须能被 parseVersionString 正确分段
  // + 满足 isVersionAtLeast 自比较）。R109 把同一模式扩展到结构化对象兜底——
  // config_service.dart:202 的 R98 标注，兜底物是 `AppConfig.defaultConfig()`
  // factory 而非字面量 String。比 R108 多一层抽象：兜底对象必须**整体满足**所有
  // 已锁的下游契约（R105 序列化 schema / R107 sourceUrl 字段 / R108 version 格式 /
  // R107 enabled=false 约定 / 启用过滤链路）。
  //
  // 风险：未来有人改 defaultConfig（如加新 sourceUrl 示例 / 改 version 格式 /
  // 改 enabled 默认）但漏更新对应 schema 锁/下游消费——
  //  - 改 enabled=true：用户首次启动会让 main_screen 用假 URL `your-svn-server.com`
  //    发起真实 SVN 请求 → 报错并污染日志；
  //  - 改 version='1.0' 或 'unknown'：getVersion 链路读不到 pubspec 时该兜底也不
  //    生效；
  //  - 改 settings 字段：R105 已锁 settings schema，但 defaultConfig 可能用了过期
  //    构造路径（const AppSettings() 默认值变化时撞红）。
  //
  // R109 就是把 defaultConfig 与下游所有锁绑定起来——R98 已锁"throw 不测"的负面
  // 契约，R108/R109 补"兜底值与 consumer 自洽"的正面契约。
  //
  // R98 反对称 throw 标注覆盖完成度：lib/ 内 4 处标注——
  //  (a) version_service.dart:160 兜底 `'1.0.0+1'`（R108 已覆盖）；
  //  (b) version_service.dart:175 兜底 `'1.0.0+1'`（同 a，R108 一并覆盖）；
  //  (c) config_service.dart:202 兜底 `AppConfig.defaultConfig()`（**R109 本轮覆盖**）；
  //  (d) log_cache_service.dart:918 兜底 `0` / 空集等（需 sqlite mock，scope 外延后）。
  // R109 完成 (c) 之后，R98 反对称模式仅剩 (d) 待覆盖。
  group('AppConfig.defaultConfig 兜底契约自洽（R109）', () {
    // 取 default 一次复用——避免每个 test 都构造（factory 是 const，复用安全）。
    final defaultCfg = AppConfig.defaultConfig();

    test('字段直接断言（锁定 default 的 immutable 内容）', () {
      // 锁住每个字段的字面量值，避免有人无意改动（如把 version 升到 '1.1.0'，
      // 让 R108 的 isVersionAtLeast 锚点漂移；或加第二个 sourceUrl 让
      // enabledSourceUrls 长度变化）。R109 是"产品级 default 是契约"的明确声明。
      expect(defaultCfg.version, '1.0.0',
          reason: 'default version 字面量是 R98 兜底契约的一部分；'
              '改动需评估对 isVersionAtLeast 锚点的影响（R108 已锁 1.0.0+1 自比较，'
              '若 default 改成 1.1.0 而 pubspec 兜底仍是 1.0.0+1，'
              '运维诊断"用的是 default 还是兜底版本"会模糊）');
      expect(defaultCfg.sourceUrls.length, 1,
          reason: 'default 必须只有 1 个 placeholder sourceUrl——多个会让用户'
              '首次启动看到多个无效示例，UX 退化；零个会让 sourceUrls 字段类型'
              '退化为空 list（R105 已锁 source_urls 必须是 List 但允许空）');
    });

    test('唯一 placeholder sourceUrl 字段对齐 R107 SourceUrlConfig schema', () {
      // R107 已锁 shipped asset sourceUrl entry 字段集合 = {name, url, description, enabled}。
      // R109 把 default sourceUrl 也纳入同一集合（factory 构造路径 vs json 反序列化
      // 路径必须产生**字段同构**对象——任一路径改动都要同步另一路径）。
      final entry = defaultCfg.sourceUrls.first;
      expect(entry.name, isNotEmpty,
          reason: 'name 必须非空——空 name 会在 displayText 渲染中产生空白行 UI bug');
      expect(entry.url, isNotEmpty);
      expect(entry.description, isNotEmpty,
          reason: 'description 应非空——R107 已锁 SourceUrlConfig.description '
              '默认空串，但 default factory 显式提供"提示用户修改"文案是 UX 约定，'
              '改成空串会让 placeholder 无操作引导');
    });

    test('placeholder sourceUrl 必须 enabled=false（与 R107 shipped asset 同向）', () {
      // R107 锁了 shipped asset 默认 enabled=false（避免假 URL 被 main_screen
      // 当真实配置使用）。R109 锁 default factory 同样的约定——两者都是
      // "placeholder 占位"语义，必须同向，不能因为是 factory 路径就走相反默认。
      // 这是"用户文件 enabled=true 是真实配置 / shipped 来源 enabled=false 是
      // placeholder"的语义对偶在 default factory 维度的延续。
      final entry = defaultCfg.sourceUrls.first;
      expect(entry.enabled, isFalse,
          reason: 'default factory 的 placeholder URL（${entry.url}）必须默认 '
              'enabled=false——若改为 true 会让 main_screen_v3 把假 URL 当真实'
              '配置发起 SVN 请求、产生用户混淆的报错。R107 已锁 shipped asset 端，'
              'R109 锁 default factory 端，两条路径行为对齐');
    });

    test('default.enabledSourceUrls 返回空 list（filter 链路自洽）', () {
      // 端到端联动：default 唯一条目 enabled=false → enabledSourceUrls
      // （filterEnabledSourceUrls 包装）必须返回空 list。锁住"default 兜底场景下
      // main_screen 拿不到任何 usable URL"这个 UX 决策——确保 UI 显式提示用户
      // 配置而不是用假 URL 报错。
      expect(defaultCfg.enabledSourceUrls, isEmpty,
          reason: 'default 兜底场景下 enabledSourceUrls 必须空——filter 链路与 '
              'default 决策必须自洽：placeholder 设 enabled=false 后过滤结果应为空；'
              '若链路 bug 让空集变成全集（R105 已锁"全 disabled 不回退到全列表"），'
              '本测试是端到端防线');
    });

    test('default.version 满足 R108 已锁的版本格式约束（x.y.z[+build] + 全数字段）', () {
      // R108 已锁 pubspec.yaml.version 必须 x.y.z + 全数字段，让 isVersionAtLeast
      // 解析不退化。R109 给 default factory 的 version 加同一约束——确保即使
      // pubspec 加载链路与 config 加载链路同时降级（极端情况），运维场景仍能
      // 用 isVersionAtLeast(defaultCfg.version, X) 做合规判断。
      final segments = defaultCfg.version.split('+').first.split('.');
      expect(segments.length, 3,
          reason: 'default.version 必须是 x.y.z 三段——与 R108 pubspec 端约束同向，'
              '让所有兜底路径上的 version 字符串都能被 isVersionAtLeast 正常处理');
      for (final s in segments) {
        expect(int.tryParse(s), isNotNull,
            reason: 'default.version 段必须全数字：$s 非数字会让 isVersionAtLeast 解析失败');
      }
    });

    test('default 完整 round-trip（serialize → parse → equality）', () {
      // R105 已锁 serializeAppConfigJson + parseAppConfigJson 配对——R109 加端到端
      // round-trip：default → 序列化 → 反序列化 → 字段全等。锁住"default factory
      // 路径 vs json 路径产生同构对象"——若有人在 SourceUrlConfig 加新字段但忘改
      // factory，本测试通过 round-trip 自洽撞红。
      final json = serializeAppConfigJson(defaultCfg);
      final reparsed = parseAppConfigJson(json);
      expect(reparsed.version, defaultCfg.version);
      expect(reparsed.sourceUrls.length, defaultCfg.sourceUrls.length);
      final origUrl = defaultCfg.sourceUrls.first;
      final reUrl = reparsed.sourceUrls.first;
      expect(reUrl.name, origUrl.name);
      expect(reUrl.url, origUrl.url);
      expect(reUrl.description, origUrl.description);
      expect(reUrl.enabled, origUrl.enabled);
      expect(reparsed.settings.svnLogLimit, defaultCfg.settings.svnLogLimit);
      expect(reparsed.settings.logPageSize, defaultCfg.settings.logPageSize);
    });

    test('default 序列化输出顶层字段集合 == R105 已知 schema', () {
      // R105 已锁"序列化输出顶层字段集合 = {source_urls, settings, version}"——
      // R109 校验 default factory 走完 serializer 输出**仍然落在同一集合**。
      // 这是"factory 不引入 lib parser 不认识的额外顶层字段"的 guard——若有人
      // 在 AppConfig 加字段但只更新 factory 不更新 serializer/JsonKey，本测试撞红。
      const knownTopLevelKeys = {'source_urls', 'settings', 'version'};
      final json = serializeAppConfigJson(defaultCfg);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), knownTopLevelKeys,
          reason: 'default factory 序列化结果必须落在 R105 已知顶层字段集合内——'
              'factory 路径不能引入 parser 不认识的字段，否则下次 loadConfig 反向'
              '解析会因 @JsonKey 漂移而走 catch 兜底（无限递归至 default）');
    });

    test('default.sourceUrls.first.url 是显式 placeholder 域名（不指向真实 SVN 服务）', () {
      // 反向锁：placeholder URL 必须含 `your-svn-server.com` / `example.com` 等
      // 显式占位域名，不能误填成真实可达的 SVN 地址（如 svn.apache.org）——
      // 后者会让用户首次启动若误启用就直接命中陌生服务，安全/隐私事故。
      // 锁定"占位 URL 视觉上必须明显是假"的 UX 设计原则。
      final url = defaultCfg.sourceUrls.first.url.toLowerCase();
      final isObviousPlaceholder = url.contains('your-svn-server') ||
          url.contains('example.com') ||
          url.contains('placeholder') ||
          url.contains('your-server') ||
          url.contains('localhost');
      expect(isObviousPlaceholder, isTrue,
          reason: 'default placeholder URL ($url) 必须包含明显的占位标识'
              '（your-svn-server / example.com / placeholder / localhost）；'
              '若改成真实可达域名，用户误启用会发起对陌生服务的请求、'
              '产生安全/隐私问题');
    });
  });
}
