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
  
  @JsonValue('done')
  done,         // 完成
  
  @JsonValue('failed')
  failed,       // 失败
}

extension JobStatusExtension on JobStatus {
  /// 获取中文显示名称
  String get displayName {
    switch (this) {
      case JobStatus.pending:
        return '等待';
      case JobStatus.running:
        return '执行中';
      case JobStatus.done:
        return '完成';
      case JobStatus.failed:
        return '失败';
    }
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

  const MergeJob({
    required this.jobId,
    required this.sourceUrl,
    required this.targetWc,
    required this.maxRetries,
    required this.revisions,
    this.status = JobStatus.pending,
    this.error = '',
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
  }) {
    return MergeJob(
      jobId: jobId ?? this.jobId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      targetWc: targetWc ?? this.targetWc,
      maxRetries: maxRetries ?? this.maxRetries,
      revisions: revisions ?? this.revisions,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  /// 获取简短描述
  String get description {
    final wcName = targetWc.split('/').last;
    final revStr = revisions.map((r) => 'r$r').join(', ');
    return '#$jobId [${status.displayName}] WC=$wcName | 源=${sourceUrl.split('/').last} | $revStr';
  }

  @override
  String toString() => description;
}

