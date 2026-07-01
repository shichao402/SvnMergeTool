/// 步骤执行快照
///
/// 记录步骤执行时的完整状态，用于事后查看。
library;

import 'package:flutter/foundation.dart';

import 'step_output.dart';

/// 步骤执行状态
enum StepExecutionStatus {
  /// 待执行
  pending,

  /// 执行中
  running,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已跳过
  skipped,
}

/// 计算从 [startTime] 到 [endTime] 的耗时（毫秒）；[endTime] 为 null 时返回 null。
///
/// **行为契约**：
/// - `endTime == null` → `null`（步骤还在执行中或被中断）；
/// - 正常情况下返回 `endTime.difference(startTime).inMilliseconds`；
/// - **不夹紧负数**：当 `endTime < startTime` 时返回**负数**而非 0——这是**现状的
///   锁定**，**故意不修复**：caller（UI 渲染、JSON 序列化）自己决定要不要 max(0, x)
///   兜底。原因：负数本身是有用的 bug 信号——通常源自系统时钟回拨、用户手动改时区，
///   静默夹紧到 0 会让这类问题变得不可见。**单测里有专门的 -1000 ms 用例锁定该行为**。
/// - **不**做时区归一化：调用方负责传入两个**同一时区**的 DateTime（通常都是
///   `DateTime.now()`，本身已是本地时区）。如果一个 UTC 一个 local，`.difference`
///   仍按绝对时刻计算，结果正确但语义模糊——这种使用是上游 bug 不在本函数兜底。
@visibleForTesting
int? computeDurationMs(DateTime startTime, DateTime? endTime) {
  if (endTime == null) return null;
  return endTime.difference(startTime).inMilliseconds;
}

/// 判定步骤是否"真正成功"——双条件 AND：状态完成 **且** output 也是成功的。
///
/// **核心契约**（由 `test/step_snapshot_test.dart` 的 `isSuccess (双条件 AND 契约)`
/// group 全面锁定）：
/// - **必须** `status == completed`：仅 5 个枚举值之一才有可能为 true，其余 4 个
///   （`pending` / `running` / `failed` / `skipped`）即便 `output.isSuccess == true`
///   也必须返回 false——"状态决定"先于"output 决定"。
/// - **必须** `output != null && output.isSuccess == true`：`output == null` 走
///   `output?.isSuccess ?? false` 兜底为 **false**（**容易踩的坑**：状态完成不
///   代表成功，必须 output 也成功）；`output.isSuccess == false` 也是 false。
/// - **真值仅一种组合**：`completed && output != null && output.isSuccess == true`。
///   全函数返回值的真值表在 5×3 = 15 种组合中只有 1 种为 true。
/// - **不**根据 `output.isCancelled` 调整——cancelled 在 [StepOutput.cancelled]
///   工厂里就把 `isSuccess: false`，已经覆盖；本函数不需要单独处理。
@visibleForTesting
bool evaluateStepSuccess(StepExecutionStatus status, StepOutput? output) =>
    status == StepExecutionStatus.completed && (output?.isSuccess ?? false);

/// 把 JSON 中的 `status` 字符串解析为 [StepExecutionStatus]；任何无法识别的值都
/// 兜底为 [StepExecutionStatus.pending]。
///
/// **核心契约**（由 `test/step_snapshot_test.dart` 的 `fromJson 反序列化容错` group
/// 锁定）：
/// - 合法 enum name（`'pending'` / `'running'` / `'completed'` / `'failed'` /
///   `'skipped'`）→ 对应枚举；
/// - 未知字符串（`'wat_is_this'`）→ `pending`；
/// - `null` → `pending`（`firstWhere` 比较 `value.name == null`，因为没有任何
///   enum 的 `.name` 是 null，全部不匹配走 `orElse`）；
/// - 空字符串 `''` → `pending`（同理无匹配）；
/// - **大小写敏感**：`'Completed'` → `pending`（Dart enum `.name` 是小写驼峰，按字面比较）。
/// - **为什么必须兜底而非抛异常**：历史快照在 enum 删值/重命名后必须仍能加载，
///   否则用户的执行历史会全炸。这是**反序列化容错的核心契约**——单测显式锁定。
/// - **为什么是 `pending` 而非 `failed`**：未知状态最保险的语义是"还没跑过"，
///   让 UI 显示"待执行"提示用户重跑；如果默认 `failed`，用户会以为出错了去查根因。
@visibleForTesting
StepExecutionStatus resolveStepStatusFromName(String? name) =>
    StepExecutionStatus.values.firstWhere(
      (value) => value.name == name,
      orElse: () => StepExecutionStatus.pending,
    );

/// 渲染 [StepSnapshot.toString] 使用的紧凑单行：
/// `'StepSnapshot(stepId: $stepId, status: $status, duration: ${durationMs}ms)'`。
///
/// **行为契约**：
/// - 固定结构 **3 段**（stepId / status / duration），用 `', '`（半角逗号 + 空格）
///   分隔——**与日志生态的 `' | '` 风格、UI 标签的 `' - '` 风格刻意都不同**：这是
///   Dart `toString` 调试输出，走标准 `ClassName(field: value, ...)` 风格（与
///   `print(obj)` / `assert` 报错时的呈现一致），不参与日志切片，也不在 UI 显示。
/// - `status` 字段会被 Dart 自动渲染为 `'StepExecutionStatus.completed'`（含枚举
///   类名前缀）而**非**仅 `.name`。**现状锁定**：调试输出已经稳定使用这个格式，
///   单测断言完整字符串包含 `'StepExecutionStatus.'` 前缀。
/// - `durationMs == null` → 末尾渲染为 `'duration: nullms'`（**不**做特殊兜底成
///   `'duration: -'` 或省略整段）。**故意保留这个看起来"不漂亮"的输出**：现状已稳定，
///   修改会破坏现有 toString 测试；也是 bug 信号（看到 `nullms` 就知道步骤还没结束）。
/// - **不**对字段做 trim 或转义——这是 toString 而不是 UI 渲染；调试可读性优先。
@visibleForTesting
String formatStepSnapshotShort({
  required String stepId,
  required StepExecutionStatus status,
  required int? durationMs,
}) =>
    'StepSnapshot(stepId: $stepId, status: $status, duration: ${durationMs}ms)';

/// 步骤执行快照
///
/// 记录步骤执行时的所有信息，包括：
/// - 输入数据
/// - 配置参数
/// - 输出结果
/// - 执行时间
class StepSnapshot {
  /// 步骤 ID
  final String stepId;

  /// 步骤类型 ID
  final String stepTypeId;

  /// 步骤名称
  final String? stepName;

  /// 执行状态
  final StepExecutionStatus status;

  /// 输入数据
  final Map<String, dynamic> inputData;

  /// 步骤配置
  final Map<String, dynamic> config;

  /// 输出结果
  final StepOutput? output;

  /// 错误信息
  final String? error;

  /// 开始时间
  final DateTime startTime;

  /// 结束时间
  final DateTime? endTime;

  const StepSnapshot({
    required this.stepId,
    required this.stepTypeId,
    this.stepName,
    required this.status,
    required this.inputData,
    required this.config,
    this.output,
    this.error,
    required this.startTime,
    this.endTime,
  });

  /// 执行耗时（毫秒）
  int? get durationMs => computeDurationMs(startTime, endTime);

  /// 是否成功
  bool get isSuccess => evaluateStepSuccess(status, output);

  StepSnapshot copyWith({
    String? stepId,
    String? stepTypeId,
    String? stepName,
    StepExecutionStatus? status,
    Map<String, dynamic>? inputData,
    Map<String, dynamic>? config,
    StepOutput? output,
    String? error,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return StepSnapshot(
      stepId: stepId ?? this.stepId,
      stepTypeId: stepTypeId ?? this.stepTypeId,
      stepName: stepName ?? this.stepName,
      status: status ?? this.status,
      inputData: inputData ?? this.inputData,
      config: config ?? this.config,
      output: output ?? this.output,
      error: error ?? this.error,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stepId': stepId,
      'stepTypeId': stepTypeId,
      'stepName': stepName,
      'status': status.name,
      'inputData': inputData,
      'config': config,
      'output': output != null
          ? {
              'port': output!.port,
              'data': output!.data,
              'message': output!.message,
              'isSuccess': output!.isSuccess,
            }
          : null,
      'error': error,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  factory StepSnapshot.fromJson(Map<String, dynamic> json) {
    return StepSnapshot(
      stepId: json['stepId'] as String,
      stepTypeId: json['stepTypeId'] as String,
      stepName: json['stepName'] as String?,
      status: resolveStepStatusFromName(json['status'] as String?),
      inputData: Map<String, dynamic>.from(json['inputData'] as Map? ?? {}),
      config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      output: json['output'] != null
          ? StepOutput(
              port: json['output']['port'] as String,
              data: Map<String, dynamic>.from(
                json['output']['data'] as Map? ?? {},
              ),
              message: json['output']['message'] as String?,
              isSuccess: json['output']['isSuccess'] as bool? ?? true,
            )
          : null,
      error: json['error'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
    );
  }

  @override
  String toString() => formatStepSnapshotShort(
        stepId: stepId,
        status: status,
        durationMs: durationMs,
      );
}

/// 一次执行过程中的步骤快照集合
class ExecutionStepSnapshots {
  final Map<String, StepSnapshot> _snapshots = {};
  Map<String, dynamic> _globalContext = {};

  ExecutionStepSnapshots();

  Map<String, StepSnapshot> get all => Map.unmodifiable(_snapshots);
  Map<String, dynamic> get globalContext => Map.unmodifiable(_globalContext);

  void setGlobalContext(Map<String, dynamic> context) {
    _globalContext = Map<String, dynamic>.from(context);
  }

  StepSnapshot? get(String stepId) => _snapshots[stepId];

  void set(String stepId, StepSnapshot snapshot) {
    _snapshots[stepId] = snapshot;
  }

  void clear() {
    _snapshots.clear();
    _globalContext.clear();
  }

  bool get isEmpty => _snapshots.isEmpty;
  int get length => _snapshots.length;

  Map<String, dynamic> toJson() {
    return {
      'globalContext': _globalContext,
      'snapshots':
          _snapshots.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory ExecutionStepSnapshots.fromJson(Map<String, dynamic> json) {
    final snapshots = ExecutionStepSnapshots();
    if (json.containsKey('globalContext')) {
      snapshots.setGlobalContext(
        Map<String, dynamic>.from(json['globalContext'] as Map? ?? {}),
      );
    }

    final snapshotsData = json['snapshots'] as Map<String, dynamic>? ?? json;
    for (final entry in snapshotsData.entries) {
      if (entry.value is Map<String, dynamic>) {
        snapshots.set(
          entry.key,
          StepSnapshot.fromJson(entry.value as Map<String, dynamic>),
        );
      }
    }
    return snapshots;
  }
}
