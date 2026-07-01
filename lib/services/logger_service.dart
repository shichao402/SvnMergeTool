/// 统一日志服务
///
/// 提供统一的日志输出接口，包含：
/// - 统一的日志格式（时间戳 + 级别 + 消息）
/// - 日志级别控制（debug, info, warn, error）
/// - 日志持久化到应用支持目录下的 logs/
/// - 开发/生产环境区分
/// - 自动日志清理（保留最近10个文件，单个<10MB，总大小<50MB）

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'app_paths_service.dart';

/// 日志级别
///
/// **R139 AppLogger log level 维度协议审计**（doc-only，0 行为变更）：
/// 接续 R138 namespace（域）维度，R139 切到"档位（量）"维度——前序 R136 cancel
/// signal × R137 error signal × R138 log namespace 锁定信号家族「时机/channel/
/// 命名」三维后，R138/R139 共同绕同一 logger surface 上的两条正交轴
/// （`域 × 量`）做二维闭合。三档框架第 19 次复用，第 3 次维度切换（继 R137 量→质、
/// R138 质→域 之后，R139 域→量 回归）——证明 N-tuple invariance 模板对**轴序**
/// 不敏感（环形闭合）。
///
/// **4 档 lib/ 实际分布**（lib/ 全量扫描，已剥离 doc/comment 行）：
/// - `debug` → ~7 callsites / 4 文件：log_file_cache_service(3) + log_sync_service(1)
///   + mergeinfo_cache_service(1) + log_cache_service(1) + svn_xml_parser(1)。
///   **极稀**——只在缓存命中/未命中等高频路径开发期跟踪用。
/// - `info` → ~188 callsites / 15 文件：日常业务正常分支主导（log_sync(69) +
///   log_cache(30) + main_screen_v3(6) + storage(4) + main(10) + ...）。
/// - `warn` → ~24 callsites / 9 文件：可恢复异常 + 降级路径（log_cache(8) +
///   svn_xml_parser(5) + mergeinfo_cache(2) + svn_service/log_sync(2 each) + ...）。
/// - `error` → ~81 callsites / 15 文件：catch 块内 fail-loud（log_cache(31) +
///   main_screen_v3(14) + mergeinfo_cache(6) + svn_service(5) + svn_xml_parser(4)
///   + main(4) + log_sync(3) + app_state(3) + ...）。
///
/// **入口签名 4 档分化（L1 签名档位律）**：
/// - `debug(message, [StackTrace?])` ——唯一接受 stackTrace 但**不接** error 对象。
///   理由：debug 用作开发期上下文打印，传 error 已经超出 debug 语义、那应升级为 error。
/// - `info(message)` ——纯消息，无附属。任何附属元数据（异常/堆栈）都隐含"已偏离正常"，
///   该升档。
/// - `warn(message)` ——同 info，纯消息。warn 表达"可继续但需关注"，传 error 等于
///   承认不可恢复、应升 error。
/// - `error(message, [Object? error, StackTrace? stackTrace])` ——三参，唯一接 error 对象。
/// L1 把"信息密度"绑死到"档位语义"——高档容许更多附属、低档拒绝附属，签名即合同。
///
/// **L2 kDebugMode 分流律**：`minLevel = kDebugMode ? LogLevel.debug : LogLevel.info`。
/// production build 中 debug 档被静默剥离（`shouldLogAtLevel` 走 false 短路），
/// info/warn/error 三档持续输出。**为什么 debug 默认上限**：debug 用于开发期跟踪，
/// 进 release 后需要的是"业务流水"（info）+"异常审计"（warn/error），跟踪段噪音。
///
/// **L3 error 携带 cause 完整律（与 R137 C1/C3 接合）**：catch (e, stackTrace) 块
/// 内调用 `.error(...)` 时**必须**透传 `(e, stackTrace)` 第二/三参。豁免场景必
/// 须明文标注，仅 2 类合法豁免：
/// - **CLI stderr 字符串豁免**——形如 `'操作失败: ${result.stderr}'`，stderr 是
///   子进程输出而非 dart 异常，无堆栈可携带（main_screen_v3:1627/1695/1727 + 等
///   ~10 处属于此类）。
/// - **状态断言豁免**——非 catch 块内的"事实陈述型 error"（如 log_cache_service:1060
///   "数据库中缺少 source_info 记录"），调用栈即栈信息、无独立异常对象。
/// 当前 lib/ 81 个 error 站点中，~67 处带 stackTrace（catch 块出口），剩余 ~14
/// 处属上述 2 类豁免——L3 锁定 catch+error 必带堆栈，违反 = 信号丢失。
///
/// **L4 量轴档位穷尽闭合律**：`{debug, info, warn, error}` 4 档**穷尽**——不存在
/// `trace` / `verbose` / `fatal` / `notice`。新增档必先扩展本 enum + 同步 R139
/// 测试，禁止 ad-hoc `logger._log(LogLevel.someNew, ...)` 走外部入口。与 R138 N3
/// 「tag 集合穷尽闭合」同源——namespace × level 同走"由声明锁定枚举"模板。
///
/// **跨 R138/R139 二维闭合矩阵**（域 × 量；行=域 / 列=档；空 ✓ 表示该 cell 至少 1 callsite）：
/// ```
///                debug  info  warn  error
/// svn              ✓     ✓     ✓     ✓
/// storage          ✓     ✓     ✓     ✓
/// app              .     ✓     .     ✓
/// ui               .     ✓     .     ✓
/// preload          .     ✓     .     ✓
/// config           .     ✓     ✓     ✓
/// merge            .     ✓     .     .  (fanout-by-helper, 单 entry)
/// credential       .     .     .     .  (R138 N4 negative space)
/// ```
/// 第 1/2 行（svn/storage）覆盖全 4 档——属"高耦合 IO 层"特征：debug 用于路径/
/// 命中跟踪，warn 用于降级，error 用于 catch 出口。3-6 行（app/ui/preload/config）
/// 缺 debug + 部分缺 warn，属"orchestration 层"——业务流水主导，仅 catch 出口
/// 报 error。merge / credential 全空属 R138 doc 锁定的 fanout / negative space
/// 模式，与 R139 量轴正交不冲突。
///
/// **故意不做**：
/// 1. 不改 4 档枚举名（trace/fatal 提案被拒：当前业务无场景需要）；
/// 2. 不强制 warn 必须升 error 的"信号合并"（warn 是"可继续"语义、与 error 不可
///    恢复语义有意义区别，强行合并会丢信号）；
/// 3. 不抽 `.errorWith(e, st)` 命名重载——4 档签名差异已经把意图锁定，多入口
///    反而增审计面；
/// 4. 不给 main_screen_v3 那 10 处 stderr-error 强行补 stackTrace——L3 豁免明文化即可。
enum LogLevel {
  debug, // 调试信息
  info, // 一般信息
  warn, // 警告
  error, // 错误
}

/// 把 [DateTime] 格式化成日志行使用的 `HH:MM:SS.mmm` 时间戳。
///
/// 用 `padLeft` 补零，**不依赖 intl**。仅取小时/分钟/秒/毫秒，
/// 不带日期段——日期由日志文件名（`app_<iso>.log`）承载，行级时间戳
/// 只关心一天内的相对时刻，避免每行都重复完整 ISO 增加噪音。
@visibleForTesting
String formatLogTimestamp(DateTime now) {
  return '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

/// 把 [DateTime] 格式化成"文件名安全"的时间戳。
///
/// 协议：先 `toIso8601String()`（如 `2025-05-28T14:23:45.678`），
/// 再把 `:` 替换为 `-`（Windows 文件名禁止 `:`），最后去掉 `.` 后的毫秒段——
/// 文件级粒度精确到秒已足够，且能让人眼直接对比"哪个更新"。
///
/// 在 `_initLogFile` 写 `# Log created at:` header 与 `_archiveLatestLog`
/// 的 fallback 命名两处使用——它们要落到同一份字符串才能让归档时
/// header 解析回填的时间戳与文件名时间戳一致。
@visibleForTesting
String formatLogFileTimestamp(DateTime time) {
  return time.toIso8601String().replaceAll(':', '-').split('.')[0];
}

/// 拼出最终的日志行：`[timestamp] [LEVEL] [TAG    ] message`。
///
/// **格式契约**（被单测显式锁定）：
/// - level 段右补空格至宽度 5（`error` 的长度），让所有级别在控制台对齐；
/// - tag 段右补空格至宽度 8，与现有 `'STORAGE'` / `'PRELOAD'` 等最长 tag 对齐；
/// - 每段用单个 `[ ]` 包裹，段间单个空格分隔，最后接 message。
///
/// **不做**的事：
/// - 不格式化 [timestamp]（由 [formatLogTimestamp] 负责，已是字符串）；
/// - 不裁剪 message（不限长，调用方自己控制）；
/// - 不转义 `]`（tag/message 中如果出现 `]` 会让肉眼解析略乱，但这是历史
///   行为；改成转义会破坏所有现有日志的 grep 习惯）。
@visibleForTesting
String formatLogLine({
  required String timestamp,
  required LogLevel level,
  required String tag,
  required String message,
}) {
  final levelStr = level.name.toUpperCase().padRight(5);
  final tagStr = tag.padRight(8);
  return '[$timestamp] [$levelStr] [$tagStr] $message';
}

/// 是否应该输出指定级别的日志。
///
/// 等价于 `enabled && level.index >= minLevel.index`。抽出来主要是为了
/// 测试可以断言 enabled / minLevel 不同组合下的行为，而不必实例化
/// LoggerService 单例并污染其状态。
@visibleForTesting
bool shouldLogAtLevel({
  required LogLevel level,
  required LogLevel minLevel,
  required bool enabled,
}) {
  return enabled && level.index >= minLevel.index;
}

/// 从 `latest.log` 的内容中找出 `# Log created at: <timestamp>` header 行，
/// 并提取 `<timestamp>` 段。
///
/// **契约**：
/// - 找到第一条匹配立即返回（与原 `_archiveLatestLog` 中 `break` 一致）；
/// - 没有任何匹配 → 返回 null；
/// - 匹配但 `<timestamp>` trim 后为空（如 `# Log created at: `）→ 返回空串
///   `''`，**不**视作 null。这把"格式正确但内容缺失"的故障表面化，
///   原 `_archiveLatestLog` 紧跟着的 `if (timestamp == null || timestamp.isEmpty)`
///   会再走 fallback 逻辑——契约保留不变。
@visibleForTesting
String? extractLogCreatedTimestamp(Iterable<String> lines) {
  const prefix = '# Log created at: ';
  for (final line in lines) {
    if (line.startsWith(prefix)) {
      return line.substring(prefix.length).trim();
    }
  }
  return null;
}

/// 选择不冲突的归档日志文件名。
///
/// 输入 [timestamp]（不含扩展名），返回 `app_<timestamp>.log`；
/// 若 [exists] 谓词对该候选返回 true，则依次尝试 `app_<timestamp>_1.log`、
/// `app_<timestamp>_2.log`...直到 [exists] 返回 false 为止。
///
/// **关键设计**：用谓词注入 [exists] 让函数完全脱离 `dart:io`，调用方
/// 在闭包里捕获目录引用（`(name) => File(path.join(dir, name)).existsSync()`）。
/// 测试不需要碰真实文件系统，只用 `Set<String>` 模拟即可。
///
/// **契约**：
/// - [timestamp] 原样使用（不 trim、不校验），调用方责任；
/// - 序号从 1 开始（与原 `_archiveLatestLog` 的 `var counter = 1; counter++` 一致）；
/// - 序号无上限（极端情况下会一直探测——生产里是文件系统，不会真的冲突几千次）。
@visibleForTesting
String pickArchiveLogFileName({
  required String timestamp,
  required bool Function(String candidate) exists,
}) {
  final base = 'app_$timestamp.log';
  if (!exists(base)) return base;
  var counter = 1;
  while (true) {
    final candidate = 'app_${timestamp}_$counter.log';
    if (!exists(candidate)) return candidate;
    counter++;
  }
}

/// 把 error 对象格式化成日志行的"附属详情"段。
///
/// 模板 `  └─ Error: <error>`，用法是紧跟主日志行下一行展示。
/// 抽出来是为了让模板字面值（`└─`、前导两空格）只存在于一处——以前
/// 在 `LoggerService.error` 内联，未来如果要改成 `  ⤷` 或加色彩需要扫
/// 全文件，现在只改这一处。
@visibleForTesting
String formatErrorDetail(Object error) {
  return '  └─ Error: $error';
}

/// 把 [StackTrace] 格式化成日志行的"附属详情"段。
///
/// 模板 `  └─ StackTrace:\n<stackTrace>`，与 [formatErrorDetail] 配套使用。
/// 注意 stackTrace 段自带换行，`\n<stackTrace>` 会让堆栈紧贴在标签下一行。
@visibleForTesting
String formatStackTraceDetail(StackTrace stackTrace) {
  return '  └─ StackTrace:\n$stackTrace';
}

/// 一条日志归档文件的纯数据描述。
///
/// 把 `dart:io` 的 `File` + `FileStat` 拍扁成 `(path, sizeBytes, modifiedTime)`
/// 三字段——这是 `planLogFilesCleanup` 唯一接受的入参形态，让单测无需在
/// tmp 目录里造真实文件就能跑。
///
/// **契约**：
/// - `path` 原样保留，不做规范化（caller 负责传 absolute path）；
/// - `sizeBytes` 不校验非负——`File.stat().size` 永远 ≥ 0，传负数等于
///   caller 自己有 bug，不替 caller 兜底；
/// - `modifiedTime` 用于 plan 中按时间排序；同毫秒精度的两个文件并列时，
///   sort 保稳定（Dart 默认 stable sort），等价于"输入顺序里靠后的会先被删"。
@visibleForTesting
class LogFileEntry {
  final String path;
  final int sizeBytes;
  final DateTime modifiedTime;

  const LogFileEntry({
    required this.path,
    required this.sizeBytes,
    required this.modifiedTime,
  });
}

/// `planLogFilesCleanup` 的纯决策结果。
///
/// - [toDelete]：应该删除的文件路径列表，**顺序与决策阶段一致**——阶段 1
///   触发的删除会先于阶段 2 / 阶段 3 加入列表。caller 直接 `for path in toDelete:
///   File(path).delete()` 即可。
/// - [keptCount]：决策完成后剩余保留的文件数；用于日志/断言。
/// - [finalTotalSize]：决策完成后剩余文件的总字节数；用于日志/断言。
@visibleForTesting
class LogCleanupPlan {
  final List<String> toDelete;
  final int keptCount;
  final int finalTotalSize;

  const LogCleanupPlan({
    required this.toDelete,
    required this.keptCount,
    required this.finalTotalSize,
  });
}

/// 计算一批 [LogFileEntry] 的字节总量。
///
/// **契约**：
/// - 入参为空 → 返回 `0`（fold 初值；空集合的累加自然为 0，与原 inline 行为一致）。
/// - 入参非空 → 返回 `sum(e.sizeBytes for e in entries)`。
///
/// **设计选择**（R118 唯一的"累加 reduce/fold"helper）：
/// - 用 `fold(0, +)` 而非 `reduce(+)`——后者要求非空，前者天然支持空集合，
///   `planLogFilesCleanup` 在阶段 1/2 的 while 循环里会让 `working` 缩到空，
///   `totalBytes` 必须能保持 `0` 而非抛 `StateError`。
/// - 不做 `sizeBytes >= 0` 校验——与 [LogFileEntry] 契约一致（caller 传负值即
///   bug，不替 caller 兜底）。
/// - **不**抽泛型 `sumBy<T>(List<T>, int Function(T))`——lib 内仅此 1 处需要
///   累加 reduce/fold（见 R118 审计），单点抽象比泛型 helper 更清晰；与 R117
///   "不抽泛型 lookupById"同源理由。
///
/// **与 R116/R117 极值族的对偶**：极值 reduce（`revisionExtremesOf` /
/// `resolveRootTailFromEntries` / `deriveNextJobId`）是"集合→标量"的 max/min；
/// 本 helper 是"集合→标量"的 sum——同抽象层"reduce/fold contract"族姊妹维度。
@visibleForTesting
int totalSizeOf(List<LogFileEntry> entries) {
  return entries.fold(0, (sum, e) => sum + e.sizeBytes);
}

/// **R119（fire-and-forget then/catchError 异步契约审计）档 2 helper**：
/// 让一个 [Future]"静默吞掉"任何 reject 错误。
///
/// **使用前提**（caller 必须满足，否则不应使用本 helper）：
/// 1. caller **故意**不 await 该 future（fire-and-forget），否则应直接 await + try-catch；
/// 2. 错误**不影响**其它子系统——典型场景：日志写文件失败时若再用 logger 报错
///    会触发递归调用 / 死循环，所以"日志写失败"必须就地静默；
/// 3. 错误诊断有**别的通道**——如 logger 的文件写失败，调用方已经通过 `debugPrint`
///    把同一行内容打到控制台，文件写失败不会让用户失去信息。
///
/// **R98 对偶位置**（throw 三档框架 → 异步链三档对偶）：
/// - **档 1（fire-and-forget then 链）**：caller 不 await，错误用 then 链异步处理 +
///   失败时也不能"静默"——见 main.dart:240/244 `loadMergeInfo` 已在内部 try-catch
///   日志化，then 链只串后续动作；
/// - **档 2（catchError 静默吞）= 本 helper**：caller 不 await，错误**故意**丢弃；
///   只有同时满足上述 3 个前提才算合法 档 2 用法；
/// - **档 3（await + try-catch / catchError 旁路）**：caller await，错误进 catchError
///   或外层 try-catch 旁路化（不抛但记日志）——见 main_screen_v3.dart:600/603/608/896。
///
/// **签名故意限定 `Future<void>`**（不接受泛型 `Future<T>`）：
/// - 档 2 前提 1 要求 caller 不 await——既然不消费返回值，唯一合法的入参形态
///   就是 `Future<void>`；放开成 `Future<T>` 会让人误以为可以"先获取 success
///   返回值再决定是否丢错"，与"故意不 await"冲突；
/// - lib 内唯一使用站点（logger `_writeToFile`）签名就是 `Future<void>`；
/// - 实现上避免 `null as T` 在非可空 T（如 `Future<String>`）撞 TypeError。
///
/// **为什么单独抽 helper 而不是继续内联 `.catchError((_) {})`**：
/// - logger_service.dart:547/585/594 三处 inline 的 `.catchError((e) {})` 容易让人
///   误以为是"忘了处理"——抽成命名 helper 后，**意图**（"我故意丢"）被语义化；
/// - 未来若要加观测点（如统计静默吞次数）只需改一处；
/// - 反向 doc 化：reviewer 看到 `silentlyDiscardAsyncError(...)` 就被强制阅读
///   上面 3 个使用前提，比 `(e) {}` 更醒目。
///
/// **不抽更通用版本签名**（与 R117/R118 同源理由）：
/// 仅 logger 内部的 `_writeToFile` 一处需要静默吞，单点抽象比泛型 helper 更清晰。
/// 若未来出现第 2 个合法 档 2 站点，可在此处升级。
@visibleForTesting
Future<void> silentlyDiscardAsyncError(Future<void> future) {
  return future.catchError((Object _) {
    // 故意空实现：见 helper doc 三个前提。
  });
}

/// 给定一批日志归档文件与 3 个阈值，决策应该删除哪些。
///
/// **3 阶段顺序固定（计数 → 总量 → 单文件）**——这就是原 `_cleanupOldLogs` 里
/// 的实现顺序，单测显式锁定。**调换阶段会得到不同结果**（例如：先删超大文件、
/// 再按总量裁剪 → 可能导致总量不再超限就停止，但实际还有"虽小但旧"的文件
/// 应该被裁掉）。把"顺序"作为契约一部分锁定，是为了防止有人觉得"反正都是
/// 删旧的"就把阶段重排。
///
/// **阶段 1（数量超限）**：
/// - 全表按 `modifiedTime` 降序排（最新的在前）；
/// - 当 `entries.length > maxFileCount` 时，**从尾部**移除（最旧的先删）；
/// - 直到 `length == maxFileCount` 为止。
///
/// **阶段 2（总量超限）**：
/// - 在阶段 1 留下的列表上继续；
/// - 当 `totalBytes > maxTotalBytes` 且列表非空时，从尾部移除；
/// - 直到 `totalBytes <= maxTotalBytes` 或列表空为止。
///
/// **阶段 3（单文件超大）**：
/// - 在阶段 2 留下的列表上扫一遍；
/// - 任何一条 `sizeBytes > maxSingleFileBytes` 的删掉，**不管它在排序中的位置**。
/// - 这是"最后一道防线"——前两阶段按时间裁剪，可能漏掉"刚生成但意外巨大"的
///   文件（比如某次崩溃日志）；阶段 3 保证这种文件即使是最新也会被清掉。
///
/// **不**做的事：
/// - 不校验阈值非负——caller 传负值等于"全删"，让症状显眼比静默兜底好；
/// - 不做 path 规范化（与 [LogFileEntry] 的契约一致）；
/// - 不在阶段 1/2 的边界做 `>=` 与 `>` 互换的"友好"调整：原 inline 是 `>`，
///   保留它，避免边界微调引入难以察觉的行为漂移。
@visibleForTesting
LogCleanupPlan planLogFilesCleanup({
  required List<LogFileEntry> entries,
  required int maxFileCount,
  required int maxTotalBytes,
  required int maxSingleFileBytes,
}) {
  // 拷贝一份避免污染调用方
  final working = List<LogFileEntry>.of(entries);
  // 按 modifiedTime 降序：最新在前，最旧在末——尾部弹出 = 删最旧
  working.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

  final toDelete = <String>[];
  int totalBytes = totalSizeOf(working);

  // 阶段 1：数量超限 → 从尾部（最旧）删除
  while (working.length > maxFileCount) {
    final removed = working.removeLast();
    totalBytes -= removed.sizeBytes;
    toDelete.add(removed.path);
  }

  // 阶段 2：总量超限 → 从尾部（最旧）继续删除
  while (totalBytes > maxTotalBytes && working.isNotEmpty) {
    final removed = working.removeLast();
    totalBytes -= removed.sizeBytes;
    toDelete.add(removed.path);
  }

  // 阶段 3：单文件超大 → 整张扫，命中即删
  // 用倒序遍历 + 索引删除，避免边遍历边修改 list 的指针失效问题
  //
  // **R123 removeAt arbitrary-index 二档判据 doc 锁**：
  // 这里的 `removeAt(i)` 是"任意 index 删除"——i 由谓词命中决定、不是固定的 0
  // 或末尾。**故意保留 List**，不改 Queue：
  // - R122 改 Queue 的判据是"恒定从头部 drain（`removeAt(0)`）"；本处 i 是动态
  //   位置，Queue 不暴露 `removeAt(int)` API、根本无法替换；
  // - 倒序遍历 + 索引删除是 List 的标准模式（`removeAt(i)` 是 O(n - i)，倒序时
  //   前部不再被访问、O(n²) 退化不会触发）；
  // - 即使想换数据结构，也只能换 `LinkedList` 而非 `Queue`——但单次扫描场景
  //   引入 LinkedList 反而劣化（缓存不友好），不值得。
  //
  // **判据明文**：`List.removeAt(i)` 在 lib 内分两档——(档 1) i ≡ 0 头部 drain
  // → R122 改 Queue；(档 2) i 由谓词或外部决定 → 保留 List。本处属档 2。
  for (int i = working.length - 1; i >= 0; i--) {
    if (working[i].sizeBytes > maxSingleFileBytes) {
      final removed = working.removeAt(i);
      totalBytes -= removed.sizeBytes;
      toDelete.add(removed.path);
    }
  }

  return LogCleanupPlan(
    toDelete: toDelete,
    keptCount: working.length,
    finalTotalSize: totalBytes,
  );
}

/// 统一日志服务
///
/// **R140 AppLogger output sink 通道协议审计**（doc-only，0 行为变更）：
/// 接续 R138 namespace（域）/ R139 level（量），R140 切到"通道（sink/channel）"
/// 维度——R138/R139 已在同一 logger surface 上沿 `域 × 量` 二维闭合，R140 把
/// 第三轴（**输出通道**）显式列出，logger 平面升至 `域 × 量 × 通道` 三维全集。
/// 三档框架第 20 次复用，第 4 次维度切换（继 R137 量→质 / R138 质→域 /
/// R139 域→量 之后，R140 引入正交新轴 → 形成"双轴循环 + 第三轴扩张"模板）。
///
/// **lib/ sink 全集（2 sink，穷尽闭合）**：
/// - `console sink`（`debugPrint(formatted)`）——同步、无 fail 路径、kDebugMode
///   下控制台/IDE 输出，release build 中 debugPrint 节流但不消失；
/// - `file sink`（`_logFileSink: IOSink?` ←─ `openWrite(FileMode.write)`）——
///   异步、可 fail（OS fd / disk full / permission）、走 `_writeQueue`
///   FIFO 排队 + scheduleMicrotask 延续 + 单 `_isWriting` 互斥锁。
/// 不存在第 3 类 sink（远程上报 / syslog / structured json 输出皆故意未引入）。
///
/// **S1 主路双写律（normal log path）**：
/// 任何 `_log(level, message)` 进入 `_shouldLog` 真分支后，**必须**双写两路 sink：
/// `debugPrint(formatted)` + `silentlyDiscardAsyncError(_writeToFile(formatted))`。
/// **为什么双写**：console 是开发期实时反馈（无 race，立即可见）/ file 是事后
/// 审计追踪（容忍写延迟，靠队列保序）。任一单路缺失 = 信号丢失（仅 console
/// = 无法事后追溯；仅 file = 开发期看不见输出）。
///
/// **S2 error 路径 fanout 律（error 三段双写）**：
/// `error(message, [error, stackTrace])` 在 `_shouldLog` 后**最多**走 3 段
/// 双写——main / errorDetail / stackDetail，每段都同时进 console + file：
/// - 段 1（必走）：`_log(LogLevel.error, message)` 双写 message；
/// - 段 2（条件 `error != null`）：`debugPrint(errorDetail)` 仅 kDebugMode 下走
///   console；`_writeToFile(errorDetail)` 无条件走 file；
/// - 段 3（条件 `stackTrace != null`）：同段 2 模式，`debugPrint` 仅 kDebugMode
///   走 console / file 无条件落盘。
/// **段 2/3 console 路 kDebugMode gate 不对称**：file 路 release build 仍要写
/// （审计需要），console 路 release 不需要冗长 errorDetail/stack 噪音。
///
/// **S3 meta-error sink 单档收敛律（logger 自身错误 → 仅 console）**：
/// logger 内部 4 处 catch 出口（`_initLogFile` 失败 / archive latest.log 失败 /
/// `_cleanupOldLogs` 失败 / `_processWriteQueue` 总 catch + 单 write 失败）
/// **仅**走 `debugPrint(...)` 单档，**禁止**走 file sink。理由：logger 报错若再
/// 走 file 路，会形成"file 写失败 → 报错 → 再写 file → 再失败"的递归无穷循环
/// （`silentlyDiscardAsyncError` 的 R119 档 2 fire-and-forget 也防不住语义环）。
/// debugPrint 是**唯一安全的兜底通道**——同步、无 dependency、不会自递归。
/// **与 S1/S2 反差**：业务路双写（高可见性）/ meta-error 路单写（防递归）。
///
/// **S4 file sink 失败处置律（write-fail 静默吞 + console 兜底）**：
/// `_processWriteQueue` 内单条 `_logFileSink!.writeln(message)` 抛错时，走
/// `debugPrint('写入日志失败: $e')` 单档静默——属 R119 catchError 档 2
/// （fire-and-forget 静默吞），3 个使用前提全满足：
/// 1) 错误**不可恢复**（fd 已损 / disk 已满，重试更糟）；
/// 2) 错误**不影响主流程**（业务方只看 logger 调用返回，不感知 file 状态）；
/// 3) 错误诊断有**别的通道**（console debugPrint 已落字符串）。
/// **关键**：catch 后**继续 while 循环**——单条失败不阻塞队列后续条目，是
/// "失败隔离"原则（与 S3 收敛律协同：file 路单条故障 → 落 console / 不污染队列）。
///
/// **跨 R138/R139/R140 三维全集矩阵**（域 × 量 × 通道；通道列省略，因每 cell
/// 都至少经 console + file 主路双写，仅 meta-error 例外）：
/// - 业务路（S1/S2）：8 域 × 4 档 × 2 通道 = 64 cell（活动）；
/// - meta-error 路（S3/S4）：1 域（logger 自身）× 1 档（隐式 error）× 1 通道
///   （console only）= 1 cell（特例）；
/// 三维全集 = 业务 64 + meta 1 = 65 cell，全部 doc-locked。
///
/// **故意不做**：
/// 1. **不引入第 3 类 sink**（远程 Sentry / 文件 JSON 输出 / syslog 等）——当前 2
///    sink 已覆盖"实时 + 审计"双需求，加 sink 必引入异步链 + 网络依赖 + 失败
///    通道，复杂度回报比不划算；
/// 2. **不把 meta-error 也写 file**——S3 自递归无穷循环风险已经论证，不能为了
///    "对称性"破坏防递归契约；
/// 3. **不抽 `_dualWrite(formatted)` helper**——双写仅 2 路且耦合 silentlyDiscard
///    异步策略，抽 helper 反而把 console-sync / file-async 不对称隐藏掉；
/// 4. **不把 S2 段 2/3 的 console kDebugMode gate 移除**——release 下错误细节
///    噪音是有意压制的，gate 是 Product Decision 不是技术 debt；
/// 5. **不把 file sink 切换到 buffered Stream 写入**——当前 IOSink + queue 已
///    保序 + 失败隔离，切 Stream 等于换通道契约重做。
///
/// **未来候选**：sink 分级（error 升远程上报） / 第 3 sink 引入（结构化 JSON
/// 文件） / sink 出错率监控 / sink × 域 × 量 × 时间四维（trace 时间窗）。
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();

  factory LoggerService() => _instance;

  LoggerService._internal();

  /// 当前日志级别（生产环境可以设置为 info 或 warn）
  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  final AppPathsService _paths = AppPathsService();

  /// 是否启用日志（可以在运行时动态控制）
  bool enabled = true;

  /// 日志标签（模块名）
  String _tag = 'APP';

  /// 日志文件路径
  String? _logFilePath;

  /// 日志文件对象
  IOSink? _logFileSink;

  /// 是否已初始化
  bool _initialized = false;

  /// 日志写入队列（确保顺序写入）
  ///
  /// **R122 复杂度修复**：原来用 `List<String>`，drain loop 中 `removeAt(0)` 是
  /// O(n)（List 是数组实现，删头要把后续全部前移一格），整体 drain 退化为
  /// O(n²)。日志高频写入（如 SVN 大量子进程并发输出）时 GC + 复制成本可观。
  /// 改用 `dart:collection.Queue<String>`（双端链表实现）：`add` / `removeFirst`
  /// 都是 O(1)，drain 回归 O(n)。**为什么是 Queue 而不是 ListQueue 或自实现**：
  /// (1) `Queue` 是抽象接口，工厂构造默认返回 `ListQueue`（环形数组）—— 比单链表
  /// 更 cache-friendly；(2) 暴露 `add/removeFirst/isEmpty/isNotEmpty` 即可，无需
  /// `[i]` 随机访问，`Queue` API 完全够用；(3) 自实现链表会重复 stdlib 工作。
  final Queue<String> _writeQueue = Queue<String>();

  /// 是否正在写入
  bool _isWriting = false;

  /// 最大日志文件数量
  static const int maxLogFiles = 10;

  /// 单个日志文件最大大小（10MB）
  static const int maxLogFileSize = 10 * 1024 * 1024;

  /// 所有日志文件总大小限制（50MB）
  static const int maxTotalLogSize = 50 * 1024 * 1024;

  /// 设置日志标签
  void setTag(String tag) {
    _tag = tag;
  }

  /// 初始化日志文件
  Future<void> _initLogFile() async {
    if (_initialized) return;

    try {
      final logDir = Directory(await _paths.getLogsDir());

      // 使用固定名称 latest.log
      final latestLogPath = path.join(logDir.path, 'latest.log');
      final latestLogFile = File(latestLogPath);

      // 如果 latest.log 已存在，根据第一行时间戳重命名
      if (await latestLogFile.exists()) {
        await _archiveLatestLog(latestLogFile);
      }

      // 创建新的 latest.log
      _logFilePath = latestLogPath;
      _logFileSink = latestLogFile.openWrite(mode: FileMode.write);

      // 写入日志创建时间作为第一行
      final now = DateTime.now();
      final timestamp = formatLogFileTimestamp(now);
      _logFileSink!.writeln('# Log created at: $timestamp');
      _logFileSink!.writeln(
          '# This file will be renamed to app_$timestamp.log on next startup');
      _logFileSink!.writeln('');

      _initialized = true;

      // 清理旧日志文件
      await _cleanupOldLogs(logDir);
    } catch (e, stackTrace) {
      // 如果文件日志初始化失败，不影响控制台日志输出
      // 注意：这里使用 debugPrint 是必要的，因为日志服务本身需要输出错误
      // 这是基础设施层的特殊情况
      debugPrint('日志文件初始化失败: $e\n$stackTrace');
    }
  }

  /// 归档 latest.log 文件
  Future<void> _archiveLatestLog(File latestLogFile) async {
    try {
      // 读取第一行获取时间戳
      final lines = await latestLogFile.readAsLines();
      var timestamp = extractLogCreatedTimestamp(lines);

      // 如果没有找到时间戳，使用文件修改时间
      if (timestamp == null || timestamp.isEmpty) {
        final stat = await latestLogFile.stat();
        timestamp = formatLogFileTimestamp(stat.modified);
      }

      // 重命名为 app_timestamp.log（如冲突自动加序号）
      final logDir = latestLogFile.parent;
      final fileName = pickArchiveLogFileName(
        timestamp: timestamp,
        exists: (name) => File(path.join(logDir.path, name)).existsSync(),
      );
      await latestLogFile.rename(path.join(logDir.path, fileName));
    } catch (e) {
      // 归档失败，直接删除旧文件
      debugPrint('归档 latest.log 失败，删除旧文件: $e');
      try {
        await latestLogFile.delete();
      } catch (_) {}
    }
  }

  /// 清理旧日志文件
  Future<void> _cleanupOldLogs(Directory logDir) async {
    try {
      // 收集所有 'app_*.log' 文件，拍扁成 LogFileEntry 纯数据
      final entries = <LogFileEntry>[];
      await for (final entity in logDir.list()) {
        if (entity is File &&
            entity.path.contains('app_') &&
            entity.path.endsWith('.log')) {
          final stat = await entity.stat();
          entries.add(LogFileEntry(
            path: entity.path,
            sizeBytes: stat.size,
            modifiedTime: stat.modified,
          ));
        }
      }

      // 决策：3 阶段（计数 → 总量 → 单文件）
      final plan = planLogFilesCleanup(
        entries: entries,
        maxFileCount: maxLogFiles,
        maxTotalBytes: maxTotalLogSize,
        maxSingleFileBytes: maxLogFileSize,
      );

      // 执行：按 plan 删除。任一文件删除失败 → 抛到外层 catch（保留原 inline
      // 行为：第一次删除失败会中止后续删除并 debugPrint 一次）
      for (final path in plan.toDelete) {
        await File(path).delete();
      }
    } catch (e, stackTrace) {
      // 注意：这里使用 debugPrint 是必要的，因为日志服务本身需要输出错误
      debugPrint('清理旧日志文件失败: $e\n$stackTrace');
    }
  }

  /// 写入日志到文件（使用队列确保顺序写入）
  void _enqueueWrite(String message) {
    _writeQueue.add(message);
    _processWriteQueue();
  }

  /// 处理写入队列
  Future<void> _processWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty) return;

    _isWriting = true;

    try {
      if (!_initialized) {
        await _initLogFile();
      }

      while (_writeQueue.isNotEmpty && _logFileSink != null) {
        final message = _writeQueue.removeFirst();
        try {
          _logFileSink!.writeln(message);
        } catch (e) {
          // 写入失败，不影响后续写入
          debugPrint('写入日志失败: $e');
        }
      }

      // 批量 flush
      if (_logFileSink != null) {
        await _logFileSink!.flush();
      }
    } catch (e, stackTrace) {
      debugPrint('处理日志队列失败: $e\n$stackTrace');
    } finally {
      _isWriting = false;

      // 如果队列中还有新的日志，继续处理
      if (_writeQueue.isNotEmpty) {
        // 使用 scheduleMicrotask 避免递归调用栈溢出
        scheduleMicrotask(() => _processWriteQueue());
      }
    }
  }

  /// 写入日志到文件（兼容旧接口）
  Future<void> _writeToFile(String message) async {
    _enqueueWrite(message);
  }

  /// 关闭日志文件
  ///
  /// **R120 等待协议档 2：polling + sleep 等待（无信号源时的回退方案）**
  /// `_writeQueue` / `_isWriting` 由多个 producer（write/info/warn/error）异步驱动，
  /// 没有单一 `Completer` 在"队列空且写入完成"时通知 close —— 因此用 polling
  /// 10ms tick 取代信号驱动。**为什么不抽 helper**：档 2 polling 的关键参数（poll
  /// 间隔 10ms / 退出条件 `_writeQueue.isEmpty && !_isWriting`）与本类内部状态紧耦
  /// 合，抽 helper 反而需要把状态作为参数传入、得不偿失。**与 R120 档 3（节流型
  /// sleep）的区分锁**：本档 sleep 是"等到事件发生"的副作用、退出由布尔条件决定；
  /// 档 3 sleep 是"故意降速"的主作用、退出由外部停止信号决定。
  ///
  /// **R121 资源释放协议档 1：真异步等待型**
  /// 本方法是 4 个释放点中**唯一**含真实 `await` 的：先 await polling 等队列排
  /// 干，再 `await flush()` + `await close()` 把 IOSink buffer 落盘。**对称释
  /// 放语义**：caller `await close()` 后必然能保证日志文件已物理落盘——这是档
  /// 1 区别于档 2/档 3 的关键契约（档 2 同步释放无落盘语义；档 3 fire-and-forget
  /// 调用方无法 await）。**幂等机制**：`_logFileSink?.flush()` 用 `?.` 在 null
  /// 上短路 + `_initialized = false` 状态位 —— 重复 close 是 safe noop。**为什么
  /// 不补 try/catch**：flush/close 抛错应向 caller 冒泡（caller 通常是 app
  /// shutdown，错了就让 OS 兜底关 fd）；档 2/档 3 同理无 try/catch，三档**异常
  /// 策略一致**（都让 caller / framework 兜底）。
  ///
  /// **R125 关闭序列约束：四步顺序不可互换**
  /// 本函数体的 4 步必须**严格按当前顺序**执行：
  ///   step 1: poll-drain 队列（`while _writeQueue.isNotEmpty || _isWriting`）
  ///   step 2: `await _logFileSink?.flush()`（IOSink buffer → OS 层）
  ///   step 3: `await _logFileSink?.close()`（OS fd 关闭，最终落盘）
  ///   step 4: `_logFileSink = null` + `_initialized = false`（状态位归零）
  /// **为什么不可互换**：
  /// - step 1 → 2：drain 必须在 flush 前，否则**残留在 _writeQueue 的 pending
  ///   write 永远进不了 IOSink buffer**——flush 只能 flush 已经在 buffer 里的
  ///   字节，未入 buffer 的会被 step 4 的 null-out 永远丢弃。
  /// - step 2 → 3：close 在 flush 前，**OS 层 buffered 字节不会落盘**——dart:io
  ///   IOSink.close 不强制内部 flush（与 Java FileOutputStream.close 不同）。
  /// - step 3 → 4：null-out 在 close 前，**第二次 close 调用会因 _logFileSink
  ///   == null 而 ?. 短路、跳过真正的 close()**——重复 close 静默失败，第一次
  ///   抛错会丢失。当前顺序保证：第一次 close 异常冒泡（强失败语义），第二次
  ///   才是 ?. 短路 noop（幂等语义）。
  /// - step 1 / step 4 之间，step 2/step 3 不可调换：flush 必先于 close（OS
  ///   层 close 后 sink handle 失效，flush 会抛 StateError）。
  /// **故意不抽 helper**：4 步耦合 _writeQueue / _isWriting / _logFileSink /
  /// _initialized 4 个内部状态——抽 helper 等于把全部状态作参数传入，比 inline
  /// 更冗长（与 R121 "档 1 polling 不抽 helper" 同一原则）。
  Future<void> close() async {
    // 等待队列处理完成
    while (_writeQueue.isNotEmpty || _isWriting) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await _logFileSink?.flush();
    await _logFileSink?.close();
    _logFileSink = null;
    _initialized = false;
  }

  /// 格式化日志消息
  String _format(LogLevel level, String message, [String? tag]) {
    return formatLogLine(
      timestamp: formatLogTimestamp(DateTime.now()),
      level: level,
      tag: tag ?? _tag,
      message: message,
    );
  }

  /// 判断是否应该输出日志
  bool _shouldLog(LogLevel level) {
    return shouldLogAtLevel(
      level: level,
      minLevel: minLevel,
      enabled: enabled,
    );
  }

  /// 输出日志
  void _log(LogLevel level, String message, [String? tag]) {
    if (_shouldLog(level)) {
      final formatted = _format(level, message, tag);

      // 输出到控制台
      debugPrint(formatted);

      // 异步写入文件（不阻塞主线程）
      // R119 档 2（catchError 静默吞）：日志写文件失败必须就地丢弃——若改用
      // logger 报错会递归调用 _log → 无限循环；同行内容已 `debugPrint` 到控
      // 制台兜底（满足 helper 的 3 个使用前提）。
      silentlyDiscardAsyncError(_writeToFile(formatted));
    }
  }

  /// Debug 日志（开发调试用）
  void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  /// Info 日志（一般信息）
  void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  /// Warning 日志（警告信息）
  void warn(String message, [String? tag]) {
    _log(LogLevel.warn, message, tag);
  }

  /// Error 日志（错误信息）
  void error(String message,
      [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, tag);

    // 与 _log 一致地受 enabled / minLevel 控制：禁用日志时不应再额外写入
    // error/stackTrace 详情，否则在没有 Flutter binding 的纯单元测试里
    // 会通过 path_provider 触发 ServicesBinding.instance 失败 → 无限重试。
    if (!_shouldLog(LogLevel.error)) return;

    String? errorDetail;
    if (error != null) {
      errorDetail = formatErrorDetail(error);
      if (kDebugMode) {
        debugPrint(errorDetail);
      }
      // 写入文件
      // R119 档 2：理由同 _log——日志报错通道里再失败必须静默。
      silentlyDiscardAsyncError(_writeToFile(errorDetail));
    }

    if (stackTrace != null) {
      final stackDetail = formatStackTraceDetail(stackTrace);
      if (kDebugMode) {
        debugPrint(stackDetail);
      }
      // 写入文件
      // R119 档 2：理由同 _log——日志报错通道里再失败必须静默。
      silentlyDiscardAsyncError(_writeToFile(stackDetail));
    }
  }

  /// 创建带标签的日志记录器
  TaggedLogger tagged(String tag) {
    return TaggedLogger._(this, tag);
  }

  /// 获取日志目录路径
  Future<String> getLogDirectory() async {
    return _paths.getLogsDir();
  }

  /// 获取当前日志文件路径
  String? get currentLogFilePath => _logFilePath;
}

/// 带标签的日志记录器
class TaggedLogger {
  final LoggerService _logger;
  final String _tag;

  TaggedLogger._(this._logger, this._tag);

  void debug(String message, [StackTrace? stackTrace]) {
    _logger.debug(message, _tag);
    if (stackTrace != null) {
      _logger.debug('Stack trace:\n$stackTrace', _tag);
    }
  }

  void info(String message) => _logger.info(message, _tag);
  void warn(String message) => _logger.warn(message, _tag);
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.error(message, _tag, error, stackTrace);
  }
}

/// 全局日志实例（便捷访问）
final logger = LoggerService();

/// 预定义的模块日志记录器
///
/// **R138 AppLogger tag namespace 协议审计**（doc-only，0 行为变更）：
/// 把"日志命名空间"作为审计维度——前序 R85-R137 全部沿"档位（量）/ channel（质）"
/// 维度递推，R138 切到"namespace（域）"维度，证明 N-tuple invariance 模板对维度
/// 类型继续不敏感（继 R137 量→质切换之后，R138 是质→域切换，三档框架第 18 次复用）。
///
/// **8 个 tag 全集 + 文件域 mapping**（lib/ 全量扫描结果，统计已剥离 doc/comment 行）：
/// - `svn` (SVN) → 4 文件 / 102 callsites：log_sync_service(75) + svn_service(11) +
///   svn_xml_parser(10) + working_copy_manager(6)。**SVN CLI 直接交互层**。
/// - `storage` (STORAGE) → 5 文件 / 116 callsites：log_cache_service(70) +
///   mergeinfo_cache_service(21) + log_filter_service(10) + log_file_cache_service(8) +
///   storage_service(7)。**所有 cache + persistence service 共享 tag**——这是 N2
///   shared-tag 唯一允许场景（同 domain 多服务）。
/// - `app` (APP) → 3 文件 / 27 callsites：main(15) + app_state(11) + version_service(1)。
///   **应用 lifecycle / 启动 / 全局 state**。
/// - `ui` (UI) → 2 文件 / 22 callsites：main_screen_v3(20) + settings_screen(2)。
///   **screens/ 子树**。
/// - `preload` (PRELOAD) → 1 文件 / 16 callsites：preload_service。
///   **专属 service，单文件 tag**。
/// - `config` (CONFIG) → 1 文件 / 10 callsites：config_service。**专属 service**。
/// - `merge` (MERGE) → 1 文件 / 1 callsite：merge_execution_state.`_appendLog:1694`。
///   **fanout-by-helper 模式**——表面只 1 处直接调用，但内部经 `_appendLog` helper
///   被 ~75 处业务调用复用，是"helper-funneled tag"模式（与其他 tag 的"直接调用"
///   分布形态不同）。
/// - `credential` (CRED) → **0 文件 / 0 callsites**。**M4 negative space invariant
///   首次跨轮复用**（R137 M4 在 channel 维度首次形式化"必须 NOT 存在"，R138 在
///   namespace 维度复用此模板——`credential` tag 故意定义但故意不用，是预留给未来
///   独立认证子系统的 namespace bookmark；当前认证日志混在 `svn` tag 内，由
///   svn_service 调用层做信号过滤。若未来抽出 CredentialService 独立服务则启用）。
///
/// **跨 tag 4 不变量 N1/N2/N3/N4**（namespace 维度首次形式化）：
/// - **N1 文件 tag 单一性律** ——一个 lib 文件内所有 AppLogger 调用必使用同一个
///   tag（已扫描验证：12/13 active 文件 100% 单一 tag；唯一例外是 main.dart 的
///   `AppLogger.error` 4 处出现在 doc 注释里、非真实 callsite）。违反 N1 = 文件
///   职责分裂信号（应拆为多文件而不是多 tag）。
/// - **N2 跨文件 tag 共享时机律** ——同一 tag 跨文件共享当且仅当文件属于同一
///   domain（例如 `storage` tag 共享于 5 个 cache/persistence service 是合法的，
///   因它们同属"持久化与缓存"domain；但 ui tag 不应被 service 文件使用）。
///   shared-tag 的合法判据 = 文件 domain 同构，而非文件路径就近。
/// - **N3 tag 集合穷尽闭合律** ——AppLogger 暴露的 tag 集合 = lib/ 实际使用 tag
///   集合 ∪ {credential 预留 bookmark}。**新增 tag 必先在 AppLogger 类声明**——
///   禁止 ad-hoc `logger.tagged('NEW_TAG')`（grep-locked: lib/ 内 0 处直接
///   `.tagged(` 字面量）。
/// - **N4 namespace 故意空 = 决策 doc 化律**（继承 R137 M4）——`credential` 0 处
///   使用必须有 doc 注释解释"为什么定义但不用"，否则被巡检命中为遗留代码。
///
/// **与既往审计接合面**：
/// - R94 日志路径 helper-vs-inline ↔ R138 logger 入口 helper（AppLogger.X.info）：
///   都形成"统一入口避免散点"模式，R94 锁路径渲染、R138 锁 tag 选择。
/// - R98 throw 三档（exception channel）↔ R138 namespace 8 域：信号 channel
///   与日志 namespace 是同一审计框架在两个维度的实例化。
/// - R136 cancel signal × R137 error signal × R138 log namespace = 信号家族三维
///   完整闭合（生产时机 / 消费 channel / 命名归宿）。
/// - merge_execution_state `_appendLog` helper 的 fanout-by-helper 模式 ↔ R119
///   档 2 helper 抽离的判据（intent 显式可见）：`_appendLog` 把 ~75 处业务日志
///   funnel 到单点 `AppLogger.merge.info`，让 reviewer 只需审计 1 处 callsite
///   就能确认整个 provider 的 tag 归属——比 75 处直接调用更易审计。
///
/// **故意不做**：
/// 1. 不引入运行时 tag 校验（dart 编译期常量字段已经天然限定）；
/// 2. 不把 `credential` tag 删除（保留 namespace bookmark 比拆改 service 边界更稳）；
/// 3. 不为 main.dart 等多 domain 文件拆分 tag（它内含 R137 error boundary
///    + 应用 lifecycle，是 app domain 内部混合，符合 N2 同 domain 共享）；
/// 4. 不引入 log level 维度审计（与 namespace 正交，留给未来轮次）；
/// 5. 不引入 structured logging / contextual MDC（当前 tag 字符串足够）。
class AppLogger {
  static final svn = logger.tagged('SVN');
  static final config = logger.tagged('CONFIG');
  static final credential = logger.tagged('CRED');
  static final storage = logger.tagged('STORAGE');
  static final merge = logger.tagged('MERGE');
  static final ui = logger.tagged('UI');
  static final app = logger.tagged('APP');
  static final preload = logger.tagged('PRELOAD');
}
