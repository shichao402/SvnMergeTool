/// 固定四步执行视图
///
/// 在执行阶段展示标准合并步骤，支持查看每一步的实时状态与快照。
library;

import 'package:flutter/material.dart';

import '../../execution/executor_status.dart';
import '../../execution/step_snapshot.dart';
import '../../providers/merge_execution_state.dart';

/// 步骤卡片视觉状态。来自 snapshot 状态 + executor 状态 + isCurrent 三者综合判定。
///
/// 公开此枚举是为了让纯逻辑函数 [resolveStepVisualState] 可被测，
/// 同时也便于 UI 层在 widget tree 之外做断言。
enum StepVisualState {
  pending,
  running,
  completed,
  failed,
  skipped,
}

/// 由 (snapshot, executor status, isCurrent) 推断步骤卡片应该展示的视觉状态。
///
/// 优先级（与原 `_StepCard._resolveVisualState` 完全一致）：
/// 1. 有 snapshot 时按 snapshot.status 直接映射，但 `pending` 不直接返回——
///    继续走下一段（这一点是原代码的细节：snapshot.status==pending 不阻塞回落）。
/// 2. snapshot 为 null 或 status==pending 时，且 `isCurrent=true` 时按 executor
///    status 映射：running→running、paused→failed、completed→completed、idle→pending。
/// 3. 否则一律 pending。
@visibleForTesting
StepVisualState resolveStepVisualState({
  required StepSnapshot? snapshot,
  required ExecutorStatus status,
  required bool isCurrent,
}) {
  if (snapshot != null) {
    switch (snapshot.status) {
      case StepExecutionStatus.completed:
        return StepVisualState.completed;
      case StepExecutionStatus.failed:
        return StepVisualState.failed;
      case StepExecutionStatus.skipped:
        return StepVisualState.skipped;
      case StepExecutionStatus.running:
        return StepVisualState.running;
      case StepExecutionStatus.pending:
        // 不直接 return，让逻辑回落到 isCurrent 分支
        break;
    }
  }

  if (isCurrent) {
    switch (status) {
      case ExecutorStatus.running:
        return StepVisualState.running;
      case ExecutorStatus.paused:
        return StepVisualState.failed;
      case ExecutorStatus.completed:
        return StepVisualState.completed;
      case ExecutorStatus.idle:
        return StepVisualState.pending;
    }
  }

  return StepVisualState.pending;
}

/// 步骤卡片右上角状态 chip 的中文文案。
///
/// `failed` + `executor=paused` + `isCurrent=true` 三者同时成立时显示 "待处理"
/// 而不是 "失败"——表示这是当前等待人工介入的步骤。这与图标分支保持一致。
@visibleForTesting
String stepStatusLabel(
  StepVisualState visualState, {
  required ExecutorStatus status,
  required bool isCurrent,
}) {
  switch (visualState) {
    case StepVisualState.pending:
      return '待执行';
    case StepVisualState.running:
      return '执行中';
    case StepVisualState.completed:
      return '已完成';
    case StepVisualState.failed:
      return status == ExecutorStatus.paused && isCurrent ? '待处理' : '失败';
    case StepVisualState.skipped:
      return '已跳过';
  }
}

/// 步骤卡片右上角 [_StatusChip] 的 hover tooltip。
///
/// **进度披露第十一层（Step 5→...→14→15）**：[stepStatusLabel] 在 `failed + paused +
/// isCurrent` 档位**主动把 "失败" 重写为 "待处理"** —— 用户在 chip 上看到的是 "待处理"
/// 三个字，但底层状态实际仍是 `failed`。chip 的颜色 / 图标都同步切换到 paused 语义
/// （橙色 + handyman_outlined），导致"这是失败步骤，但当前流程被暂停等待人工"这条
/// **复合信息**在 chip 表面完全不可见。
///
/// 本 tooltip 仅在该重写档位触发，浮出 `'步骤失败，等待人工继续/跳过/终止'` 一行
/// 还原完整语义；其它档位（pending / running / completed / skipped / 普通 failed）
/// chip 文本与底层状态语义一致 → 返回 `''`，由 caller `isEmpty` 检查决定是否包
/// [Tooltip]，与 Step 8/9/10/11/12/13/14 的 empty-string 契约同源。
///
/// **为什么"普通 failed"（非 paused）不补 tooltip**：chip 显示 "失败" 与底层 `failed`
/// 语义直接对齐，无重写、无信号丢失 → 与 Step 13 `stepDetailTooltip` single-line
/// dedup 同源（"helper 已渲染等价信息 → tooltip 不重复"）。
///
/// **为什么不展开 ExecutorStatus 名**：`paused` 维度由 `_StatusChip` 的 handyman 图标
/// + 橙色调色板已经 dual-encode；tooltip 重点在还原"failed → 待处理"这个**字符串**重写
/// 丢失，而非状态枚举名。强行展示 `'ExecutorStatus.paused'` 维度是技术细节泄漏。
///
/// **为什么不复用 [statusActionHint] / job 系 helper**：那批 helper 是**任务级**操作建议
/// （`继续/跳过/终止` 的卡片头部入口），而本 tooltip 的"继续/跳过/终止"是**步骤级**
/// 解释——两者文字接近但维度正交（任务卡 vs 步骤卡），不强行复用，与 Step 13
/// `stepDetailTooltip` 拒绝复用 `formatJobErrorTooltip` 同源决策。
@visibleForTesting
String stepStatusTooltip(
  StepVisualState visualState, {
  required ExecutorStatus status,
  required bool isCurrent,
}) {
  if (visualState != StepVisualState.failed) return '';
  if (status != ExecutorStatus.paused) return '';
  if (!isCurrent) return '';
  return '步骤失败，等待人工继续 / 跳过 / 终止。';
}

/// 步骤卡片状态图标。
///
/// 与 [stepStatusLabel] 同一处特殊：failed + paused + isCurrent → 用 `handyman_outlined`
/// 提示需要人工处理；其它失败用 `error_outline`。
@visibleForTesting
IconData stepStatusIcon(
  StepVisualState visualState, {
  required ExecutorStatus status,
  required bool isCurrent,
}) {
  switch (visualState) {
    case StepVisualState.pending:
      return Icons.schedule;
    case StepVisualState.running:
      return Icons.sync;
    case StepVisualState.completed:
      return Icons.check_circle;
    case StepVisualState.failed:
      return status == ExecutorStatus.paused && isCurrent
          ? Icons.handyman_outlined
          : Icons.error_outline;
    case StepVisualState.skipped:
      return Icons.skip_next;
  }
}

/// 卡片右上角的"耗时/开始时间/处理中"小字。可能返回 null 表示不显示。
///
/// 优先级：
/// 1. snapshot.durationMs 非空 → `${ms}ms`
/// 2. snapshot 非空 → `formatStepTime(snapshot.startTime)`（HH:MM:SS）
/// 3. 当前步骤且 executor 在 running → `'处理中'`
/// 4. 否则 null
@visibleForTesting
String? stepInfoText(
  StepSnapshot? snapshot, {
  required bool isCurrent,
  required ExecutorStatus status,
}) {
  if (snapshot?.durationMs != null) {
    return '${snapshot!.durationMs}ms';
  }
  if (snapshot != null) {
    return formatStepTime(snapshot.startTime);
  }
  if (isCurrent && status == ExecutorStatus.running) {
    return '处理中';
  }
  return null;
}

/// 卡片下方详情文案。
///
/// 优先级（与 `_StepCard._buildDetailText` 完全一致）：
/// 1. snapshot 为 null：当前在跑 → "当前正在执行...." / 当前已暂停 → "等待人工处理...." /
///    其它 → "尚未执行到此步骤。"
/// 2. snapshot.error 非空（trim 后）→ 取错误第一行
/// 3. snapshot.output.data 非空：含 `revision` → "处理 revision rN，输出端口: P"；
///    含 `message` → 直出 message；否则 → "输出端口: P"
/// 4. 否则按 snapshot.status 给一句兜底文案
@visibleForTesting
String stepDetailText(
  StepSnapshot? snapshot, {
  required bool isCurrent,
  required ExecutorStatus status,
}) {
  if (snapshot == null) {
    if (isCurrent && status == ExecutorStatus.running) {
      return '当前正在执行此步骤，执行日志与结果会在完成后写入快照。';
    }
    if (isCurrent && status == ExecutorStatus.paused) {
      return '该步骤已暂停，等待人工处理后继续。';
    }
    return '尚未执行到此步骤。';
  }

  final error = snapshot.error;
  if (error != null && error.trim().isNotEmpty) {
    return error.trim().split('\n').first;
  }

  final output = snapshot.output;
  if (output != null && output.data.isNotEmpty) {
    if (output.data.containsKey('revision')) {
      return '处理 revision r${output.data['revision']}，输出端口: ${output.port}';
    }
    if (output.data.containsKey('message')) {
      return '${output.data['message']}';
    }
    return '输出端口: ${output.port}';
  }

  switch (snapshot.status) {
    case StepExecutionStatus.completed:
      return '步骤已执行完成。';
    case StepExecutionStatus.failed:
      return '步骤执行失败，请查看右侧详情。';
    case StepExecutionStatus.running:
      return '步骤正在执行中。';
    case StepExecutionStatus.skipped:
      return '步骤已被跳过。';
    case StepExecutionStatus.pending:
      return '尚未执行到此步骤。';
  }
}

/// 步骤详情卡 hover tooltip。
///
/// **进度披露第九层（Step 5→6→7→8→9→10→11→12→13）**：扩展到步骤执行视图维度。
/// 现有 [stepDetailText] 在两个位置截断信息：
/// 1. helper 内 `error.trim().split('\n').first` —— 多行 error 只显示第一行；
/// 2. UI 层 `Text(detailText, maxLines: 3, overflow: TextOverflow.ellipsis)` —— 长文本被省略号截掉。
///
/// 本 tooltip 的职责仅是**还原 helper 内部的 error 多行截断**：
/// - snapshot.error trim 后含 `\n` → 返回完整 trim 后 error；
/// - 其它分支（snapshot=null / output / status 兜底）→ 返回 `''`，由 caller `isEmpty`
///   检查决定是否包 [Tooltip]，与 Step 8/9/10/11/12 的 empty-string 契约同源。
///
/// **为什么不还原 maxLines:3 截断**：detailText 单段语义已经是"压缩后的关键信息"
/// （revision / message / 兜底文案），3 行截断只在非 error 分支非常长 message 下才会触发；
/// 这是当前 schema 下的低优先级 case，先聚焦最高价值的 error multiline 还原。
/// 未来如发现 message 截断频繁，可在此扩展。
///
/// **为什么 single-line error 仍返回 ''**：[stepDetailText] 已完整渲染，hover 不应
/// 重复展示同一字符串（与 Step 8 `formatJobErrorTooltip` 同源 dedup 约束）。
@visibleForTesting
String stepDetailTooltip(
  StepSnapshot? snapshot, {
  required bool isCurrent,
  required ExecutorStatus status,
}) {
  if (snapshot == null) return '';
  final error = snapshot.error;
  if (error == null) return '';
  final trimmed = error.trim();
  if (trimmed.isEmpty) return '';
  // 不含换行 → 与 stepDetailText 渲染等价，避免重复
  if (!trimmed.contains('\n')) return '';
  return trimmed;
}

/// 步骤卡片右上角 [_InfoPill] 的 hover tooltip。
///
/// **进度披露第十层（Step 5→6→7→8→9→10→11→12→13→14）**：[stepInfoText] 在四档
/// 状态间切换显示形态：
/// 1. `durationMs != null` → `'${ms}ms'`（**只剩耗时数字**，开始/结束时刻不可见）；
/// 2. `snapshot != null` 但无 durationMs → `'HH:MM:SS'`（开始时间，全可见）；
/// 3. `snapshot == null + isCurrent + running` → `'处理中'`（无更多信息可暴露）；
/// 4. 其它 → `null`（不渲染 pill，无 tooltip 锚点）。
///
/// 本 tooltip 只在档位 (1) 触发——当用户看到 `'250ms'` 这种压缩耗时数字时，hover
/// 浮出三行还原完整时序：
/// ```
/// 开始: 10:30:45
/// 结束: 10:30:46
/// 耗时: 250ms
/// ```
/// 其它三档返回 `''`，caller 用 `isEmpty` 判断不渲染 [Tooltip]，与 Step 8/9/10/11/12/13
/// 的 empty-string 契约同源。
///
/// **为什么档位 (2) 不补 tooltip**：pill 已展示 `startTime` 完整 `HH:MM:SS`，没有
/// `endTime` / `durationMs` 可叠加 → 与 Step 8 `formatJobErrorTooltip` 同源 dedup
/// 约束（"helper 已渲染 → tooltip 不重复"）。
///
/// **为什么档位 (3) 不补 tooltip**：`snapshot == null` 时 lib 拿不到 `startTime` /
/// `endTime`（本来就没快照）—— `'处理中'` 已经是当前 schema 下能给出的所有信息。
///
/// **delegate 到 [formatStepTime]**：开始/结束时刻渲染走唯一时钟时间入口，与
/// pill 文本档位 (2) 同源，避免 `padLeft` 拼接逻辑漂移。
///
/// **不展开"已用时长 estimate"**：`durationMs == null + isCurrent` 场景理论上可计算
/// `DateTime.now().difference(startTime)`，但需要 `now` 注入或 ticker，引入 stateful 维度
/// （重大决策延后；与 Step 12 / R57 schema 限制同律）。
@visibleForTesting
String stepInfoTooltip(
  StepSnapshot? snapshot, {
  required bool isCurrent,
  required ExecutorStatus status,
}) {
  if (snapshot == null) return '';
  final duration = snapshot.durationMs;
  if (duration == null) return '';
  final endTime = snapshot.endTime;
  if (endTime == null) return '';
  return '开始: ${formatStepTime(snapshot.startTime)}\n'
      '结束: ${formatStepTime(endTime)}\n'
      '耗时: ${duration}ms';
}

/// 步骤卡片左下 [_InfoPill]（icon=Icons.fingerprint, text=step.id）的 hover tooltip。
///
/// **进度披露第二十层（Step 5→...→23）**：**`step_execution_view.dart` 维度第三轮收口**
/// （Step 13 detail 行 / Step 14 InfoPill 时序 / 本轮 Step 24 stepId InfoPill），
/// 与 Step 19+20（log_list_panel）/ Step 21+23（pending_panel）/ Step 22（config_bar 双字段）
/// 的"同文件多轮回访"模式同源。step.id（`'prepare'` / `'update'` / `'merge'` / `'commit'`）
/// 是开发者级标识，**用户在卡片上看到 id 但完全看不到该步骤的运行时配置**——`prepare`/`update`/
/// `merge` 三步配置为空（snapshot.config={}），唯独 `commit` 步有运行时配置：
/// 1. `maxRetries: int`（永远存在；out-of-date 重试上限，由 job.maxRetries 决定）；
/// 2. `messageTemplate: String?`（可选；自定义 commit message 模板）。
/// 这两个值是"任务启动时的快照"——后续即便用户改 SettingsScreen 全局默认值也不影响已启动任务，
/// 是有价值的"事后审计"信息。本 tooltip 把 snapshot.config 渲染成 `'配置:\nkey: value\n...'`，
/// hover stepId InfoPill 即可看到该步骤本次执行的实际配置。
///
/// **契约**（与 Step 14 `stepInfoTooltip` empty-string dedup 同源）：
/// - `snapshot == null` → `''`（步骤尚未运行，无 snapshot 即无 config 可暴露）；
/// - `snapshot.config.isEmpty` → `''`（prepare/update/merge 三步走此分支，无 added value）；
/// - 否则 → `'配置:\n${k1}: ${v1}\n${k2}: ${v2}\n...'`（每行一个 entry，**保持 Map 插入顺序**——
///   StepSnapshot.config 是 `Map<String, dynamic>`，Dart 的 LinkedHashMap 保留插入顺序，
///   `_startSnapshot` 内 `if (commit) maxRetries` 在 `if (commit && template != null) messageTemplate`
///   之前，故 maxRetries 永远在 messageTemplate 之前——单测显式锁定该顺序）。
///
/// **为什么不附加 stepTypeId**：当前实现里 `snapshot.stepTypeId == snapshot.stepId == step.id`
/// （见 `_startSnapshot`），与 InfoPill 已渲染的 step.id 字面相等 → 重复展示是噪音，与
/// Step 8/13/14/19/20/21/22/23 的 dedup 契约同源。未来若 step type 与 id 解耦，可按需扩展。
///
/// **为什么用 `\n` 多行而非单行 `key=value, key=value`**：参照 Step 12 `formatJobProgressTooltip`
/// 三段拆分（`已完成 / 当前 / 剩余`）/ Step 14 `stepInfoTooltip` 三行（`开始 / 结束 / 耗时`）/
/// Step 18 `formatFailureBucketTooltip` 双段（`hint\n包含任务: ...`）的"标签 + 内容"行式样——
/// 多行视觉一致、跨 helper 对偶，不引入新格式风格。
///
/// **为什么不 lossy stringify**：直接用 `'$value'`（Dart 默认 toString），不走 jsonEncode 也不
/// 截断长 messageTemplate——单一职责"还原 config"，调用方看到什么就是 snapshot 内的什么；
/// 长模板由 Tooltip widget 自身负责换行渲染，不在 helper 里截断。
@visibleForTesting
String formatStepIdTooltip(StepSnapshot? snapshot) {
  if (snapshot == null) return '';
  final config = snapshot.config;
  if (config.isEmpty) return '';
  final lines = <String>['配置:'];
  config.forEach((key, value) {
    lines.add('$key: $value');
  });
  return lines.join('\n');
}

/// 把 [DateTime] 渲染成 `HH:MM:SS`，每段两位补零。
///
/// **唯一时钟时间渲染入口**（合并执行面板 + 步骤执行视图共用）：
/// 步骤详情卡的"开始 / 结束"时间，单步耗时通常 < 1 天，所以不带日期段，
/// 精度到秒。**不引入 intl 依赖**——保留原 `time.hour.toString().padLeft(2, '0')`
/// 三段拼接的实现，与 [logger_service.dart] 内的 `formatLogTimestamp` 同模式
/// 但语义不同（前者带毫秒、后者不带）——保持两条路径独立，按设计模式 #9
/// 拒绝合并。
///
/// **R90 跨库放弃 `@visibleForTesting`**：本 helper 由 `merge_execution_panel.dart`
/// 跨库调用（line 745 `_formatTime` wrapper）；R57 抽时仅本库使用，加了注解；
/// R90 巡检发现 `merge_execution_panel.dart` 内有同实现的 `formatStepClockTime`
/// duplicate（同样 `@visibleForTesting`，4 个 `padLeft(2, '0')` 拼接逐字相同），
/// 决定收敛到本 helper 并放弃注解。pattern 与 R84 / R88 / R89 一致。
String formatStepTime(DateTime time) {
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  final ss = time.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// 步骤间连接线颜色：snapshot 的 status → 配色。snapshot 为 null 用灰色。
@visibleForTesting
Color stepConnectorColor(StepSnapshot? snapshot) {
  if (snapshot == null) {
    return const Color(0xFFD6DEE2);
  }
  switch (snapshot.status) {
    case StepExecutionStatus.completed:
      return const Color(0xFF2E8B57);
    case StepExecutionStatus.failed:
      return const Color(0xFFD97A2B);
    case StepExecutionStatus.running:
      return const Color(0xFF1E6AA8);
    case StepExecutionStatus.skipped:
      return const Color(0xFF8E99A3);
    case StepExecutionStatus.pending:
      return const Color(0xFFD6DEE2);
  }
}

/// `StepExecutionView` 的布局结果：是否走窄屏（纵向）排版，以及每张卡片的宽度。
///
/// 由 [resolveStepExecutionLayout] 从父级 `LayoutBuilder` 传入的 `maxWidth` 推导。
/// 公开此类型是为了让纯函数可被单测，并避免布局魔术常量散落在 widget tree 里。
@visibleForTesting
class StepExecutionLayout {
  /// 是否使用纵向（compact）布局。`maxWidth < 760` 时为 true。
  final bool isCompact;

  /// 单张步骤卡片的宽度。compact 下随容器宽度伸缩、被 clamp 到 [260, 640]；
  /// wide 下固定 240。
  final double cardWidth;

  const StepExecutionLayout({
    required this.isCompact,
    required this.cardWidth,
  });
}

/// 由父级容器宽度 [maxWidth] 推断步骤视图的布局形态。
///
/// 契约（与原 `StepExecutionView.build` 内联算式完全一致）：
/// - `maxWidth < 760` → compact 纵向布局；卡片宽度 = `(maxWidth - 48).clamp(260, 640)`。
/// - 否则 → 横向布局；卡片宽度固定 240。
///
/// 抽出来是为了把 760 / 48 / 260 / 640 / 240 这几个魔术常量集中到一处、并能直接被
/// 单测覆盖（widget 测试只能间接验证布局结果）。
@visibleForTesting
StepExecutionLayout resolveStepExecutionLayout(double maxWidth) {
  final isCompact = maxWidth < 760;
  final cardWidth = isCompact
      ? (maxWidth - 48).clamp(260.0, 640.0).toDouble()
      : 240.0;
  return StepExecutionLayout(isCompact: isCompact, cardWidth: cardWidth);
}

/// 步骤卡片的 5 色调色板：accent / border / background / chipBackground / text。
///
/// 由 [StepVisualState] 唯一决定，与 widget 树解耦。公开此类型 + 配套的纯函数
/// [resolveStepCardPalette] 是为了把"5 个 visual state × 5 个 const Color"的 25 个
/// 字面量绑定从 `_StepCard._paletteFor` 拎出来锁死——任何人误改一个色，单测会立刻红。
///
/// 与 `JobCardActionSpec` / `LogStatusTagSpec` 同风格：值相等 + hashCode + toString。
@visibleForTesting
class StepCardPalette {
  final Color accent;
  final Color border;
  final Color background;
  final Color chipBackground;
  final Color text;

  const StepCardPalette({
    required this.accent,
    required this.border,
    required this.background,
    required this.chipBackground,
    required this.text,
  });

  @override
  bool operator ==(Object other) {
    if (other is! StepCardPalette) return false;
    return other.accent.toARGB32() == accent.toARGB32() &&
        other.border.toARGB32() == border.toARGB32() &&
        other.background.toARGB32() == background.toARGB32() &&
        other.chipBackground.toARGB32() == chipBackground.toARGB32() &&
        other.text.toARGB32() == text.toARGB32();
  }

  @override
  int get hashCode => Object.hash(
        accent.toARGB32(),
        border.toARGB32(),
        background.toARGB32(),
        chipBackground.toARGB32(),
        text.toARGB32(),
      );

  @override
  String toString() =>
      'StepCardPalette(accent: 0x${accent.toARGB32().toRadixString(16)}, '
      'border: 0x${border.toARGB32().toRadixString(16)}, '
      'background: 0x${background.toARGB32().toRadixString(16)}, '
      'chipBackground: 0x${chipBackground.toARGB32().toRadixString(16)}, '
      'text: 0x${text.toARGB32().toRadixString(16)})';
}

/// 把 [StepVisualState] 翻译成 5 色调色板。
///
/// **契约 — 5 套调色板的字面量与原 `_StepCard._paletteFor` 严格一致**：
/// - `running`：蓝色系（accent=`0xFF1E6AA8`，深蓝主导，传达"正在进行"）
/// - `completed`：绿色系（accent=`0xFF2E8B57`，传达"成功完成"）
/// - `failed`：橙色系（accent=`0xFFD97A2B`，**注意是橙不是红**——与 `paused` 对齐，
///    与 `JobStatus.failed` 卡片用红色刻意分裂。step 失败语义偏"需要人工处理"，更接近"暂停"）
/// - `skipped`：中性灰（accent=`0xFF7A8894`，**比 pending 更亮一档**——已决策跳过，淡出）
/// - `pending`：深灰（accent=`0xFF66747F`，比 skipped 略暗——还未开始但仍占位）
///
/// 注：`pending` / `skipped` 的相对亮度由单测 `pending vs skipped accent 强度对比锁定`
/// 显式锁定（`pending.luminance < skipped.luminance`）。
///
/// 穷举式 switch（无 default）——未来若 [StepVisualState] 加新值，编译器会立刻报错
/// 强制处理新 case（设计模式 #12）。
@visibleForTesting
StepCardPalette resolveStepCardPalette(StepVisualState state) {
  switch (state) {
    case StepVisualState.running:
      return const StepCardPalette(
        accent: Color(0xFF1E6AA8),
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
    case StepVisualState.completed:
      return const StepCardPalette(
        accent: Color(0xFF2E8B57),
        border: Color(0xFFA8D0B7),
        background: Color(0xFFF1FAF4),
        chipBackground: Color(0xFFDFF2E5),
        text: Color(0xFF1E5A39),
      );
    case StepVisualState.failed:
      return const StepCardPalette(
        accent: Color(0xFFD97A2B),
        border: Color(0xFFF0BE90),
        background: Color(0xFFFFF6EE),
        chipBackground: Color(0xFFFCE3CC),
        text: Color(0xFF7A4519),
      );
    case StepVisualState.skipped:
      return const StepCardPalette(
        accent: Color(0xFF7A8894),
        border: Color(0xFFCCD4DA),
        background: Color(0xFFF6F8F9),
        chipBackground: Color(0xFFE8EDF0),
        text: Color(0xFF4F5B64),
      );
    case StepVisualState.pending:
      return const StepCardPalette(
        accent: Color(0xFF66747F),
        border: Color(0xFFD5DDE2),
        background: Color(0xFFFFFFFF),
        chipBackground: Color(0xFFF1F4F6),
        text: Color(0xFF27323A),
      );
  }
}

/// 卡片是否进入"强调态"（边框加粗 / 阴影更重 / 用 accent 色而非 border 色）。
///
/// **契约**：`isCurrent || isSelected` 任一为 true 即返回 true。原 `_StepCard.build`
/// 在 widget 树里**完全相同**地出现三次（决定 border.color、border.width、boxShadow.color），
/// 抽到顶层后三处共用一个变量，未来若改条件（如加 hover 状态判断），改一处即可。
@visibleForTesting
bool isStepCardEmphasized({required bool isCurrent, required bool isSelected}) {
  return isCurrent || isSelected;
}

/// 步骤卡片"强调 + 脉冲"两条独立通道渲染参数的合包。
///
/// **核心契约 — emphasized 与 isCurrent 是两条独立维度**：
/// - **emphasized**（边框通道）：`isCurrent || isSelected` —— 用户点选 / 当前正在跑都加粗，
///   因为两种状态都属于"用户视觉焦点应当在这张卡上"。
/// - **isCurrent**（脉冲通道）：仅当前正在跑 —— 决定阴影 alpha（0.24 vs 0.12）与 blur（24 vs 16）
///   的强弱。"已选但未在跑"（emphasized=true && isCurrent=false）只加粗边框、**不**脉冲发光，
///   保持"焦点指示"与"运行指示"语义分裂。
///
/// 4 种 (emphasized, isCurrent) 组合：
/// - (false, false)：默认态——细 border 色、淡阴影。
/// - (true, false)：已选未跑——粗 accent 色边框、阴影色用 accent 但 alpha/blur 仍是淡档。
/// - (false, true)：理论上不可达——`isCurrent=true` 时 `emphasized` 必为 true（因 isCurrent → emphasized）。
///   保留此组合不抛异常是为单测可断言"该路径出现时仍能工作"，并暴露 caller 端不变量错误。
/// - (true, true)：当前在跑——粗 accent 色边框、阴影色 accent + 浓档 alpha/blur。
///
/// **此前所在位置**：`_StepCard.build` 行 553-567，4 条决策（borderColor/borderWidth/shadowColor/
/// shadowAlpha/shadowBlur）散落在 BoxDecoration / Border.all / BoxShadow 三层 inline 三元里，
/// 没有一处单测能直接覆盖"独立维度"这条契约——任何人误把 shadow 改成读 emphasized（而非 isCurrent）
/// 都不会撞红任何测试。本轮抽出后用真值表 + 反向断言双重锁定。
@visibleForTesting
class StepCardEmphasisStyle {
  /// 边框颜色：emphasized → accent，否则 border。
  final Color borderColor;

  /// 边框宽度：emphasized → 2.4，否则 1.3。
  final double borderWidth;

  /// 阴影基色：emphasized → accent，否则 border（与 borderColor 同源，方便共用变量）。
  final Color shadowBaseColor;

  /// 阴影 alpha：isCurrent → 0.24，否则 0.12。**注意是 isCurrent，不是 emphasized**。
  final double shadowAlpha;

  /// 阴影 blur 半径：isCurrent → 24，否则 16。**同上，是 isCurrent**。
  final double shadowBlur;

  const StepCardEmphasisStyle({
    required this.borderColor,
    required this.borderWidth,
    required this.shadowBaseColor,
    required this.shadowAlpha,
    required this.shadowBlur,
  });

  @override
  bool operator ==(Object other) {
    if (other is! StepCardEmphasisStyle) return false;
    return other.borderColor.toARGB32() == borderColor.toARGB32() &&
        other.borderWidth == borderWidth &&
        other.shadowBaseColor.toARGB32() == shadowBaseColor.toARGB32() &&
        other.shadowAlpha == shadowAlpha &&
        other.shadowBlur == shadowBlur;
  }

  @override
  int get hashCode => Object.hash(
        borderColor.toARGB32(),
        borderWidth,
        shadowBaseColor.toARGB32(),
        shadowAlpha,
        shadowBlur,
      );

  @override
  String toString() =>
      'StepCardEmphasisStyle(borderColor: 0x${borderColor.toARGB32().toRadixString(16)}, '
      'borderWidth: $borderWidth, '
      'shadowBaseColor: 0x${shadowBaseColor.toARGB32().toRadixString(16)}, '
      'shadowAlpha: $shadowAlpha, '
      'shadowBlur: $shadowBlur)';
}

/// 由 (palette, emphasized, isCurrent) 推断步骤卡片的 5 个渲染参数。
///
/// 见 [StepCardEmphasisStyle] 的核心契约说明：emphasized 控制边框，isCurrent 控制脉冲。
///
/// **字面量与原 `_StepCard.build` 严格一致**：
/// - borderWidth: emphasized ? 2.4 : 1.3
/// - shadowAlpha: isCurrent ? 0.24 : 0.12
/// - shadowBlur:  isCurrent ? 24 : 16
@visibleForTesting
StepCardEmphasisStyle resolveStepCardEmphasisStyle({
  required StepCardPalette palette,
  required bool emphasized,
  required bool isCurrent,
}) {
  final baseColor = emphasized ? palette.accent : palette.border;
  return StepCardEmphasisStyle(
    borderColor: baseColor,
    borderWidth: emphasized ? 2.4 : 1.3,
    shadowBaseColor: baseColor,
    shadowAlpha: isCurrent ? 0.24 : 0.12,
    shadowBlur: isCurrent ? 24.0 : 16.0,
  );
}

/// 卡片点击时应当传给 `onStepSelected` 回调的 `stepId` 参数。
///
/// **契约**：
/// - `selectedStepId == stepId`（点击的是当前已选中的卡）→ 返回 `null`（toggle off：
///   再次点击 = 取消选中）。
/// - 其它情况（未选中 / 选中的是别的卡）→ 返回 `stepId`（切到这张卡）。
///
/// 注意 `selectedStepId` 是 nullable（无任何卡被选中时为 null），不用 `!` 解引用——
/// `null == stepId` 永远 false（`stepId` 由 caller 保证非 null），自然走第二条分支。
@visibleForTesting
String? resolveStepCardTapTarget({
  required String? selectedStepId,
  required String stepId,
}) {
  return selectedStepId == stepId ? null : stepId;
}

/// 固定步骤执行视图
class StepExecutionView extends StatelessWidget {
  /// 固定四步定义
  final List<MergeExecutionStepDefinition> steps;

  /// 当前执行步骤 ID
  final String? currentStepId;

  /// 执行状态
  final ExecutorStatus status;

  /// 步骤执行快照
  final ExecutionStepSnapshots snapshots;

  /// 当前选中的步骤 ID
  final String? selectedStepId;

  /// 步骤选择回调
  final void Function(String? stepId)? onStepSelected;

  const StepExecutionView({
    super.key,
    required this.steps,
    this.currentStepId,
    required this.status,
    required this.snapshots,
    this.selectedStepId,
    this.onStepSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF4F7F8),
            Color(0xFFFFFFFF),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = resolveStepExecutionLayout(constraints.maxWidth);
          final isCompact = layout.isCompact;
          final cardWidth = layout.cardWidth;
          final children = <Widget>[];

          for (int index = 0; index < steps.length; index++) {
            final step = steps[index];
            if (index > 0) {
              children.add(
                isCompact
                    ? _VerticalConnector(
                        color: _connectorColor(steps[index - 1]),
                      )
                    : _HorizontalConnector(
                        color: _connectorColor(steps[index - 1]),
                      ),
              );
            }

            children.add(
              SizedBox(
                width: cardWidth,
                child: _StepCard(
                  index: index,
                  step: step,
                  snapshot: snapshots.get(step.id),
                  isCurrent: step.id == currentStepId,
                  isSelected: step.id == selectedStepId,
                  status: status,
                  onTap: onStepSelected == null
                      ? null
                      : () {
                          onStepSelected!(
                            resolveStepCardTapTarget(
                              selectedStepId: selectedStepId,
                              stepId: step.id,
                            ),
                          );
                        },
                ),
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: isCompact ? Axis.vertical : Axis.horizontal,
            padding: const EdgeInsets.all(24),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
          );
        },
      ),
    );
  }

  Color _connectorColor(MergeExecutionStepDefinition step) {
    return stepConnectorColor(snapshots.get(step.id));
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final MergeExecutionStepDefinition step;
  final StepSnapshot? snapshot;
  final bool isCurrent;
  final bool isSelected;
  final ExecutorStatus status;
  final VoidCallback? onTap;

  const _StepCard({
    required this.index,
    required this.step,
    required this.snapshot,
    required this.isCurrent,
    required this.isSelected,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visualState = _resolveVisualState();
    final palette = resolveStepCardPalette(visualState);
    final emphasized =
        isStepCardEmphasized(isCurrent: isCurrent, isSelected: isSelected);
    final emphasis = resolveStepCardEmphasisStyle(
      palette: palette,
      emphasized: emphasized,
      isCurrent: isCurrent,
    );
    final theme = Theme.of(context);
    final infoText = _buildInfoText();
    final infoTooltip = _buildInfoTooltip();
    final detailText = _buildDetailText();
    final detailTooltip = _buildDetailTooltip();
    final statusTooltip = _buildStatusTooltip(visualState);
    final stepIdTooltip = formatStepIdTooltip(snapshot);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: emphasis.borderColor,
              width: emphasis.borderWidth,
            ),
            boxShadow: [
              BoxShadow(
                color: emphasis.shadowBaseColor
                    .withValues(alpha: emphasis.shadowAlpha),
                blurRadius: emphasis.shadowBlur,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (statusTooltip.isEmpty)
                    _StatusChip(
                      icon: _statusIcon(visualState),
                      label: _statusLabel(visualState),
                      foreground: palette.accent,
                      background: palette.chipBackground,
                      busy: visualState == StepVisualState.running,
                    )
                  else
                    Tooltip(
                      message: statusTooltip,
                      child: _StatusChip(
                        icon: _statusIcon(visualState),
                        label: _statusLabel(visualState),
                        foreground: palette.accent,
                        background: palette.chipBackground,
                        busy: visualState == StepVisualState.running,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                step.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.45,
                  color: const Color(0xFF55626D),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (stepIdTooltip.isEmpty)
                    _InfoPill(
                      icon: Icons.fingerprint,
                      text: step.id,
                    )
                  else
                    Tooltip(
                      message: stepIdTooltip,
                      child: _InfoPill(
                        icon: Icons.fingerprint,
                        text: step.id,
                      ),
                    ),
                  if (infoText != null && infoTooltip.isEmpty)
                    _InfoPill(
                      icon: Icons.schedule,
                      text: infoText,
                    ),
                  if (infoText != null && infoTooltip.isNotEmpty)
                    Tooltip(
                      message: infoTooltip,
                      child: _InfoPill(
                        icon: Icons.schedule,
                        text: infoText,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.7),
                  ),
                ),
                child: detailTooltip.isEmpty
                    ? Text(
                        detailText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: const Color(0xFF46515A),
                        ),
                      )
                    : Tooltip(
                        message: detailTooltip,
                        child: Text(
                          detailText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.45,
                            color: const Color(0xFF46515A),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  StepVisualState _resolveVisualState() {
    return resolveStepVisualState(
      snapshot: snapshot,
      status: status,
      isCurrent: isCurrent,
    );
  }

  IconData _statusIcon(StepVisualState visualState) {
    return stepStatusIcon(visualState, status: status, isCurrent: isCurrent);
  }

  String _statusLabel(StepVisualState visualState) {
    return stepStatusLabel(visualState, status: status, isCurrent: isCurrent);
  }

  String _buildStatusTooltip(StepVisualState visualState) {
    return stepStatusTooltip(visualState, status: status, isCurrent: isCurrent);
  }

  String? _buildInfoText() {
    return stepInfoText(snapshot, isCurrent: isCurrent, status: status);
  }

  String _buildInfoTooltip() {
    return stepInfoTooltip(snapshot, isCurrent: isCurrent, status: status);
  }

  String _buildDetailText() {
    return stepDetailText(snapshot, isCurrent: isCurrent, status: status);
  }

  String _buildDetailTooltip() {
    return stepDetailTooltip(snapshot, isCurrent: isCurrent, status: status);
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final bool busy;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          else
            Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF61717D)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF52616B),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalConnector extends StatelessWidget {
  final Color color;

  const _HorizontalConnector({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 160,
      child: Center(
        child: Container(
          height: 3,
          width: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _VerticalConnector extends StatelessWidget {
  final Color color;

  const _VerticalConnector({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: SizedBox(
        width: 24,
        height: 40,
        child: Center(
          child: Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}
