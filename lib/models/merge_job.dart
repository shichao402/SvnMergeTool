/// 合并任务模型
///
/// 表示一个待执行或已执行的合并任务，包含完整的参数和状态信息

import 'package:json_annotation/json_annotation.dart';

part 'merge_job.g.dart';

/// 任务状态枚举
enum JobStatus {
  @JsonValue('pending')
  pending,      // 等待执行
  
  @JsonValue('running')
  running,      // 执行中
  
  @JsonValue('paused')
  paused,       // 暂停（需要人工介入）
  
  @JsonValue('done')
  done,         // 完成
  
  @JsonValue('failed')
  failed,       // 失败（已放弃）
}

extension JobStatusExtension on JobStatus {
  /// 获取中文显示名称
  String get displayName {
    switch (this) {
      case JobStatus.pending:
        return '等待';
      case JobStatus.running:
        return '执行中';
      case JobStatus.paused:
        return '已暂停';
      case JobStatus.done:
        return '完成';
      case JobStatus.failed:
        return '失败';
    }
  }
  
  /// 是否是活跃状态（需要显示在任务列表中）
  bool get isActive {
    return this == JobStatus.pending || 
           this == JobStatus.running || 
           this == JobStatus.paused;
  }
}

@JsonSerializable()
class MergeJob {
  final int jobId;
  final String sourceUrl;
  final String targetWc;
  final int maxRetries;
  final List<int> revisions;
  final JobStatus status;
  final String error;
  
  /// 已完成合并的 revision 索引（用于暂停后继续）
  /// 例如：revisions = [100, 101, 102]，completedIndex = 1 表示 r100 和 r101 已完成
  final int completedIndex;
  
  /// 暂停原因（冲突、提交失败等）
  final String pauseReason;

  const MergeJob({
    required this.jobId,
    required this.sourceUrl,
    required this.targetWc,
    required this.maxRetries,
    required this.revisions,
    this.status = JobStatus.pending,
    this.error = '',
    this.completedIndex = 0,
    this.pauseReason = '',
  });

  /// 从 JSON 创建
  factory MergeJob.fromJson(Map<String, dynamic> json) =>
      _$MergeJobFromJson(json);

  /// 转换为 JSON
  Map<String, dynamic> toJson() => _$MergeJobToJson(this);

  /// 复制并修改部分字段
  MergeJob copyWith({
    int? jobId,
    String? sourceUrl,
    String? targetWc,
    int? maxRetries,
    List<int>? revisions,
    JobStatus? status,
    String? error,
    int? completedIndex,
    String? pauseReason,
  }) {
    return MergeJob(
      jobId: jobId ?? this.jobId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      targetWc: targetWc ?? this.targetWc,
      maxRetries: maxRetries ?? this.maxRetries,
      revisions: revisions ?? this.revisions,
      status: status ?? this.status,
      error: error ?? this.error,
      completedIndex: completedIndex ?? this.completedIndex,
      pauseReason: pauseReason ?? this.pauseReason,
    );
  }
  
  /// 获取当前正在处理的 revision（如果有）
  int? get currentRevision {
    if (completedIndex < revisions.length) {
      return revisions[completedIndex];
    }
    return null;
  }
  
  /// 获取剩余待合并的 revision 列表
  List<int> get remainingRevisions {
    if (completedIndex >= revisions.length) {
      return [];
    }
    return revisions.sublist(completedIndex);
  }
  
  /// 获取已完成的 revision 列表
  List<int> get completedRevisions {
    if (completedIndex <= 0) {
      return [];
    }
    return revisions.sublist(0, completedIndex);
  }
  
  /// 是否需要人工介入
  bool get needsIntervention => status == JobStatus.paused;

  /// 获取简短描述
  String get description {
    final wcName = targetWc.split('/').last;
    final revStr = revisions.map((r) => 'r$r').join(', ');
    String statusStr = status.displayName;
    if (status == JobStatus.paused) {
      statusStr = '$statusStr (${completedIndex}/${revisions.length})';
    }
    return '#$jobId [$statusStr] WC=$wcName | 源=${sourceUrl.split('/').last} | $revStr';
  }

  @override
  String toString() => description;
}

