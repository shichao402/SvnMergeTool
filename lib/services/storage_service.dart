/// 持久化存储服务
///
/// 负责管理应用的历史记录、队列等数据的持久化存储
/// 使用 shared_preferences 存储简单数据，使用 JSON 文件存储复杂数据

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../models/merge_job.dart';
import 'app_paths_service.dart';
import 'logger_service.dart';

/// 把"历史记录列表"规整成符合 MRU 持久化约定的形态：
/// 1. 保留**首次出现**的元素的相对顺序（`Set` + `toList()` 在 Dart 中等价于 `LinkedHashSet`，
///    所以 `[a, b, a, c]` → `[a, b, c]`，**不是** `[a, c, b]`）。
/// 2. 截断到 `maxLength` 条；若已 `<= maxLength` 则保持原长。
///
/// 与原 `saveSourceUrlHistory` / `saveTargetWcHistory` 行为一致：
/// 它们之前用的是 `urls.toSet().toList()` + `if (length > 20) removeRange(20, length)`。
///
/// **不修改入参**，返回新 list。`maxLength <= 0` 视为非法（与"队列长度"语义不符），抛 `ArgumentError`。
@visibleForTesting
List<String> normalizeMruHistory(
  List<String> items, {
  required int maxLength,
}) {
  if (maxLength <= 0) {
    throw ArgumentError.value(maxLength, 'maxLength', '必须为正整数');
  }
  final deduped = items.toSet().toList();
  if (deduped.length > maxLength) {
    deduped.removeRange(maxLength, deduped.length);
  }
  return deduped;
}

/// 把 `item` 提升到 MRU 列表的最前面：
/// 1. 先从 history 里删掉所有等于 `item` 的元素（理论上只会有 0 / 1 个，
///    但若调用方传了未去重的 list 也能正确处理）。
/// 2. 把 `item` 插到 index 0。
/// 3. 截断到 `maxLength` 条。
///
/// 与原 `addSourceUrlToHistory` / `addTargetWcToHistory` / `addAuthorToFilterHistory`
/// 的语义一致。三个原函数对 `maxLength` 的取值不一样（URL 系列用 20，author 用 5），
/// 提取成参数后调用方各自传值。
///
/// **不修改入参**，返回新 list。空字符串 / 全空白 `item` 也会被插入——是否丢弃由调用方决定
/// （`addAuthorToFilterHistory` 的 `trim().isEmpty` 守卫保留在 IO 方法里，因为它跟 trim
/// 后存储的副作用绑定，不是纯列表操作）。
@visibleForTesting
List<String> promoteToMruFront(
  List<String> history,
  String item, {
  required int maxLength,
}) {
  if (maxLength <= 0) {
    throw ArgumentError.value(maxLength, 'maxLength', '必须为正整数');
  }
  final next = List<String>.from(history);
  // List.remove 只移除第一个匹配项；为防御调用方传入未去重 list，循环移除所有匹配项。
  // R124 mutator 二档判据：`next.remove(item)` 是**档 2**（element 由谓词等值匹配
  // 决定，不是常量）——这里 item 由调用方传入，每次匹配的 element 不固定。如果改
  // 成 Set 会破坏 MRU 的"按位置访问"语义（List 第 0 位 = 最近一次使用），与 R123
  // merge_execution_state `_currentJobIndex` 同形——结构身份必须保留 List。
  while (next.remove(item)) {}
  // R124 mutator 二档判据：`next.insert(0, item)` 是**档 1**（index ≡ 0 常量字面
  // 量）——单次插入头部 O(n)、不会退化到 O(n²)（不在循环里），与 R122 logger drain
  // loop（O(n²) 退化）形成对偶：同样 index=0 但单次 vs 循环决定是否需要 Queue。
  next.insert(0, item);
  if (next.length > maxLength) {
    next.removeRange(maxLength, next.length);
  }
  return next;
}

/// 队列加载时对中断任务进行恢复的批量映射。
///
/// 对每个 `job`：
/// - 若 `job.shouldRecoverAsInterrupted` 为 true，调用 `job.recoverInterrupted()` 替换之；
/// - 否则原样保留。
///
/// 返回 `(jobs: 处理后的列表, recoveredCount: 被恢复的任务数)`。调用方据 `recoveredCount`
/// 决定是否打印告警日志（保持与原 `loadQueue` 内联实现完全一致的统计口径）。
///
/// **不修改入参**：返回的是新 list，元素可能与入参相同（未触发恢复）或为新对象。
@visibleForTesting
({List<MergeJob> jobs, int recoveredCount}) recoverInterruptedJobs(
  List<MergeJob> jobs,
) {
  var recoveredCount = 0;
  final result = jobs.map((job) {
    if (job.shouldRecoverAsInterrupted) {
      recoveredCount++;
      return job.recoverInterrupted();
    }
    return job;
  }).toList();
  return (jobs: result, recoveredCount: recoveredCount);
}

/// 预加载设置的**默认值契约**（扁平化 map 形态）。
///
/// 所有 `StorageService.getPreload*` 系列 getter 的 `??` 兜底必须与本 map 一致——
/// 否则 UI 默认占位（[`SettingsScreen` 的 `formatPositiveIntForField`](../screens/settings_screen.dart)
/// + UI 复选框初始值）与"未保存过设置时返回的实际值"会悄悄不一致。
///
/// **每次调用返回新 map**：避免调用方误改后污染下次返回值（const map 在 Dart 里
/// 不可变，但即便调用方需要可变 map，本函数显式返回新实例也更安全）。
///
/// 默认值依据：
/// - `enabled = true`：默认开启预加载（首启用户体验）
/// - `stop_on_branch_point = true`：合并场景下分支点是天然边界
/// - `max_days = 90`：3 个月覆盖绝大多数 hotfix / feature 分支寿命
/// - `max_count = 1000`：足以装下大型 monorepo 单分支日志
/// - `stop_revision = 0`：0 表示"不限制"（与 `evaluatePreloadStopReason` 的
///   `> 0` 守卫语义一致）
/// - `stop_date = null`：null 表示"不限制"
@visibleForTesting
Map<String, dynamic> defaultPreloadSettingsMap() {
  return <String, dynamic>{
    'enabled': true,
    'stop_on_branch_point': true,
    'max_days': 90,
    'max_count': 1000,
    'stop_revision': 0,
    'stop_date': null,
  };
}

/// 预加载设置的"写指令"——把命令式 IO 调用变成可静态生成、可断言的纯数据。
///
/// 6 种 op 一一对应 [savePreloadSettings] 中 6 个 `if (settings.containsKey(k))` 分支：
/// - `setBool` / `setInt` / `setString`：写入对应类型；
/// - `removeKey`：仅在 `stop_date == null` 分支使用——SharedPreferences 没有
///   "存 null"概念，必须 remove 才能区分"未设置"与"显式 null"。
@visibleForTesting
enum PreloadWriteOpKind { setBool, setInt, setString, removeKey }

/// 单条写指令。`value` 在 `removeKey` 时为 null。类型由 [kind] 隐式承诺，
/// 调用方 dispatch 时 `as bool/int/String` 与原代码一致。
@visibleForTesting
class PreloadWriteOp {
  final String key;
  final PreloadWriteOpKind kind;
  final Object? value;

  const PreloadWriteOp({
    required this.key,
    required this.kind,
    required this.value,
  });

  @override
  bool operator ==(Object other) =>
      other is PreloadWriteOp &&
      other.key == key &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(key, kind, value);

  @override
  String toString() => 'PreloadWriteOp($kind, $key, $value)';
}

/// 把"用户提交的部分预加载设置 map"翻译成有序的写指令列表。
///
/// **契约**：
/// - 只处理 [defaultPreloadSettingsMap] 里出现过的 6 个 key——`settings` 中
///   多余的 key 被静默忽略，与原 `savePreloadSettings` 的 6 段 `containsKey` 一致。
/// - 顺序固定：enabled / stop_on_branch_point / max_days / max_count /
///   stop_revision / stop_date。这个顺序是**契约的一部分**——单测会断言写指令
///   顺序，便于调用方一次性原子性 `setMockInitialValues`，也便于 review 时对比 diff。
/// - `stop_date == null` → 生成 `removeKey` 指令而不是 `setString` 一个 null（
///   SharedPreferences 不允许存 null）。
/// - `settings` 中**未出现**的 key（不是 null，是 missing）→ **不**生成任何指令——
///   这是部分更新语义：调用方只想改 enabled，就只传 `{'enabled': true}`，
///   其它 key 保持原值不动。原代码靠 `containsKey` 守卫做到这一点，本函数完全保留。
@visibleForTesting
List<PreloadWriteOp> buildPreloadWriteOps(Map<String, dynamic> settings) {
  final ops = <PreloadWriteOp>[];
  if (settings.containsKey('enabled')) {
    ops.add(PreloadWriteOp(
      key: 'preload_enabled',
      kind: PreloadWriteOpKind.setBool,
      value: settings['enabled'],
    ));
  }
  if (settings.containsKey('stop_on_branch_point')) {
    ops.add(PreloadWriteOp(
      key: 'preload_stop_on_branch_point',
      kind: PreloadWriteOpKind.setBool,
      value: settings['stop_on_branch_point'],
    ));
  }
  if (settings.containsKey('max_days')) {
    ops.add(PreloadWriteOp(
      key: 'preload_max_days',
      kind: PreloadWriteOpKind.setInt,
      value: settings['max_days'],
    ));
  }
  if (settings.containsKey('max_count')) {
    ops.add(PreloadWriteOp(
      key: 'preload_max_count',
      kind: PreloadWriteOpKind.setInt,
      value: settings['max_count'],
    ));
  }
  if (settings.containsKey('stop_revision')) {
    ops.add(PreloadWriteOp(
      key: 'preload_stop_revision',
      kind: PreloadWriteOpKind.setInt,
      value: settings['stop_revision'],
    ));
  }
  if (settings.containsKey('stop_date')) {
    final stopDate = settings['stop_date'];
    ops.add(PreloadWriteOp(
      key: 'preload_stop_date',
      kind: stopDate == null
          ? PreloadWriteOpKind.removeKey
          : PreloadWriteOpKind.setString,
      value: stopDate,
    ));
  }
  return ops;
}

/// 反序列化 [StorageService] 队列文件（`queue.json`）的 JSON 字符串，得到 jobs list。
///
/// **契约**（R105 持久化 schema 审计）：
/// - 顶层必须是 JSON 对象（`Map<String, dynamic>`），否则抛 [TypeError]——
///   调用方 `loadQueue` 用 try/catch 吞掉后返回空 list（与原 inline 解析行为等价）。
/// - 顶层必须含 `'jobs'` 字段且为 `List`——同上，类型不符抛 [TypeError]。
///   **不要**改 `'jobs'` 字面量：磁盘上已存在的旧文件会突然解不出来、所有用户队列丢失。
///   如果真要改，必须配合迁移路径（读旧 key + 删旧 key + 写新 key）——参考
///   R104 `preload_settings` 旧 key 在 `savePreloadSettings` 中的清理模式。
/// - 每个 `'jobs'` 元素必须能被 `MergeJob.fromJson` 接受——元素类型异常会让整次
///   `loadQueue` 失败并返回空 list（不是部分恢复）；这是有意行为：队列文件损坏
///   时强制走"全空 + 用户重新建队"的安全路径，而非吃下部分损坏数据。
/// - 返回的 list **保留 JSON 数组顺序**——任务队列顺序就是执行顺序，乱序会改变
///   语义。这条不变量被 `loadQueue` 后续传给 `recoverInterruptedJobs`，
///   后者也是按 list 顺序处理。
@visibleForTesting
List<MergeJob> parseQueueJson(String jsonContent) {
  final json = jsonDecode(jsonContent) as Map<String, dynamic>;
  final jobsData = json['jobs'] as List<dynamic>;
  return jobsData
      .map((item) => MergeJob.fromJson(item as Map<String, dynamic>))
      .toList();
}

/// 序列化 jobs list 为队列文件的 JSON 字符串。
///
/// **契约**（与 [parseQueueJson] 配对，R105 持久化 schema 审计）：
/// - 顶层固定为 `{'jobs': [...]}` 对象——**不要**改成裸数组、不要加 `'version'` /
///   `'metadata'` 等额外字段，除非配合迁移读取逻辑。新增字段时优先选"读侧默认 +
///   写侧添加"（向前兼容），而不是直接改 schema。
/// - 使用 2 空格缩进的 [JsonEncoder.withIndent]——人类可读，方便用户在文件浏览器
///   里直接看队列状态。**不要**改成无缩进或制表符：缩进格式本身不是契约（解析侧
///   不依赖），但保持稳定能减少 git diff 噪音（万一用户做了备份 / 版本控制）。
/// - jobs 元素由 `MergeJob.toJson` 输出——契约锁在 MergeJob round-trip 测试上
///   （R101 已覆盖），本函数不重复锁。
@visibleForTesting
String serializeQueueJson(List<MergeJob> jobs) {
  final json = {
    'jobs': jobs.map((job) => job.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// 窗口布局在 SharedPreferences 中的唯一存储 key。
@visibleForTesting
const String kWindowBoundsKey = 'window_bounds';

/// 检查窗口矩形是否适合持久化。
bool isStorableWindowBounds(Rect bounds) {
  return bounds.left.isFinite &&
      bounds.top.isFinite &&
      bounds.width.isFinite &&
      bounds.height.isFinite &&
      bounds.width > 0 &&
      bounds.height > 0;
}

/// 把窗口矩形序列化成扁平 JSON map。
@visibleForTesting
Map<String, double> windowBoundsToJson(Rect bounds) {
  if (!isStorableWindowBounds(bounds)) {
    throw ArgumentError.value(bounds, 'bounds', '窗口矩形无效，无法持久化');
  }
  return {
    'left': bounds.left,
    'top': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };
}

double? _readFiniteDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) return null;
  final doubleValue = value.toDouble();
  return doubleValue.isFinite ? doubleValue : null;
}

/// 从 JSON 字符串恢复窗口矩形；坏数据返回 null，由调用方决定是否告警。
@visibleForTesting
Rect? parseWindowBoundsJson(String? jsonContent) {
  if (jsonContent == null || jsonContent.isEmpty) {
    return null;
  }

  try {
    final json = jsonDecode(jsonContent) as Map<String, dynamic>;
    final left = _readFiniteDouble(json, 'left');
    final top = _readFiniteDouble(json, 'top');
    final width = _readFiniteDouble(json, 'width');
    final height = _readFiniteDouble(json, 'height');
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    final bounds = Rect.fromLTWH(left, top, width, height);
    return isStorableWindowBounds(bounds) ? bounds : null;
  } catch (_) {
    return null;
  }
}

/// **R141 SharedPreferences 类型轴协议审计**（与 R104 prefs key 持久化审计正交）
///
/// 与 R138 (域) / R139 (量) / R140 (通道) 在 logger 平面构成 3D 后，本轮把审计
/// 视角切到 **StorageService + LogCacheService 的 SharedPreferences 表面**，沿
/// SP API **类型轴**做穷尽闭合。
///
/// **4 type 全集穷尽闭合**：SharedPreferences 仅支持 5 个原始类型 API
/// (bool/int/double/string/stringList)。本项目只使用其中 4 个——`double` 不被
/// 任何业务 key 使用（**故意不做**：所有数值都是计数 / 版本号 / revision，无小数）。
///
/// **业务 key 类型矩阵（21 keys，**字典序**列举防漏迁）：
///
/// | 类型        | key 字面量                          | 默认值来源                              | 读点                              | 写点 |
/// |------------|-----------------------------------|---------------------------------------|----------------------------------|------|
/// | bool       | `preload_enabled`                 | `defaultPreloadSettingsMap['enabled']`| `getPreloadSettings`/`getPreloadEnabled` | `savePreloadEnabled` + op |
/// | bool       | `preload_stop_on_branch_point`    | `defaultPreloadSettingsMap`           | `getPreloadSettings`/`getPreloadStopOnBranchPoint` | op |
/// | bool       | `use_temporary_sparse_working_copy` | false                                | `getUseTemporarySparseWorkingCopy` | `saveUseTemporarySparseWorkingCopy` |
/// | int        | `default_max_retries`             | `kDefaultMaxRetries` (app_config)     | `getDefaultMaxRetries`           | `saveDefaultMaxRetries` |
/// | int        | `preload_max_days`                | `defaultPreloadSettingsMap`           | `getPreloadSettings`/`getPreloadMaxDays` | op |
/// | int        | `preload_max_count`               | `defaultPreloadSettingsMap`           | `getPreloadSettings`/`getPreloadMaxCount` | op |
/// | int        | `preload_stop_revision`           | `defaultPreloadSettingsMap`           | `getPreloadSettings`/`getPreloadStopRevision` | op |
/// | string     | `last_source_url`                 | null (无 fallback)                     | `getLastSourceUrl`               | `saveLastSourceUrl` |
/// | string     | `last_target_wc`                  | null (无 fallback)                     | `getLastTargetWc`                | `saveLastTargetWc` |
/// | string     | `last_author_filter`              | null (无 fallback)                     | `getLastAuthorFilter`            | `saveLastAuthorFilter` |
/// | string     | `last_title_filter`               | null (无 fallback)                     | `getLastTitleFilter`             | `saveLastTitleFilter` |
/// | string     | `last_message_filter`             | null (无 fallback)                     | `getLastMessageFilter`           | `saveLastMessageFilter` |
/// | string     | `preload_stop_date`               | null (`defaultPreloadSettingsMap` 为 null) | `getPreloadSettings`/`getPreloadStopDate` | op (setString **或** removeKey) |
/// | string     | `log_cache_url_hash_map`          | null (调用方 if-非-null 守卫)           | `LogCacheService._loadUrlHashMap` | `LogCacheService._saveUrlHashMap` |
/// | string     | `last_target_url`                 | null (无 fallback)                     | `getLastTargetUrl`               | `saveLastTargetUrl` |
/// | string     | `window_bounds`                   | null (无 fallback)                     | `getWindowBounds`                | `saveWindowBounds` |
/// | stringList | `source_url_history`              | `[]` (空 list)                         | `getSourceUrlHistory`            | `saveSourceUrlHistory` (经 `normalizeMruHistory(20)`) |
/// | stringList | `switch_branch_history`           | `[]`                                  | `getSwitchBranchHistory`         | `saveSwitchBranchHistory` (`normalizeMruHistory(20)`) |
/// | stringList | `target_wc_history`               | `[]`                                  | `getTargetWcHistory`             | `saveTargetWcHistory` (`normalizeMruHistory(20)`) |
/// | stringList | `target_url_history`              | `[]`                                  | `getTargetUrlHistory`            | `saveTargetUrlHistory` (`normalizeMruHistory(20)`) |
/// | stringList | `author_filter_history`           | `[]`                                  | `getAuthorFilterHistory` (`take(5)`) | `addAuthorToFilterHistory` (`promoteToMruFront(5)`) |
///
/// **legacy key（1 个）**：`preload_settings`——R104 已 doc 化的旧嵌套 JSON
/// 格式，迁移完成后在 [savePreloadSettings] 末尾用 `if(containsKey) remove`
/// 一次性清理（line 527-533）。**永远不要再写**这个 key，只能 remove。
///
/// **T1 read/write 镜像律**：每个**业务** key（非 legacy）必须满足：
///   1. **读侧 type** == **写侧 type**——若读用 `getInt('foo')`，写必须 `setInt('foo', ...)`
///      或经 `PreloadWriteOpKind.setInt` 派发。**严禁**读侧 `getString`、写侧 `setInt`
///      （SharedPreferences 不会自动转换，下次读返回 null + fallback 默认值，
///      数据静默丢失）。
///   2. 至少一处读 + 至少一处写存在（除非该 key 显式标注为只读 / 只写 / legacy）。
///   3. SP 中 `getStringList`/`setStringList` 是**唯一**支持容器的类型；List<int>、
///      Map、嵌套 JSON 必须先 `jsonEncode → setString`、读时 `getString → jsonDecode`
///      （`log_cache_url_hash_map` 即此模式；`preload_settings` 旧格式也是，
///      已迁出）。
///
/// **T2 key 字面量单点律**：所有 `preload_*` 键的字面量必须**仅在两处**出现：
///   1. **读侧** `getPreloadSettings` 6 段 + 各 `getPreload*` getter
///   2. **写侧** [buildPreloadWriteOps] 6 个 `if(containsKey)` 分支
/// 任何**第三处**出现（除本 doc-block + R104 doc + legacy `preload_settings`
/// 清理点）都视为漏迁。`buildPreloadWriteOps` 是写侧的**唯一字面量来源**——
/// `savePreloadSettings` 不再直接写字面量，统一走 op dispatch。
///
/// **T3 default fallback 单点律**：每个读侧的 `??` 兜底值必须能**追溯到单一来源**：
///   - `preload_*` 6 个 key → [defaultPreloadSettingsMap]（且 `getPreloadSettings`
///     扁平 map 与 6 个独立 getter 必须返回**同一份兜底**——否则 R104 已 doc 化的
///     "UI 占位 vs 持久化兜底悄悄不一致"会复活）。
///   - `default_max_retries` → `kDefaultMaxRetries`（app_config.dart 单点）。
///   - `*_history` → 字面量 `[]`（语义"空历史"）；这是**唯一允许硬编码**的兜底。
///   - `last_*` → 不加 `??`，让 `String?` null 透传给调用方表达"无历史选择"。
///   - `window_bounds` → 不加 `??`，让 null 表达"没有保存过窗口布局"。
///   - `log_cache_url_hash_map` → 调用方 if-非-null 守卫，不在 SP 读侧加 `??`。
///
/// **T4 legacy key 清理协议**：旧 key 迁出后必须遵循：
///   1. 删除所有读路径（`prefs!.getX(legacyKey)` 全删）
///   2. 删除所有写路径（`setX(legacyKey, ...)` 全删）
///   3. **仅保留** `if(containsKey) remove` 的"幂等清理"——位置在新 key 写完
///      之后，确保迁移失败时不会丢用户数据。
///   4. 用 doc 注释说明"为什么还要 remove"（R104 已 doc 化）。
/// 当前**唯一** legacy key 是 `preload_settings`，已遵循 4 点。
///
/// **故意不做**：
///   1. ❌ 不引入 `double` 类型 SP——业务无浮点存储需求，引入会破坏 4 type 全集闭合。
///   2. ❌ 不抽 `_typedRead<T>` / `_typedWrite<T>` 泛型 helper——SP API 已是
///      `getBool/getInt/getString/getStringList` 强类型分裂，泛型 helper 会强制
///      `is T` runtime 分支 + `Object?` 转 T，反而比直写 4 个 case 更晦涩。
///   3. ❌ 不把 `getPreloadSettings` 6 段 inline `??` 改成循环遍历 keys——丢类型
///      静态检查（`getBool/getInt/getString` 是不同 API），且 6 段是固定 schema、
///      不会动态扩展。
///   4. ❌ 不把 `log_cache_url_hash_map` 与 `*_history` 都迁到 `setStringList`
///      ——前者是 Map<String,String>，stringList 只能存 `[k1,v1,k2,v2,...]`
///      扁平化形式，反而比 jsonEncode 更脆弱（缺一个元素就错位）。
///   5. ❌ 不审计 `_prefs!` vs `_prefs?` ——R125/R126/R127 已 doc 化 init 序列；
///      `_prefs!` (storage_service) 与 `_prefs?` (log_cache_service) 的差异是
///      "init 是否在调用前 await" 的语义差，不是类型轴问题。
class StorageService {
  /// 单例模式
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// 测试钩子：子类用于构造可注入的 fake。生产路径仍走单例。
  @visibleForTesting
  StorageService.forTesting();

  SharedPreferences? _prefs;

  final AppPathsService _paths = AppPathsService();

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取应用数据目录
  Future<String> getDataDir() async {
    return _paths.getDataDir();
  }

  // ===== 历史记录 =====

  /// 获取源 URL 历史记录
  Future<List<String>> getSourceUrlHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('source_url_history') ?? [];
  }

  /// 保存源 URL 历史记录
  Future<void> saveSourceUrlHistory(List<String> urls) async {
    await _ensureInit();
    final normalized = normalizeMruHistory(urls, maxLength: 20);
    await _prefs!.setStringList('source_url_history', normalized);
  }

  /// 添加源 URL 到历史记录
  Future<void> addSourceUrlToHistory(String url) async {
    final history = await getSourceUrlHistory();
    final next = promoteToMruFront(history, url, maxLength: 20);
    await saveSourceUrlHistory(next);
  }

  /// 获取 switch 目标分支历史记录
  Future<List<String>> getSwitchBranchHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('switch_branch_history') ?? [];
  }

  /// 保存 switch 目标分支历史记录
  Future<void> saveSwitchBranchHistory(List<String> urls) async {
    await _ensureInit();
    final normalized = normalizeMruHistory(urls, maxLength: 20);
    await _prefs!.setStringList('switch_branch_history', normalized);
  }

  /// 添加 switch 目标分支到历史记录
  Future<void> addSwitchBranchToHistory(String url) async {
    final history = await getSwitchBranchHistory();
    final next = promoteToMruFront(history, url, maxLength: 20);
    await saveSwitchBranchHistory(next);
  }

  /// 获取精简模式目标 SVN URL 历史记录
  Future<List<String>> getTargetUrlHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('target_url_history') ?? [];
  }

  /// 保存精简模式目标 SVN URL 历史记录
  Future<void> saveTargetUrlHistory(List<String> urls) async {
    await _ensureInit();
    final normalized = normalizeMruHistory(urls, maxLength: 20);
    await _prefs!.setStringList('target_url_history', normalized);
  }

  /// 添加精简模式目标 SVN URL 到历史记录
  Future<void> addTargetUrlToHistory(String url) async {
    final history = await getTargetUrlHistory();
    final next = promoteToMruFront(history, url, maxLength: 20);
    await saveTargetUrlHistory(next);
  }

  /// 获取工作副本历史记录
  Future<List<String>> getTargetWcHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('target_wc_history') ?? [];
  }

  /// 保存工作副本历史记录
  Future<void> saveTargetWcHistory(List<String> wcs) async {
    await _ensureInit();
    final normalized = normalizeMruHistory(wcs, maxLength: 20);
    await _prefs!.setStringList('target_wc_history', normalized);
  }

  /// 添加工作副本到历史记录
  Future<void> addTargetWcToHistory(String wc) async {
    final history = await getTargetWcHistory();
    final next = promoteToMruFront(history, wc, maxLength: 20);
    await saveTargetWcHistory(next);
  }

  /// 获取最后选择的源 URL
  Future<String?> getLastSourceUrl() async {
    await _ensureInit();
    return _prefs!.getString('last_source_url');
  }

  /// 保存最后选择的源 URL
  Future<void> saveLastSourceUrl(String url) async {
    await _ensureInit();
    await _prefs!.setString('last_source_url', url);
  }

  /// 获取最后选择的工作副本
  Future<String?> getLastTargetWc() async {
    await _ensureInit();
    return _prefs!.getString('last_target_wc');
  }

  /// 保存最后选择的工作副本
  Future<void> saveLastTargetWc(String wc) async {
    await _ensureInit();
    await _prefs!.setString('last_target_wc', wc);
  }

  /// 获取最后选择的精简模式目标 SVN URL
  Future<String?> getLastTargetUrl() async {
    await _ensureInit();
    return _prefs!.getString('last_target_url');
  }

  /// 保存最后选择的精简模式目标 SVN URL
  Future<void> saveLastTargetUrl(String url) async {
    await _ensureInit();
    await _prefs!.setString('last_target_url', url);
  }

  // ===== 任务队列 =====

  /// 获取队列文件路径
  Future<String> _getQueueFilePath() async {
    return _paths.getQueueFilePath();
  }

  /// 加载任务队列
  Future<List<MergeJob>> loadQueue() async {
    try {
      final queueFile = File(await _getQueueFilePath());

      if (!await queueFile.exists()) {
        return [];
      }

      final content = await queueFile.readAsString();
      // R105：JSON schema / 字段名契约锁在 [parseQueueJson] 测试上
      final jobs = parseQueueJson(content);

      final recovery = recoverInterruptedJobs(jobs);
      final resetJobs = recovery.jobs;

      if (recovery.recoveredCount > 0) {
        AppLogger.storage.warn(
          '检测到 ${recovery.recoveredCount} 个中断任务，已恢复为暂停状态，等待人工继续或终止',
        );
      }

      AppLogger.storage.info('已加载 ${resetJobs.length} 个任务');
      return resetJobs;
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载队列失败', e, stackTrace);
      return [];
    }
  }

  /// 保存任务队列
  Future<void> saveQueue(List<MergeJob> jobs) async {
    try {
      final queueFile = File(await _getQueueFilePath());

      // R105：JSON schema / 缩进格式锁在 [serializeQueueJson] 测试上
      final content = serializeQueueJson(jobs);
      await queueFile.writeAsString(content);

      AppLogger.storage.info('已保存 ${jobs.length} 个任务');
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存队列失败', e, stackTrace);
    }
  }

  // ===== 设置 =====

  /// 获取默认最大重试次数
  Future<int> getDefaultMaxRetries() async {
    await _ensureInit();
    return _prefs!.getInt('default_max_retries') ?? kDefaultMaxRetries;
  }

  /// 保存默认最大重试次数
  Future<void> saveDefaultMaxRetries(int value) async {
    await _ensureInit();
    await _prefs!.setInt('default_max_retries', value);
  }

  /// 获取合并后、提交前执行的本地校验脚本路径。
  Future<String> getMergeValidationScriptPath() async {
    await _ensureInit();
    return normalizeMergeValidationScriptPath(
      _prefs!.getString('merge_validation_script_path'),
    );
  }

  /// 保存合并校验脚本路径。传入空白时清除配置，下次读取回落默认脚本路径。
  Future<void> saveMergeValidationScriptPath(String? value) async {
    await _ensureInit();
    final normalized = normalizeMergeValidationScriptPath(value);
    if (normalized == kDefaultMergeValidationScriptPath &&
        (value == null || value.trim().isEmpty)) {
      await _prefs!.remove('merge_validation_script_path');
      return;
    }
    await _prefs!.setString('merge_validation_script_path', normalized);
  }

  /// 获取是否默认使用临时精简工作副本。
  Future<bool> getUseTemporarySparseWorkingCopy() async {
    await _ensureInit();
    return _prefs!.getBool('use_temporary_sparse_working_copy') ?? false;
  }

  /// 保存是否默认使用临时精简工作副本。
  Future<void> saveUseTemporarySparseWorkingCopy(bool value) async {
    await _ensureInit();
    await _prefs!.setBool('use_temporary_sparse_working_copy', value);
  }

  // ===== 窗口布局 =====

  /// 获取上次保存的桌面窗口位置和大小。
  Future<Rect?> getWindowBounds() async {
    await _ensureInit();
    final raw = _prefs!.getString(kWindowBoundsKey);
    final bounds = parseWindowBoundsJson(raw);
    if (raw != null && bounds == null) {
      AppLogger.storage.warn('窗口布局配置无效，已忽略');
    }
    return bounds;
  }

  /// 保存桌面窗口位置和大小。
  Future<void> saveWindowBounds(Rect bounds) async {
    await _ensureInit();
    final json = windowBoundsToJson(bounds);
    await _prefs!.setString(kWindowBoundsKey, jsonEncode(json));
  }

  // ===== 提交者过滤历史 =====

  /// 获取提交者过滤历史记录（最多 5 条）
  Future<List<String>> getAuthorFilterHistory() async {
    await _ensureInit();
    final history = _prefs!.getStringList('author_filter_history') ?? [];
    return history.take(5).toList();
  }

  /// 添加提交者到过滤历史记录
  Future<void> addAuthorToFilterHistory(String author) async {
    final trimmed = author.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _ensureInit();
    final history = await getAuthorFilterHistory();
    final limitedHistory = promoteToMruFront(history, trimmed, maxLength: 5);
    await _prefs!.setStringList('author_filter_history', limitedHistory);
    AppLogger.storage.info(
      '已添加提交者到过滤历史: $trimmed（共 ${limitedHistory.length} 条）',
    );
  }

  /// 获取最后使用的提交者过滤值
  Future<String?> getLastAuthorFilter() async {
    await _ensureInit();
    return _prefs!.getString('last_author_filter');
  }

  /// 保存最后使用的提交者过滤值
  Future<void> saveLastAuthorFilter(String author) async {
    if (author.trim().isEmpty) {
      return;
    }
    await _ensureInit();
    await _prefs!.setString('last_author_filter', author.trim());
  }

  /// 获取最后使用的标题过滤值
  Future<String?> getLastTitleFilter() async {
    await _ensureInit();
    return _prefs!.getString('last_title_filter');
  }

  /// 保存最后使用的标题过滤值
  Future<void> saveLastTitleFilter(String title) async {
    if (title.trim().isEmpty) {
      return;
    }
    await _ensureInit();
    await _prefs!.setString('last_title_filter', title.trim());
  }

  /// 获取最后使用的消息过滤值
  Future<String?> getLastMessageFilter() async {
    await _ensureInit();
    return _prefs!.getString('last_message_filter');
  }

  /// 保存最后使用的消息过滤值
  Future<void> saveLastMessageFilter(String message) async {
    if (message.trim().isEmpty) {
      return;
    }
    await _ensureInit();
    await _prefs!.setString('last_message_filter', message.trim());
  }

  // ===== 预加载设置 =====

  /// 获取预加载设置（扁平化存储，不再使用嵌套 JSON）
  Future<Map<String, dynamic>> getPreloadSettings() async {
    await _ensureInit();
    final defaults = defaultPreloadSettingsMap();
    return {
      'enabled':
          _prefs!.getBool('preload_enabled') ?? defaults['enabled'] as bool,
      'stop_on_branch_point': _prefs!.getBool('preload_stop_on_branch_point') ??
          defaults['stop_on_branch_point'] as bool,
      'max_days':
          _prefs!.getInt('preload_max_days') ?? defaults['max_days'] as int,
      'max_count':
          _prefs!.getInt('preload_max_count') ?? defaults['max_count'] as int,
      'stop_revision': _prefs!.getInt('preload_stop_revision') ??
          defaults['stop_revision'] as int,
      'stop_date': _prefs!.getString('preload_stop_date') ??
          defaults['stop_date'] as String?,
    };
  }

  /// 获取预加载设置的强类型形态。
  ///
  /// 直接把 [getPreloadSettings] 的扁平 map 喂进 `PreloadSettings.fromJson`，
  /// 让"读"侧和"写"侧（settings_screen 已改用 `toJson()`）走同一份 json_serializable
  /// 契约——避免调用方手工挑字段重建时漏掉 `stop_revision` / `stop_date` 这类隐性 bug。
  Future<PreloadSettings> getPreloadSettingsTyped() async {
    final map = await getPreloadSettings();
    return PreloadSettings.fromJson(map);
  }

  /// 保存预加载设置（扁平化存储，不再使用嵌套 JSON）
  Future<void> savePreloadSettings(Map<String, dynamic> settings) async {
    await _ensureInit();

    // 把"哪些 key 要写、写什么类型"这一段决策抽到纯函数 buildPreloadWriteOps，
    // 这里只负责把指令分发到 SharedPreferences。
    final ops = buildPreloadWriteOps(settings);
    for (final op in ops) {
      switch (op.kind) {
        case PreloadWriteOpKind.setBool:
          await _prefs!.setBool(op.key, op.value as bool);
          break;
        case PreloadWriteOpKind.setInt:
          await _prefs!.setInt(op.key, op.value as int);
          break;
        case PreloadWriteOpKind.setString:
          await _prefs!.setString(op.key, op.value as String);
          break;
        case PreloadWriteOpKind.removeKey:
          await _prefs!.remove(op.key);
          break;
      }
    }

    if (_prefs!.containsKey('preload_settings')) {
      // R124 mutator 二档判据：`_prefs!.remove('preload_settings')` 是 Map.remove
      // 的**档 1**——key 是**常量字面量字符串**'preload_settings'，不由 lookup
      // 决定。这是 R104 prefs 历史迁移路径专项审计 doc 化的同一行，从 mutator
      // 视角看是"必然清理同一 key"的档 1 操作；R104 视角是"清理旧格式数据"的
      // 持久化契约。两个 doc 维度互不冲突——同一行可承载多重 audit 标记。
      await _prefs!.remove('preload_settings');
    }

    AppLogger.storage.info('已保存预加载设置');
  }

  /// 获取预加载是否启用
  Future<bool> getPreloadEnabled() async {
    await _ensureInit();
    return _prefs!.getBool('preload_enabled') ??
        defaultPreloadSettingsMap()['enabled'] as bool;
  }

  /// 保存预加载是否启用
  Future<void> savePreloadEnabled(bool enabled) async {
    await _ensureInit();
    await _prefs!.setBool('preload_enabled', enabled);
  }

  /// 获取预加载停止条件：到达分支点
  Future<bool> getPreloadStopOnBranchPoint() async {
    await _ensureInit();
    return _prefs!.getBool('preload_stop_on_branch_point') ??
        defaultPreloadSettingsMap()['stop_on_branch_point'] as bool;
  }

  /// 获取预加载停止条件：天数限制
  Future<int> getPreloadMaxDays() async {
    await _ensureInit();
    return _prefs!.getInt('preload_max_days') ??
        defaultPreloadSettingsMap()['max_days'] as int;
  }

  /// 获取预加载停止条件：条数限制
  Future<int> getPreloadMaxCount() async {
    await _ensureInit();
    return _prefs!.getInt('preload_max_count') ??
        defaultPreloadSettingsMap()['max_count'] as int;
  }

  /// 获取预加载停止条件：指定版本
  Future<int> getPreloadStopRevision() async {
    await _ensureInit();
    return _prefs!.getInt('preload_stop_revision') ??
        defaultPreloadSettingsMap()['stop_revision'] as int;
  }

  /// 获取预加载停止条件：指定日期
  Future<String?> getPreloadStopDate() async {
    await _ensureInit();
    return _prefs!.getString('preload_stop_date');
  }

  // ===== 私有方法 =====

  Future<void> _ensureInit() async {
    if (_prefs == null) {
      await init();
    }
  }
}
