import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/app_config.dart';

void main() {
  group('merge validation script path config', () {
    test('默认路径固定为目标工作副本下 Tools/check.py', () {
      expect(kDefaultMergeValidationScriptPath, 'Tools/check.py');
    });

    test('路径归一化：空白回落默认值，反斜杠转 /', () {
      expect(
        normalizeMergeValidationScriptPath(null),
        kDefaultMergeValidationScriptPath,
      );
      expect(
        normalizeMergeValidationScriptPath('   '),
        kDefaultMergeValidationScriptPath,
      );
      expect(
        normalizeMergeValidationScriptPath(r' Tools\check.py '),
        'Tools/check.py',
      );
    });

    test('只接受相对路径', () {
      expect(isRelativeMergeValidationScriptPath('Tools/check.py'), isTrue);
      expect(isRelativeMergeValidationScriptPath('/Tools/check.py'), isFalse);
      expect(
          isRelativeMergeValidationScriptPath(r'C:\Tools\check.py'), isFalse);
    });
  });

  group('filterEnabledSourceUrls', () {
    test('正常情况：只保留 enabled == true', () {
      const urls = [
        SourceUrlConfig(name: 'A', url: 'a', enabled: true),
        SourceUrlConfig(name: 'B', url: 'b', enabled: false),
        SourceUrlConfig(name: 'C', url: 'c', enabled: true),
      ];
      final result = filterEnabledSourceUrls(urls);
      expect(result.length, 2);
      expect(result[0].name, 'A');
      expect(result[1].name, 'C');
    });

    test('保持入参顺序（UI 下拉框依赖）', () {
      // 用户配置 [A, B, C]，禁用 B → 期望 [A, C] 而非 [C, A]。
      const urls = [
        SourceUrlConfig(name: 'A', url: 'a', enabled: true),
        SourceUrlConfig(name: 'B', url: 'b', enabled: false),
        SourceUrlConfig(name: 'C', url: 'c', enabled: true),
        SourceUrlConfig(name: 'D', url: 'd', enabled: true),
      ];
      final result = filterEnabledSourceUrls(urls);
      expect(result.map((u) => u.name).toList(), ['A', 'C', 'D']);
    });

    test('空列表 → 空列表', () {
      expect(filterEnabledSourceUrls(const []), <SourceUrlConfig>[]);
    });

    test('全部 disabled → 空列表（不回退到全列表）', () {
      // "全禁用 = 用户明确不要任何 URL"——静默回退会违背用户意图。
      const urls = [
        SourceUrlConfig(name: 'A', url: 'a', enabled: false),
        SourceUrlConfig(name: 'B', url: 'b', enabled: false),
      ];
      expect(filterEnabledSourceUrls(urls), <SourceUrlConfig>[]);
    });

    test('全部 enabled → 全列表（按顺序）', () {
      const urls = [
        SourceUrlConfig(name: 'A', url: 'a', enabled: true),
        SourceUrlConfig(name: 'B', url: 'b', enabled: true),
      ];
      final result = filterEnabledSourceUrls(urls);
      expect(result.length, 2);
      expect(result[0].name, 'A');
      expect(result[1].name, 'B');
    });

    test('返回新列表（不影响入参）', () {
      // 调用方拿到的列表可以独立修改而不污染原配置。
      const urls = [
        SourceUrlConfig(name: 'A', url: 'a', enabled: true),
      ];
      final result = filterEnabledSourceUrls(urls);
      result.add(const SourceUrlConfig(name: 'X', url: 'x'));
      expect(urls.length, 1);
      expect(urls[0].name, 'A');
    });

    test('不去重：相同 url 的两个 enabled 项全部保留', () {
      // 上游配置 bug 信号——应当显眼出现而非被静默合并。
      const urls = [
        SourceUrlConfig(name: 'A', url: 'same', enabled: true),
        SourceUrlConfig(name: 'B', url: 'same', enabled: true),
      ];
      final result = filterEnabledSourceUrls(urls);
      expect(result.length, 2);
    });

    test('AppConfig.enabledSourceUrls 与 filterEnabledSourceUrls 输出等价', () {
      const config = AppConfig(
        version: '1.0.0',
        sourceUrls: [
          SourceUrlConfig(name: 'A', url: 'a', enabled: true),
          SourceUrlConfig(name: 'B', url: 'b', enabled: false),
        ],
        settings: AppSettings(),
      );
      expect(
        config.enabledSourceUrls.map((u) => u.name).toList(),
        filterEnabledSourceUrls(config.sourceUrls).map((u) => u.name).toList(),
      );
    });
  });

  group('formatSourceUrlDisplayText', () {
    test('正常情况：name + " - " + url', () {
      expect(
        formatSourceUrlDisplayText(name: '主干', url: 'https://svn/repo/trunk'),
        '主干 - https://svn/repo/trunk',
      );
    });

    test('分隔符是半角空格 + 半角连字符 + 半角空格', () {
      // 与中文全角"——"或全角空格刻意区分——UI 下拉框字符宽度敏感。
      final line = formatSourceUrlDisplayText(name: 'a', url: 'b');
      expect(line.contains(' - '), isTrue);
      expect(line.contains('——'), isFalse);
      expect(line.contains('　'), isFalse); // 全角空格
    });

    test('与 formatJobDescription / formatLogEntryShort 风格刻意不同（不含 " | "）', () {
      // 那两个用于 4-5 段日志生态的分段查询；这里只有 2 段简单展示，用 ' - ' 更符合 UI 直觉。
      final line = formatSourceUrlDisplayText(name: 'a', url: 'b');
      expect(line.contains(' | '), isFalse);
    });

    test('空 name → " - \$url"（前导 " - " 作为 bug 信号）', () {
      expect(
        formatSourceUrlDisplayText(name: '', url: 'https://x'),
        ' - https://x',
      );
    });

    test('空 url → "\$name - "（末尾 " - " 作为 bug 信号）', () {
      expect(formatSourceUrlDisplayText(name: 'A', url: ''), 'A - ');
    });

    test('不对 url 做 trim 或规范化（渲染函数职责单一）', () {
      // URL 规范化由上游 SourceUrlConfig 构造时负责。
      expect(
        formatSourceUrlDisplayText(name: 'A', url: '  /spaced/  '),
        'A -   /spaced/  ',
      );
    });

    test('SourceUrlConfig.displayText 与 formatSourceUrlDisplayText 输出等价', () {
      const config = SourceUrlConfig(name: 'A', url: 'https://x');
      expect(
        config.displayText,
        formatSourceUrlDisplayText(name: 'A', url: 'https://x'),
      );
    });
  });

  group('kDefaultLogPageSize 与 AppSettings 一致性', () {
    test('常量值锁定为 50', () {
      // 锁定数值——任何修改都需要单测同步更新，引发 review 注意。
      expect(kDefaultLogPageSize, 50);
    });

    test('AppSettings 默认构造器的 logPageSize == kDefaultLogPageSize（防漂移）', () {
      // 这条是核心契约：AppSettings 构造器字面量与 caller-side 兜底必须一致。
      // 单测确保有人单独改一处时被发现。
      expect(const AppSettings().logPageSize, kDefaultLogPageSize);
    });

    test('JSON 反序列化无 log_page_size 字段时使用同一默认值', () {
      // 第二条防漂移：app_config.g.dart 的 ?? 50 是 generator 从构造器默认值反向
      // 推导的，这条单测确保两条路径殊途同归。
      final settings = AppSettings.fromJson(<String, dynamic>{});
      expect(settings.logPageSize, kDefaultLogPageSize);
    });
  });

  group('kDefaultMaxRetries 与 caller 一致性', () {
    test('常量值锁定为 5', () {
      // 之前没有显式锁定该值，本轮顺手补齐。
      expect(kDefaultMaxRetries, 5);
    });
  });

  group('kDefaultSvnLogLimit 与 AppSettings 一致性', () {
    test('常量值锁定为 200', () {
      expect(kDefaultSvnLogLimit, 200);
    });

    test('AppSettings 默认构造器的 svnLogLimit == kDefaultSvnLogLimit（防漂移）', () {
      // 同 logPageSize：构造器默认与常量必须永远一致。
      expect(const AppSettings().svnLogLimit, kDefaultSvnLogLimit);
    });

    test('JSON 反序列化无 svn_log_limit 字段时使用同一默认值', () {
      final settings = AppSettings.fromJson(<String, dynamic>{});
      expect(settings.svnLogLimit, kDefaultSvnLogLimit);
    });
  });

  group('parseStopDateTime', () {
    test('null → null（未配置）', () {
      expect(parseStopDateTime(null), isNull);
    });

    test('空字符串 → null（与 null 等价对待，UI 清空按钮可能写空串）', () {
      // settings UI 的清空按钮可能写入 ''（不是 null）——两种"无值"语义相同。
      expect(parseStopDateTime(''), isNull);
    });

    test('合法 ISO 日期 → DateTime', () {
      final result = parseStopDateTime('2024-01-15');
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('合法 ISO 日期时间 → DateTime', () {
      final result = parseStopDateTime('2024-01-15T10:30:00Z');
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.hour, 10);
    });

    test('非 ISO 格式（斜杠分隔）→ null（不容错）', () {
      // 严格按 ISO-8601，宽松匹配会让格式错误的 bug 静默存在。
      expect(parseStopDateTime('2024/01/15'), isNull);
    });

    test('完全无效字符串 → null（不抛异常）', () {
      // 预加载是后台静默任务，不能因坏字符串崩溃。
      expect(parseStopDateTime('invalid'), isNull);
      expect(parseStopDateTime('garbage'), isNull);
    });

    test('前后空白的合法日期 → null（不做容错 trim）', () {
      // '  2024-01-01  ' 在 DateTime.parse 看来是无效的——保持严格契约。
      expect(parseStopDateTime('  2024-01-01  '), isNull);
    });

    test('部分合法（年-月）→ null', () {
      // DateTime.parse 要求至少 'YYYY-MM-DD'。
      expect(parseStopDateTime('2024-01'), isNull);
    });

    test('PreloadSettings.stopDateTime 与 parseStopDateTime 输出等价', () {
      const settings = PreloadSettings(stopDate: '2024-06-30');
      expect(settings.stopDateTime, parseStopDateTime('2024-06-30'));
    });

    test('PreloadSettings 默认值（stopDate == null）→ stopDateTime == null', () {
      const settings = PreloadSettings();
      expect(settings.stopDate, isNull);
      expect(settings.stopDateTime, isNull);
    });

    test('未来日期与过去日期都正常解析（不做范围校验）', () {
      // 范围语义由 preload_service 决定（"截止日期早于现在 = 不预加载"）。
      // 解析层不做范围校验。
      expect(parseStopDateTime('1999-01-01'), isNotNull);
      expect(parseStopDateTime('2099-12-31'), isNotNull);
    });
  });

  // R101 JsonSerializable round-trip 完整性审计：
  // lib/models/app_config.dart 内 4 个 @JsonSerializable 类（SourceUrlConfig /
  // PreloadSettings / AppSettings / AppConfig）应有"全字段非默认值 round-trip"测试，
  // 锁住 toJson/fromJson 的字段对称性。原有测试只针对单个字段或边界——本轮补齐：
  //   - 全字段都用"显式非默认值"（避免与 @JsonKey default 退化无法区分）
  //   - nullable 字段做 null 与非 null 双路 round-trip（原 PreloadSettings round-trip
  //     在 storage_service_test.dart 已覆盖非 null path，此处不重复）
  //   - AppConfig 嵌套 round-trip 锁 sourceUrls(List) + settings 嵌套字段对称
  // **设计模式**：每个 round-trip 用 `expect(restored.X, original.X)` 逐字段断言而非
  // `expect(restored, equals(original))`——后者依赖 == 重写（lib/ 内 @JsonSerializable
  // 类未实现 ==），逐字段断言在 fail 时直接指向"哪个字段对称性破了"。
  group('SourceUrlConfig round-trip 完整性（R101）', () {
    test('全字段非默认值 round-trip', () {
      const original = SourceUrlConfig(
        name: 'release-branch',
        url: 'svn://repo/branches/release',
        description: '主发布分支',
        enabled: false, // 故意非 default（default=true）
      );
      final restored = SourceUrlConfig.fromJson(original.toJson());
      expect(restored.name, original.name);
      expect(restored.url, original.url);
      expect(restored.description, original.description);
      expect(restored.enabled, original.enabled);
    });

    test('default value 字段省略后 fromJson 仍能 hydrate（向后兼容旧配置文件）', () {
      // 真实用户的旧配置文件可能没有 description / enabled key——
      // @JsonKey default 必须能补齐，否则升级时崩。
      final restored = SourceUrlConfig.fromJson({
        'name': 'old-config',
        'url': 'svn://legacy',
      });
      expect(restored.description, '');
      expect(restored.enabled, isTrue);
    });
  });

  group('AppSettings round-trip 完整性（R101）', () {
    test('全字段非默认值 round-trip', () {
      const original = AppSettings(
        svnLogLimit: 500, // 非 default(200)
        logPageSize: 100, // 非 default(50)
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.svnLogLimit, original.svnLogLimit);
      expect(restored.logPageSize, original.logPageSize);
    });

    test('@JsonKey 字段名映射：lib 字段 svnLogLimit ↔ JSON key svn_log_limit', () {
      // 锁住 snake_case ↔ camelCase 的映射方向——若有人误把 lib 字段直接命名为
      // svn_log_limit 会破坏 toJson 输出格式（与历史配置文件不兼容）。
      const original = AppSettings(svnLogLimit: 500, logPageSize: 100);
      final json = original.toJson();
      expect(json.keys.toSet(), {'svn_log_limit', 'log_page_size'},
          reason: 'AppSettings.toJson 必须输出 snake_case key——历史配置文件依赖此格式。');
    });
  });

  group('AppConfig round-trip 完整性（R101）', () {
    // **R101 重要发现 / 实测契约**：AppConfig 的 toJson 直接返回的 Map 内部嵌套字段
    // （sourceUrls / settings）仍是 lib 类型对象（List<SourceUrlConfig> / AppSettings），
    // 不是 Map<String, dynamic>。直接 `AppConfig.fromJson(config.toJson())` 会因
    // type cast 失败抛 `type 'SourceUrlConfig' is not a subtype of type 'Map<String, dynamic>'`。
    // 真实持久化路径是 `jsonEncode(config.toJson())` → `jsonDecode(content)` → fromJson
    // （见 config_service.dart:177-178），dart 的 jsonEncode 会递归调用嵌套对象的 toJson。
    // 本 group 用 jsonEncode + jsonDecode 模拟真实路径——这是把 lib **端到端序列化契约**
    // 显式锁进测试。继承 R98 "测试不绑实现细节"原则：测的是"配置文件能正确读写"，
    // 不是 toJson/fromJson 方法本身的签名细节。
    Map<String, dynamic> serialize(AppConfig config) =>
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;

    test('嵌套结构 round-trip：sourceUrls(List) + settings 嵌套字段对称', () {
      const original = AppConfig(
        version: '2.5.1',
        sourceUrls: [
          SourceUrlConfig(
            name: 'main',
            url: 'svn://repo/trunk',
            description: '主线',
            enabled: true,
          ),
          SourceUrlConfig(
            name: 'release',
            url: 'svn://repo/branches/release',
            description: '发布',
            enabled: false,
          ),
        ],
        settings: AppSettings(svnLogLimit: 300, logPageSize: 75),
      );
      final restored = AppConfig.fromJson(serialize(original));
      expect(restored.version, original.version);
      expect(restored.sourceUrls.length, 2);
      expect(restored.sourceUrls[0].name, 'main');
      expect(restored.sourceUrls[0].enabled, isTrue);
      expect(restored.sourceUrls[1].name, 'release');
      expect(restored.sourceUrls[1].enabled, isFalse);
      expect(restored.settings.svnLogLimit, 300);
      expect(restored.settings.logPageSize, 75);
    });

    test('空 sourceUrls 列表 round-trip（边界）', () {
      // 用户首次启动时 sourceUrls 可能为空——必须能 round-trip 不丢失。
      const original = AppConfig(
        version: '1.0.0',
        sourceUrls: [],
        settings: AppSettings(),
      );
      final restored = AppConfig.fromJson(serialize(original));
      expect(restored.sourceUrls, isEmpty);
      expect(restored.version, '1.0.0');
    });

    test('@JsonKey 字段名映射：lib 字段 sourceUrls ↔ JSON key source_urls', () {
      const original = AppConfig(
        version: '1.0.0',
        sourceUrls: [],
        settings: AppSettings(),
      );
      // jsonEncode 后的 JSON 文本应含 source_urls 而非 sourceUrls
      final jsonText = jsonEncode(original.toJson());
      expect(jsonText.contains('source_urls'), isTrue,
          reason: 'AppConfig 序列化必须使用 source_urls (snake_case)——'
              '历史配置文件依赖此格式。');
      expect(jsonText.contains('"sourceUrls"'), isFalse,
          reason: '不应输出 sourceUrls (camelCase)——会与历史配置文件不兼容。');
    });

    test('R101 实测发现 doc 化：直接 fromJson(toJson()) 不工作（端到端路径需要 jsonEncode）', () {
      // 显式锁住"toJson 输出含未序列化的嵌套对象"这一行为契约——
      // 防止有人误把 toJson 实现改成"递归调用嵌套 toJson"（这会破坏 jsonEncode 链路）。
      // 当前行为：toJson() 返回的 Map 内 sourceUrls 仍是 List<SourceUrlConfig>。
      const config = AppConfig(
        version: '1.0',
        sourceUrls: [SourceUrlConfig(name: 'x', url: 'y')],
        settings: AppSettings(),
      );
      final raw = config.toJson();
      expect(raw['source_urls'], isA<List>(),
          reason: 'toJson 输出 source_urls 字段应为 List。');
      expect(raw['source_urls'][0], isA<SourceUrlConfig>(),
          reason: '当前契约：toJson 不递归调用嵌套 toJson——依赖 jsonEncode 自动调用。'
              '若有人改成递归 toJson，会让 jsonEncode 双重序列化或 fromJson 失败。');
    });
  });

  group('PreloadSettings round-trip null 边界（R101）', () {
    // PreloadSettings 全字段非 null round-trip 已在 storage_service_test.dart:297
    // 锁定，本轮只补"stopDate==null"边界——nullable 字段必须双路 round-trip。
    test('stopDate==null（默认）round-trip 保持 null', () {
      const original = PreloadSettings(); // stopDate 默认 null
      expect(original.stopDate, isNull);
      final restored = PreloadSettings.fromJson(original.toJson());
      expect(restored.stopDate, isNull);
    });

    test('stopDate=null 与 stopDate="" 不应等价（区分"未设"与"空串"）', () {
      // 防御性边界：JSON 内 stopDate 字段可能存为 null 或空串——两者语义都是"不限制"。
      // 当前 lib doc:179 声明 null = 不限制，本测试锁定空串也走 null 路径或保留为空串
      // （任一行为稳定即可，关键是不能崩）。
      final fromNull = PreloadSettings.fromJson({'stop_date': null});
      expect(fromNull.stopDate, isNull, reason: 'JSON null → 字段 null（默认行为）');
      // 空串解析当前行为（应保留为空串，因为 stopDate 是 String?）
      final fromEmpty = PreloadSettings.fromJson({'stop_date': ''});
      expect(fromEmpty.stopDate, '',
          reason: 'JSON 空串 → 字段空串（与 null 不等价，但解析层不崩）');
    });
  });

  // R102 copyWith 完整性 / 字段对称性审计：
  // app_config.dart 内 3 个有 copyWith 的类（SourceUrlConfig / PreloadSettings /
  // AppSettings）原本 0 个 copyWith 测试。本轮补"全字段独立可改对称性"+"nullable
  // 字段 reset 限制 doc 化"。
  // **关键审计发现**：PreloadSettings.copyWith 用 `stopDate ?? this.stopDate` 模式——
  // 一旦 stopDate 已设值，**无法通过 copyWith 把它清回 null**。这与 MergeJob.copyWith 用
  // `_unset` sentinel 处理 nullable reset 的模式不一致。本轮把这条 lib 实测契约 doc 化进
  // 测试（R101 模式）——若未来有人在调用方需要"通过 copyWith 清掉 stopDate"，必须改 lib
  // 实现（如加 clearStopDate flag），本测试会撞红提示。
  group('SourceUrlConfig copyWith 全字段对称性（R102）', () {
    const baseline = SourceUrlConfig(
      name: 'baseline',
      url: 'svn://baseline',
      description: 'baseline-desc',
      enabled: true,
    );

    test('修改单个字段时其他 3 字段全部保持原值', () {
      final modName = baseline.copyWith(name: 'new');
      expect(modName.name, 'new');
      expect(modName.url, baseline.url);
      expect(modName.description, baseline.description);
      expect(modName.enabled, baseline.enabled);

      final modUrl = baseline.copyWith(url: 'svn://new');
      expect(modUrl.url, 'svn://new');
      expect(modUrl.name, baseline.name);

      final modDesc = baseline.copyWith(description: 'new-desc');
      expect(modDesc.description, 'new-desc');
      expect(modDesc.name, baseline.name);

      final modEnabled = baseline.copyWith(enabled: false);
      expect(modEnabled.enabled, isFalse);
      expect(modEnabled.name, baseline.name);
    });

    test('无参 copyWith 等价于副本（保留所有原值）', () {
      final copy = baseline.copyWith();
      expect(copy.name, baseline.name);
      expect(copy.url, baseline.url);
      expect(copy.description, baseline.description);
      expect(copy.enabled, baseline.enabled);
    });
  });

  group('PreloadSettings copyWith 全字段对称性（R102）', () {
    const baseline = PreloadSettings(
      enabled: true,
      stopOnBranchPoint: true,
      maxDays: 30,
      maxCount: 500,
      stopRevision: 100,
      stopDate: '2025-01-01',
    );

    test('修改单个字段时其他 5 字段全部保持原值', () {
      final modEnabled = baseline.copyWith(enabled: false);
      expect(modEnabled.enabled, isFalse);
      expect(modEnabled.stopOnBranchPoint, baseline.stopOnBranchPoint);
      expect(modEnabled.maxDays, baseline.maxDays);
      expect(modEnabled.maxCount, baseline.maxCount);
      expect(modEnabled.stopRevision, baseline.stopRevision);
      expect(modEnabled.stopDate, baseline.stopDate);

      final modStopOnBp = baseline.copyWith(stopOnBranchPoint: false);
      expect(modStopOnBp.stopOnBranchPoint, isFalse);
      expect(modStopOnBp.enabled, baseline.enabled);

      final modMaxDays = baseline.copyWith(maxDays: 60);
      expect(modMaxDays.maxDays, 60);
      expect(modMaxDays.maxCount, baseline.maxCount);

      final modMaxCount = baseline.copyWith(maxCount: 999);
      expect(modMaxCount.maxCount, 999);
      expect(modMaxCount.maxDays, baseline.maxDays);

      final modStopRev = baseline.copyWith(stopRevision: 9999);
      expect(modStopRev.stopRevision, 9999);
      expect(modStopRev.maxCount, baseline.maxCount);

      final modStopDate = baseline.copyWith(stopDate: '2026-12-31');
      expect(modStopDate.stopDate, '2026-12-31');
      expect(modStopDate.stopRevision, baseline.stopRevision);
    });

    test('R102 lib 实测契约 doc 化：copyWith 无法把 stopDate 清回 null（?? this.X 限制）', () {
      // 现状锁定：PreloadSettings.copyWith 用 `stopDate ?? this.stopDate` 模式——
      // 一旦 stopDate 已设值，传 null 会被 `??` 回退到原值。
      // **判据**：与 MergeJob.copyWith 的 _unset sentinel 模式不一致，若未来调用方
      // 需要"通过 copyWith 清 stopDate"必须先改 lib 实现（加 clearStopDate flag 或
      // 改用 _unset sentinel）。本测试撞红即是改 lib 的强提示。
      // 当前清空路径：直接 `PreloadSettings(stopDate: null, ...其他字段)` 重建，
      // 见 storage_service.dart / settings_screen.dart 等。
      const withStopDate = PreloadSettings(stopDate: '2025-01-01');
      final attempt = withStopDate.copyWith(stopDate: null);
      expect(attempt.stopDate, '2025-01-01',
          reason: 'copyWith(stopDate: null) 不能清空——`?? this.stopDate` 会回退到原值。'
              '若调用方需要清空 stopDate 必须直接 new PreloadSettings(...) 重建。');
    });

    test('无参 copyWith 等价于副本（保留所有原值）', () {
      final copy = baseline.copyWith();
      expect(copy.enabled, baseline.enabled);
      expect(copy.stopOnBranchPoint, baseline.stopOnBranchPoint);
      expect(copy.maxDays, baseline.maxDays);
      expect(copy.maxCount, baseline.maxCount);
      expect(copy.stopRevision, baseline.stopRevision);
      expect(copy.stopDate, baseline.stopDate);
    });
  });

  group('AppSettings copyWith 全字段对称性（R102）', () {
    const baseline = AppSettings(svnLogLimit: 300, logPageSize: 75);

    test('修改单个字段时其他字段保持原值', () {
      final modSvnLogLimit = baseline.copyWith(svnLogLimit: 999);
      expect(modSvnLogLimit.svnLogLimit, 999);
      expect(modSvnLogLimit.logPageSize, baseline.logPageSize);

      final modLogPageSize = baseline.copyWith(logPageSize: 200);
      expect(modLogPageSize.logPageSize, 200);
      expect(modLogPageSize.svnLogLimit, baseline.svnLogLimit);
    });

    test('无参 copyWith 等价于副本', () {
      final copy = baseline.copyWith();
      expect(copy.svnLogLimit, baseline.svnLogLimit);
      expect(copy.logPageSize, baseline.logPageSize);
    });
  });
}
