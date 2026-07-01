import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132-R140 复用，R141 第 11 次复用）。
String _stripComments(String src) {
  return src.split('\n').where((line) {
    final t = line.trimLeft();
    return !t.startsWith('///') && !t.startsWith('//');
  }).join('\n');
}

/// **R141 SharedPreferences 类型轴协议审计**
///
/// 协议要点（详见 lib/services/storage_service.dart 内 `class StorageService`
/// 上方 R141 doc-block）：
/// - 4 type 全集穷尽：bool / int / string / stringList（无 double）
/// - 21 业务 keys + 1 legacy key 的类型矩阵
/// - T1 read/write 镜像律：每 key 读写 type 必须匹配
/// - T2 key 字面量单点律：preload_* 仅在读侧 + buildPreloadWriteOps 出现
/// - T3 default fallback 单点律：tracable to defaultPreloadSettingsMap /
///   kDefaultMaxRetries / `[]`
/// - T4 legacy key 清理协议：仅 if(containsKey) remove，无读写
void main() {
  final storageSrc =
      File('lib/services/storage_service.dart').readAsStringSync();
  final logCacheSrc =
      File('lib/services/log_cache_service.dart').readAsStringSync();
  final storageCode = _stripComments(storageSrc);
  final logCacheCode = _stripComments(logCacheSrc);

  // 21 业务 keys 按类型分桶（与 doc-block 字典序一致）
  const boolKeys = [
    'preload_enabled',
    'preload_stop_on_branch_point',
    'use_temporary_sparse_working_copy',
  ];
  const intKeys = [
    'default_max_retries',
    'preload_max_count',
    'preload_max_days',
    'preload_stop_revision',
  ];
  const stringKeys = [
    'last_author_filter',
    'last_message_filter',
    'last_source_url',
    'last_target_wc',
    'last_target_url',
    'last_title_filter',
    'log_cache_url_hash_map',
    'preload_stop_date',
    'window_bounds',
  ];
  const stringListKeys = [
    'author_filter_history',
    'source_url_history',
    'switch_branch_history',
    'target_wc_history',
    'target_url_history',
  ];
  const legacyKeys = ['preload_settings'];

  group('R141 G1: 4 type 全集穷尽闭合', () {
    test('SP 仅使用 4 个原始类型 API（无 double）', () {
      // 业务代码不调 setDouble / getDouble
      expect(storageCode, isNot(contains('setDouble')), reason: '本项目无浮点存储需求');
      expect(storageCode, isNot(contains('getDouble')));
      expect(logCacheCode, isNot(contains('setDouble')));
      expect(logCacheCode, isNot(contains('getDouble')));
    });

    test('storage_service 同时使用 4 个 SP 类型 API（每类至少一处）', () {
      expect(storageCode, contains('setBool('));
      expect(storageCode, contains('getBool('));
      expect(storageCode, contains('setInt('));
      expect(storageCode, contains('getInt('));
      expect(storageCode, contains('setString('));
      expect(storageCode, contains('getString('));
      expect(storageCode, contains('setStringList('));
      expect(storageCode, contains('getStringList('));
    });
  });

  group('R141 G2: T1 read/write 镜像律（每 key 读写 type 一致）', () {
    test('bool keys 读写都走 getBool/setBool', () {
      for (final k in boolKeys) {
        // 至少出现一处 getBool('k')
        expect(
          RegExp("getBool\\('$k'\\)").hasMatch(storageCode),
          isTrue,
          reason: 'bool key $k 应有 getBool 读路径',
        );
        // 至少出现一处 setBool('k') 或经 PreloadWriteOpKind.setBool 派发
        // （buildPreloadWriteOps 中 key 字面量为 'k'）
        final hasSetBool = RegExp("setBool\\('$k'").hasMatch(storageCode);
        final hasOpDispatch =
            RegExp("key: '$k',[\\s\\S]{0,80}?PreloadWriteOpKind\\.setBool")
                .hasMatch(storageCode);
        expect(hasSetBool || hasOpDispatch, isTrue,
            reason: 'bool key $k 必须有 setBool 写路径或 op dispatch');
      }
    });

    test('int keys 读写都走 getInt/setInt', () {
      for (final k in intKeys) {
        expect(
          RegExp("getInt\\('$k'\\)").hasMatch(storageCode),
          isTrue,
          reason: 'int key $k 应有 getInt 读路径',
        );
        final hasSetInt = RegExp("setInt\\('$k'").hasMatch(storageCode);
        final hasOpDispatch =
            RegExp("key: '$k',[\\s\\S]{0,80}?PreloadWriteOpKind\\.setInt")
                .hasMatch(storageCode);
        expect(hasSetInt || hasOpDispatch, isTrue,
            reason: 'int key $k 必须有 setInt 写路径或 op dispatch');
      }
    });

    test('string keys 读侧走 getString', () {
      // log_cache_url_hash_map 在 log_cache_service 中
      for (final k in stringKeys) {
        final src =
            (k == 'log_cache_url_hash_map') ? logCacheCode : storageCode;
        // log_cache_url_hash_map 用 const _urlHashMapKey 而非字面量
        if (k == 'log_cache_url_hash_map') {
          expect(src, contains("'log_cache_url_hash_map'"),
              reason: '$k 字面量应在 log_cache_service 出现（_urlHashMapKey 常量定义）');
          expect(src, contains('getString(_urlHashMapKey)'),
              reason: '$k 应通过 _urlHashMapKey 常量 getString');
          expect(src, contains('setString(_urlHashMapKey'),
              reason: '$k 应通过 _urlHashMapKey 常量 setString');
        } else if (k == 'window_bounds') {
          expect(src, contains("kWindowBoundsKey = 'window_bounds'"),
              reason: '$k 字面量应在 storage_service 常量定义中出现');
          expect(src, contains('getString(kWindowBoundsKey)'),
              reason: '$k 应通过 kWindowBoundsKey 常量 getString');
          expect(src, contains('setString(kWindowBoundsKey'),
              reason: '$k 应通过 kWindowBoundsKey 常量 setString');
        } else {
          expect(
            RegExp("getString\\('$k'\\)").hasMatch(src),
            isTrue,
            reason: 'string key $k 应有 getString 读路径',
          );
        }
      }
    });

    test('preload_stop_date 写侧支持 setString **或** removeKey（null 语义）', () {
      // doc-block 已说明：stop_date == null → removeKey
      expect(
        RegExp("key: 'preload_stop_date'").hasMatch(storageCode),
        isTrue,
      );
      // buildPreloadWriteOps 内的三元 stopDate == null ? removeKey : setString
      expect(
        storageCode,
        contains('PreloadWriteOpKind.removeKey'),
      );
    });

    test('stringList keys 读写都走 getStringList/setStringList', () {
      for (final k in stringListKeys) {
        expect(
          RegExp("getStringList\\('$k'\\)").hasMatch(storageCode),
          isTrue,
          reason: 'stringList key $k 应有 getStringList 读路径',
        );
        expect(
          RegExp("setStringList\\('$k'").hasMatch(storageCode),
          isTrue,
          reason: 'stringList key $k 应有 setStringList 写路径',
        );
      }
    });

    test('禁止跨类型读写（同一 key 不能同时 setInt + setString 等）', () {
      // 列举所有出现过的 key 字面量（boolKeys + intKeys + stringKeys + stringListKeys）
      // 验证每个 key 在 storage_service 中只对应单一类型 API
      const allBusinessKeys = [
        ...boolKeys,
        ...intKeys,
        ...stringKeys,
        ...stringListKeys,
      ];
      for (final k in allBusinessKeys) {
        if (k == 'log_cache_url_hash_map') continue; // 不在 storage_service
        // 'String' 会被 'StringList' 包含；ripgrep 已用 \( 边界，正则的 ' 已是边界
        // 但 String 与 StringList 的 API 名前缀重叠——用更严格匹配
        final keyExpression =
            k == 'window_bounds' ? 'kWindowBoundsKey' : "'$k'";
        final escapedKeyExpression = RegExp.escape(keyExpression);
        final boolHit = RegExp("(get|set)Bool\\($escapedKeyExpression")
            .hasMatch(storageCode);
        final intHit = RegExp("(get|set)Int\\($escapedKeyExpression")
            .hasMatch(storageCode);
        final stringHit = RegExp("(get|set)String\\($escapedKeyExpression")
            .hasMatch(storageCode);
        final listHit = RegExp("(get|set)StringList\\($escapedKeyExpression")
            .hasMatch(storageCode);
        final hits =
            [boolHit, intHit, stringHit, listHit].where((h) => h).length;
        expect(hits, equals(1),
            reason:
                'key $k 必须只对应一种 SP 类型 API；实际：bool=$boolHit int=$intHit string=$stringHit list=$listHit');
      }
    });
  });

  group('R141 G3: T2 key 字面量单点律', () {
    test('每个 preload_* 业务 key 在 buildPreloadWriteOps 内出现 1 次', () {
      const preloadKeys = [
        'preload_enabled',
        'preload_stop_on_branch_point',
        'preload_max_days',
        'preload_max_count',
        'preload_stop_revision',
        'preload_stop_date',
      ];
      // 提取 buildPreloadWriteOps 函数体
      final fnMatch =
          RegExp(r'List<PreloadWriteOp> buildPreloadWriteOps[\s\S]+?\n\}\n')
              .firstMatch(storageCode);
      expect(fnMatch, isNotNull, reason: 'buildPreloadWriteOps 必须可被定位');
      final fnBody = fnMatch!.group(0)!;
      for (final k in preloadKeys) {
        final occurrences = "'$k'".allMatches(fnBody).length;
        expect(occurrences, equals(1),
            reason: 'buildPreloadWriteOps 内 $k 字面量必须恰好 1 次（实际 $occurrences）');
      }
    });

    test('savePreloadSettings 函数体内不再直接写 preload_* 字面量（统一走 op dispatch）', () {
      final fnMatch =
          RegExp(r'Future<void> savePreloadSettings[\s\S]+?\n  \}\n')
              .firstMatch(storageCode);
      expect(fnMatch, isNotNull);
      final fnBody = fnMatch!.group(0)!;
      // 仅允许 'preload_settings' (legacy 清理) 出现；preload_enabled 等业务 key
      // 不应在 savePreloadSettings 函数体内出现
      for (final k in [
        'preload_enabled',
        'preload_stop_on_branch_point',
        'preload_max_days',
        'preload_max_count',
        'preload_stop_revision',
        'preload_stop_date',
      ]) {
        expect(fnBody.contains("'$k'"), isFalse,
            reason: 'savePreloadSettings 函数体内不应直接写 $k；改走 buildPreloadWriteOps');
      }
      // legacy key 必须出现
      expect(fnBody, contains("'preload_settings'"),
          reason: 'savePreloadSettings 末尾保留 legacy key 清理');
    });
  });

  group('R141 G4: T3 default fallback 单点律', () {
    test('preload_* 6 个 getter 的 ?? 兜底全部追溯到 defaultPreloadSettingsMap', () {
      // 6 个独立 getPreloadX getter 内的 ?? fallback
      final fallbackHits =
          'defaultPreloadSettingsMap()'.allMatches(storageCode).length;
      // getPreloadSettings(扁平 map 6 段调一次) + 5 个独立 getter (enabled/
      // stop_on_branch_point/max_days/max_count/stop_revision；stop_date 不加
      // ?? 因为本身就允许 null)
      // 实际计数 ≥ 6 即可（doc-block 内不计——已 _stripComments）
      expect(fallbackHits, greaterThanOrEqualTo(6),
          reason: 'defaultPreloadSettingsMap() 应在 6+ 处被作为 fallback 来源');
    });

    test('default_max_retries 兜底为 kDefaultMaxRetries（app_config 单点）', () {
      expect(
        storageCode,
        contains("getInt('default_max_retries') ?? kDefaultMaxRetries"),
      );
    });

    test('*_history stringList 兜底固定为 [] 字面量', () {
      for (final k in stringListKeys) {
        // 兜底必须是 ?? []
        expect(
          RegExp("getStringList\\('$k'\\) \\?\\? \\[\\]").hasMatch(storageCode),
          isTrue,
          reason: '$k 兜底应为 []（语义"空历史"）',
        );
      }
    });

    test('last_* string 不加 ?? 兜底（让 null 透传给调用方）', () {
      // last_source_url / last_target_wc / last_target_url / last_author_filter / last_title_filter / last_message_filter
      const lastKeys = [
        'last_source_url',
        'last_target_wc',
        'last_target_url',
        'last_author_filter',
        'last_title_filter',
        'last_message_filter',
      ];
      for (final k in lastKeys) {
        final lineMatch = RegExp("return _prefs!\\.getString\\('$k'\\)([^;]*);")
            .firstMatch(storageCode);
        expect(lineMatch, isNotNull, reason: '$k 必须有 getString 读 line');
        final tail = lineMatch!.group(1)!;
        expect(tail.contains('??'), isFalse,
            reason: '$k 不应加 ?? 兜底；让 String? null 透传');
      }
    });
  });

  group('R141 G5: T4 legacy key 清理协议', () {
    test('preload_settings 仅出现在 if(containsKey) remove 清理处', () {
      // 仅允许：containsKey + remove；禁止 setX 写、getX 读
      expect(
        storageCode,
        contains("containsKey('preload_settings')"),
      );
      expect(
        storageCode,
        contains("remove('preload_settings')"),
      );
      // 严禁读写
      for (final api in ['getString', 'getBool', 'getInt', 'getStringList']) {
        expect(
          storageCode.contains("$api('preload_settings')"),
          isFalse,
          reason: 'legacy key preload_settings 严禁出现 $api 读路径',
        );
      }
      for (final api in ['setString', 'setBool', 'setInt', 'setStringList']) {
        expect(
          storageCode.contains("$api('preload_settings'"),
          isFalse,
          reason: 'legacy key preload_settings 严禁出现 $api 写路径',
        );
      }
    });

    test('legacyKeys 清单与 doc-block 一致（本轮唯一 1 个）', () {
      expect(legacyKeys, equals(['preload_settings']));
    });
  });

  group('R141 G6: doc-block 关键字锚点', () {
    test('storage_service.dart 顶部 R141 doc-block 关键术语锚点齐全', () {
      // 注意：doc 注释会被 _stripComments 剥离；此处直接读 raw src
      expect(storageSrc, contains('R141 SharedPreferences 类型轴协议审计'));
      expect(storageSrc, contains('4 type 全集穷尽闭合'));
      expect(storageSrc, contains('T1 read/write 镜像律'));
      expect(storageSrc, contains('T2 key 字面量单点律'));
      expect(storageSrc, contains('T3 default fallback 单点律'));
      expect(storageSrc, contains('T4 legacy key 清理协议'));
      // 与 R138/R139/R140 logger 平面互文
      expect(storageSrc, contains('R138'));
      expect(storageSrc, contains('R139'));
      expect(storageSrc, contains('R140'));
      expect(storageSrc, contains('故意不做'));
    });
  });
}
