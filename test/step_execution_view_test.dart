import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/step_output.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';
import 'package:svn_auto_merge/screens/components/step_execution_view.dart';

StepSnapshot _snap(
  StepExecutionStatus status, {
  DateTime? startTime,
  DateTime? endTime,
  String? error,
  StepOutput? output,
  Map<String, dynamic>? config,
}) {
  return StepSnapshot(
    stepId: 'merge',
    stepTypeId: 'merge',
    status: status,
    inputData: const {},
    config: config ?? const {},
    startTime: startTime ?? DateTime(2026, 5, 27, 10, 30, 45),
    endTime: endTime,
    error: error,
    output: output,
  );
}

void main() {
  group('resolveStepVisualState', () {
    test('snapshot.completed → completed（即使 isCurrent=false）', () {
      expect(
        resolveStepVisualState(
          snapshot: _snap(StepExecutionStatus.completed),
          status: ExecutorStatus.idle,
          isCurrent: false,
        ),
        StepVisualState.completed,
      );
    });

    test('snapshot.failed → failed', () {
      expect(
        resolveStepVisualState(
          snapshot: _snap(StepExecutionStatus.failed),
          status: ExecutorStatus.paused,
          isCurrent: true,
        ),
        StepVisualState.failed,
      );
    });

    test('snapshot.skipped → skipped', () {
      expect(
        resolveStepVisualState(
          snapshot: _snap(StepExecutionStatus.skipped),
          status: ExecutorStatus.idle,
          isCurrent: false,
        ),
        StepVisualState.skipped,
      );
    });

    test('snapshot.running → running', () {
      expect(
        resolveStepVisualState(
          snapshot: _snap(StepExecutionStatus.running),
          status: ExecutorStatus.idle,
          isCurrent: false,
        ),
        StepVisualState.running,
      );
    });

    test('snapshot.pending + isCurrent=true + executor.running → running（关键回落分支）', () {
      // 这条覆盖原代码 break 之后继续走 isCurrent 的逻辑
      expect(
        resolveStepVisualState(
          snapshot: _snap(StepExecutionStatus.pending),
          status: ExecutorStatus.running,
          isCurrent: true,
        ),
        StepVisualState.running,
      );
    });

    test('snapshot=null + isCurrent=true + paused → failed', () {
      expect(
        resolveStepVisualState(
          snapshot: null,
          status: ExecutorStatus.paused,
          isCurrent: true,
        ),
        StepVisualState.failed,
      );
    });

    test('snapshot=null + isCurrent=true + completed → completed', () {
      expect(
        resolveStepVisualState(
          snapshot: null,
          status: ExecutorStatus.completed,
          isCurrent: true,
        ),
        StepVisualState.completed,
      );
    });

    test('snapshot=null + isCurrent=true + idle → pending', () {
      expect(
        resolveStepVisualState(
          snapshot: null,
          status: ExecutorStatus.idle,
          isCurrent: true,
        ),
        StepVisualState.pending,
      );
    });

    test('snapshot=null + isCurrent=false → pending（不论 executor 状态）', () {
      for (final s in ExecutorStatus.values) {
        expect(
          resolveStepVisualState(
            snapshot: null,
            status: s,
            isCurrent: false,
          ),
          StepVisualState.pending,
          reason: 'executor=$s',
        );
      }
    });
  });

  group('stepStatusLabel', () {
    test('基础枚举映射', () {
      const baseArgs = (status: ExecutorStatus.running, isCurrent: false);
      expect(
        stepStatusLabel(StepVisualState.pending,
            status: baseArgs.status, isCurrent: baseArgs.isCurrent),
        '待执行',
      );
      expect(
        stepStatusLabel(StepVisualState.running,
            status: baseArgs.status, isCurrent: baseArgs.isCurrent),
        '执行中',
      );
      expect(
        stepStatusLabel(StepVisualState.completed,
            status: baseArgs.status, isCurrent: baseArgs.isCurrent),
        '已完成',
      );
      expect(
        stepStatusLabel(StepVisualState.skipped,
            status: baseArgs.status, isCurrent: baseArgs.isCurrent),
        '已跳过',
      );
    });

    test('failed + paused + isCurrent → "待处理"', () {
      expect(
        stepStatusLabel(StepVisualState.failed,
            status: ExecutorStatus.paused, isCurrent: true),
        '待处理',
      );
    });

    test('failed + paused + !isCurrent → "失败"（不是当前步骤就不显示待处理）', () {
      expect(
        stepStatusLabel(StepVisualState.failed,
            status: ExecutorStatus.paused, isCurrent: false),
        '失败',
      );
    });

    test('failed + 非 paused → "失败"', () {
      expect(
        stepStatusLabel(StepVisualState.failed,
            status: ExecutorStatus.running, isCurrent: true),
        '失败',
      );
    });
  });

  group('stepStatusIcon', () {
    test('failed + paused + isCurrent → handyman_outlined（人工处理图标）', () {
      expect(
        stepStatusIcon(StepVisualState.failed,
            status: ExecutorStatus.paused, isCurrent: true),
        Icons.handyman_outlined,
      );
    });

    test('failed + 其它 → error_outline', () {
      expect(
        stepStatusIcon(StepVisualState.failed,
            status: ExecutorStatus.running, isCurrent: true),
        Icons.error_outline,
      );
      expect(
        stepStatusIcon(StepVisualState.failed,
            status: ExecutorStatus.paused, isCurrent: false),
        Icons.error_outline,
      );
    });

    test('其它枚举映射', () {
      const args = (status: ExecutorStatus.running, isCurrent: false);
      expect(
        stepStatusIcon(StepVisualState.pending,
            status: args.status, isCurrent: args.isCurrent),
        Icons.schedule,
      );
      expect(
        stepStatusIcon(StepVisualState.running,
            status: args.status, isCurrent: args.isCurrent),
        Icons.sync,
      );
      expect(
        stepStatusIcon(StepVisualState.completed,
            status: args.status, isCurrent: args.isCurrent),
        Icons.check_circle,
      );
      expect(
        stepStatusIcon(StepVisualState.skipped,
            status: args.status, isCurrent: args.isCurrent),
        Icons.skip_next,
      );
    });
  });

  group('stepInfoText', () {
    test('snapshot 有 durationMs → "{ms}ms"', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: DateTime(2026, 1, 1, 0, 0, 0),
        endTime: DateTime(2026, 1, 1, 0, 0, 1, 234),
      );
      expect(
        stepInfoText(snap, isCurrent: false, status: ExecutorStatus.idle),
        '${snap.durationMs}ms',
      );
    });

    test('snapshot 无 endTime → 显示 startTime（HH:MM:SS）', () {
      final snap = _snap(
        StepExecutionStatus.running,
        startTime: DateTime(2026, 5, 27, 9, 5, 7),
      );
      expect(
        stepInfoText(snap, isCurrent: true, status: ExecutorStatus.running),
        '09:05:07',
      );
    });

    test('snapshot=null + isCurrent + running → "处理中"', () {
      expect(
        stepInfoText(null, isCurrent: true, status: ExecutorStatus.running),
        '处理中',
      );
    });

    test('snapshot=null + 其它 → null', () {
      expect(
        stepInfoText(null, isCurrent: false, status: ExecutorStatus.running),
        isNull,
      );
      expect(
        stepInfoText(null, isCurrent: true, status: ExecutorStatus.idle),
        isNull,
      );
    });
  });

  group('stepDetailText', () {
    test('snapshot=null + isCurrent + running → 在执行中文案', () {
      expect(
        stepDetailText(null, isCurrent: true, status: ExecutorStatus.running),
        '当前正在执行此步骤，执行日志与结果会在完成后写入快照。',
      );
    });

    test('snapshot=null + isCurrent + paused → 等待人工文案', () {
      expect(
        stepDetailText(null, isCurrent: true, status: ExecutorStatus.paused),
        '该步骤已暂停，等待人工处理后继续。',
      );
    });

    test('snapshot=null + 其它 → "尚未执行到此步骤。"', () {
      expect(
        stepDetailText(null, isCurrent: false, status: ExecutorStatus.idle),
        '尚未执行到此步骤。',
      );
    });

    test('snapshot.error 非空 → 取错误第一行', () {
      final snap = _snap(
        StepExecutionStatus.failed,
        error: 'first line\nsecond line\nthird',
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        'first line',
      );
    });

    test('snapshot.error 仅空白 → 不命中（继续后续分支）', () {
      // error trim 后为空，应回落到 status 兜底文案
      final snap = _snap(
        StepExecutionStatus.completed,
        error: '   \n  \n',
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        '步骤已执行完成。',
      );
    });

    test('output.data 含 revision → "处理 revision rN，输出端口: P"', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        output: const StepOutput(
          port: 'success',
          data: {'revision': 1234},
        ),
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        '处理 revision r1234，输出端口: success',
      );
    });

    test('output.data 含 message（非 revision）→ 直出 message', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        output: const StepOutput(
          port: 'success',
          data: {'message': 'all good'},
        ),
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        'all good',
      );
    });

    test('revision 优先于 message（同时存在时）', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        output: const StepOutput(
          port: 'success',
          data: {'revision': 5, 'message': 'ignored'},
        ),
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        '处理 revision r5，输出端口: success',
      );
    });

    test('output.data 非空但不含 revision/message → "输出端口: P"', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        output: const StepOutput(
          port: 'failure',
          data: {'other': 1},
        ),
      );
      expect(
        stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
        '输出端口: failure',
      );
    });

    test('snapshot.status 兜底文案（无 error 无 output）', () {
      for (final entry in const [
        (StepExecutionStatus.completed, '步骤已执行完成。'),
        (StepExecutionStatus.failed, '步骤执行失败，请查看右侧详情。'),
        (StepExecutionStatus.running, '步骤正在执行中。'),
        (StepExecutionStatus.skipped, '步骤已被跳过。'),
        (StepExecutionStatus.pending, '尚未执行到此步骤。'),
      ]) {
        final snap = _snap(entry.$1);
        expect(
          stepDetailText(snap, isCurrent: false, status: ExecutorStatus.idle),
          entry.$2,
          reason: 'status=${entry.$1}',
        );
      }
    });
  });

  group('stepDetailTooltip', () {
    test('snapshot=null → 空字符串（不暴露兜底文案）', () {
      expect(
        stepDetailTooltip(null, isCurrent: true, status: ExecutorStatus.running),
        '',
      );
      expect(
        stepDetailTooltip(null, isCurrent: true, status: ExecutorStatus.paused),
        '',
      );
      expect(
        stepDetailTooltip(null, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('error=null → 空（无 error 不需要 tooltip）', () {
      final snap = _snap(StepExecutionStatus.completed);
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('error 全空白 trim 后 → 空', () {
      final snap = _snap(StepExecutionStatus.failed, error: '   \n  \n');
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('error 单行 → 空（与 stepDetailText 等价，避免重复）', () {
      final snap = _snap(
        StepExecutionStatus.failed,
        error: 'merge conflict at file.dart',
      );
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('error 单行 + 末尾空白 → 空（trim 后无 \\n）', () {
      final snap = _snap(
        StepExecutionStatus.failed,
        error: '  merge conflict at file.dart  \n',
      );
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('error 多行 → 返回完整 trim 后内容', () {
      final snap = _snap(
        StepExecutionStatus.failed,
        error: '\nline1\nline2\nline3\n',
      );
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        'line1\nline2\nline3',
      );
    });

    test('error 多行（无前后空白）→ 原样返回', () {
      final snap = _snap(
        StepExecutionStatus.failed,
        error: 'svn: E155007: Working copy locked\nrun cleanup to unlock',
      );
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        'svn: E155007: Working copy locked\nrun cleanup to unlock',
      );
    });

    test('output 分支 → 空（output 不触发 tooltip）', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        output: const StepOutput(
          port: 'success',
          data: {'revision': 12345},
        ),
      );
      expect(
        stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('status 兜底分支 → 空（无 error 无 output）', () {
      for (final status in const [
        StepExecutionStatus.completed,
        StepExecutionStatus.failed,
        StepExecutionStatus.running,
        StepExecutionStatus.skipped,
        StepExecutionStatus.pending,
      ]) {
        final snap = _snap(status);
        expect(
          stepDetailTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
          '',
          reason: 'status=$status',
        );
      }
    });
  });

  group('formatStepIdTooltip（Step 24 - 第二十层 hover）', () {
    test('snapshot=null → "" (步骤未运行)', () {
      expect(formatStepIdTooltip(null), '');
    });

    test('snapshot.config 空 → "" (prepare/update/merge 三步走此分支)', () {
      final snap = _snap(StepExecutionStatus.completed);
      expect(snap.config.isEmpty, isTrue);
      expect(formatStepIdTooltip(snap), '');
    });

    test('snapshot.config 仅 maxRetries → 单段配置', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        config: const {'maxRetries': 3},
      );
      expect(formatStepIdTooltip(snap), '配置:\nmaxRetries: 3');
    });

    test('snapshot.config maxRetries + messageTemplate → 双段配置（保持插入顺序）', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        config: const {
          'maxRetries': 5,
          'messageTemplate': '[Merge] r{revision}',
        },
      );
      expect(
        formatStepIdTooltip(snap),
        '配置:\nmaxRetries: 5\nmessageTemplate: [Merge] r{revision}',
      );
    });

    test('maxRetries=0 边界值（"不启用重试"）→ 仍渲染', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        config: const {'maxRetries': 0},
      );
      expect(formatStepIdTooltip(snap), '配置:\nmaxRetries: 0');
    });

    test('messageTemplate 含中文 + 长字符串 → 不截断、不转义', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        config: const {
          'maxRetries': 1,
          'messageTemplate': '[合并] r{revision} 来自 {sourceUrl}（自动合并）',
        },
      );
      expect(
        formatStepIdTooltip(snap),
        '配置:\nmaxRetries: 1\nmessageTemplate: [合并] r{revision} 来自 {sourceUrl}（自动合并）',
      );
    });

    test('插入顺序锁：先 messageTemplate 后 maxRetries → tooltip 也按该序', () {
      // 防御性：即便上游改了 _startSnapshot 的 if 顺序，本 helper 也是按 Map 插入序输出。
      final snap = _snap(
        StepExecutionStatus.completed,
        config: const {
          'messageTemplate': 'tpl',
          'maxRetries': 2,
        },
      );
      expect(
        formatStepIdTooltip(snap),
        '配置:\nmessageTemplate: tpl\nmaxRetries: 2',
      );
    });
  });

  group('stepInfoTooltip', () {
    test('snapshot=null + running → 空（pill 显示"处理中"，无 startTime 可暴露）', () {
      expect(
        stepInfoTooltip(null, isCurrent: true, status: ExecutorStatus.running),
        '',
      );
    });

    test('snapshot=null + idle → 空（pill 不渲染）', () {
      expect(
        stepInfoTooltip(null, isCurrent: false, status: ExecutorStatus.idle),
        '',
      );
    });

    test('snapshot 但 endTime=null + durationMs=null → 空（pill 显示 startTime 已完整）', () {
      final snap = _snap(
        StepExecutionStatus.running,
        startTime: DateTime(2026, 5, 27, 10, 30, 45),
      );
      expect(snap.durationMs, isNull);
      expect(
        stepInfoTooltip(snap, isCurrent: true, status: ExecutorStatus.running),
        '',
      );
    });

    test('endTime + durationMs 都有 → 三行 "开始/结束/耗时"', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: DateTime(2026, 5, 27, 10, 30, 45),
        endTime: DateTime(2026, 5, 27, 10, 30, 46),
      );
      expect(
        stepInfoTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '开始: 10:30:45\n结束: 10:30:46\n耗时: 1000ms',
      );
    });

    test('耗时 0ms（同一秒内 + 毫秒精度丢失）→ 仍渲染三行', () {
      final start = DateTime(2026, 5, 27, 10, 30, 45);
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: start,
        endTime: start,
      );
      expect(
        stepInfoTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '开始: 10:30:45\n结束: 10:30:45\n耗时: 0ms',
      );
    });

    test('耗时为负数（系统时钟回拨）→ 仍渲染三行（不夹紧；与 computeDurationMs 同律）', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: DateTime(2026, 5, 27, 10, 30, 46),
        endTime: DateTime(2026, 5, 27, 10, 30, 45),
      );
      expect(
        stepInfoTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '开始: 10:30:46\n结束: 10:30:45\n耗时: -1000ms',
      );
    });

    test('跨小时（durationMs 用毫秒不用 HH:MM:SS）→ 三行原样', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: DateTime(2026, 5, 27, 10, 0, 0),
        endTime: DateTime(2026, 5, 27, 11, 30, 0),
      );
      expect(
        stepInfoTooltip(snap, isCurrent: false, status: ExecutorStatus.idle),
        '开始: 10:00:00\n结束: 11:30:00\n耗时: 5400000ms',
      );
    });

    test('delegate 到 formatStepTime（HH:MM:SS 补零一致）', () {
      final snap = _snap(
        StepExecutionStatus.completed,
        startTime: DateTime(2026, 1, 1, 1, 2, 3),
        endTime: DateTime(2026, 1, 1, 23, 59, 59),
      );
      final result =
          stepInfoTooltip(snap, isCurrent: false, status: ExecutorStatus.idle);
      // 与 formatStepTime 的补零策略一致：1:2:3 → 01:02:03
      expect(result.contains('开始: 01:02:03'), isTrue);
      expect(result.contains('结束: 23:59:59'), isTrue);
    });
  });

  group('stepStatusTooltip', () {
    test('failed + paused + isCurrent → "步骤失败，等待人工继续 / 跳过 / 终止。"', () {
      expect(
        stepStatusTooltip(
          StepVisualState.failed,
          status: ExecutorStatus.paused,
          isCurrent: true,
        ),
        '步骤失败，等待人工继续 / 跳过 / 终止。',
      );
    });

    test('failed + paused + !isCurrent → ""（chip 显示"失败"，与底层语义一致，无重写）', () {
      expect(
        stepStatusTooltip(
          StepVisualState.failed,
          status: ExecutorStatus.paused,
          isCurrent: false,
        ),
        '',
      );
    });

    test('failed + 非 paused → ""（chip 显示"失败"，无 paused 重写）', () {
      for (final s in [
        ExecutorStatus.idle,
        ExecutorStatus.running,
        ExecutorStatus.completed,
      ]) {
        expect(
          stepStatusTooltip(
            StepVisualState.failed,
            status: s,
            isCurrent: true,
          ),
          '',
          reason: 'executor=$s',
        );
      }
    });

    test('非 failed visualState → ""（不论 status / isCurrent）', () {
      for (final v in [
        StepVisualState.pending,
        StepVisualState.running,
        StepVisualState.completed,
        StepVisualState.skipped,
      ]) {
        for (final s in ExecutorStatus.values) {
          for (final c in [true, false]) {
            expect(
              stepStatusTooltip(v, status: s, isCurrent: c),
              '',
              reason: 'visual=$v status=$s isCurrent=$c',
            );
          }
        }
      }
    });

    test('与 stepStatusLabel "待处理" 重写档位严格对齐（双 helper 触发条件唯一）', () {
      // 唯一一组让 stepStatusLabel 返回 "待处理" 的输入 ⇔ 唯一一组让 stepStatusTooltip 返回非空的输入
      for (final v in StepVisualState.values) {
        for (final s in ExecutorStatus.values) {
          for (final c in [true, false]) {
            final label = stepStatusLabel(v, status: s, isCurrent: c);
            final tooltip = stepStatusTooltip(v, status: s, isCurrent: c);
            if (label == '待处理') {
              expect(tooltip, isNotEmpty, reason: 'v=$v s=$s c=$c');
            } else {
              expect(tooltip, isEmpty, reason: 'v=$v s=$s c=$c label=$label');
            }
          }
        }
      }
    });
  });

  group('formatStepTime', () {
    test('单位数补零', () {
      expect(formatStepTime(DateTime(2026, 1, 1, 1, 2, 3)), '01:02:03');
    });

    test('两位数原样', () {
      expect(formatStepTime(DateTime(2026, 1, 1, 23, 59, 59)), '23:59:59');
    });

    test('零点零分零秒', () {
      expect(formatStepTime(DateTime(2026, 1, 1, 0, 0, 0)), '00:00:00');
    });

    // R90 从 merge_execution_panel_status_test.dart::formatStepClockTime 迁来的高价值边界：
    test('正常时分秒原样输出', () {
      expect(
        formatStepTime(DateTime(2026, 5, 27, 14, 30, 45)),
        '14:30:45',
      );
    });

    test('忽略毫秒（精度只到秒）', () {
      expect(
        formatStepTime(DateTime(2026, 5, 27, 12, 0, 0, 999)),
        '12:00:00',
      );
    });

    test('忽略日期部分', () {
      // 不同日期、相同时分秒应输出相同字符串
      final a = formatStepTime(DateTime(2020, 1, 1, 8, 15, 30));
      final b = formatStepTime(DateTime(2099, 12, 31, 8, 15, 30));
      expect(a, b);
      expect(a, '08:15:30');
    });
  });

  group('stepConnectorColor', () {
    test('snapshot=null → 灰色 #D6DEE2', () {
      expect(stepConnectorColor(null), const Color(0xFFD6DEE2));
    });

    test('completed → 绿', () {
      expect(
        stepConnectorColor(_snap(StepExecutionStatus.completed)),
        const Color(0xFF2E8B57),
      );
    });

    test('failed → 橙', () {
      expect(
        stepConnectorColor(_snap(StepExecutionStatus.failed)),
        const Color(0xFFD97A2B),
      );
    });

    test('running → 蓝', () {
      expect(
        stepConnectorColor(_snap(StepExecutionStatus.running)),
        const Color(0xFF1E6AA8),
      );
    });

    test('skipped → 中灰', () {
      expect(
        stepConnectorColor(_snap(StepExecutionStatus.skipped)),
        const Color(0xFF8E99A3),
      );
    });

    test('pending → 浅灰（同 null 分支颜色）', () {
      expect(
        stepConnectorColor(_snap(StepExecutionStatus.pending)),
        const Color(0xFFD6DEE2),
      );
    });
  });

  // 锁住 StepExecutionView 的布局算式：760 断点、48/260/640 的 compact clamp、
  // wide 模式固定 240。把这些魔术常量集中到一处，未来调断点时改一处即可。
  group('resolveStepExecutionLayout', () {
    test('maxWidth < 760 → compact', () {
      final layout = resolveStepExecutionLayout(500);
      expect(layout.isCompact, isTrue);
    });

    test('maxWidth == 760 → wide（边界严格 <）', () {
      final layout = resolveStepExecutionLayout(760);
      expect(layout.isCompact, isFalse);
      expect(layout.cardWidth, 240.0);
    });

    test('maxWidth > 760 → wide，cardWidth 固定 240', () {
      final layout = resolveStepExecutionLayout(1200);
      expect(layout.isCompact, isFalse);
      expect(layout.cardWidth, 240.0);
    });

    test('compact 中间值：cardWidth = maxWidth - 48（落在 [260, 640] 内）', () {
      // 500 - 48 = 452，落在 [260, 640]，不被 clamp
      final layout = resolveStepExecutionLayout(500);
      expect(layout.isCompact, isTrue);
      expect(layout.cardWidth, 452.0);
    });

    test('compact 下界：maxWidth 太小被 clamp 到 260', () {
      // 100 - 48 = 52 < 260 → clamp 到 260
      final layout = resolveStepExecutionLayout(100);
      expect(layout.isCompact, isTrue);
      expect(layout.cardWidth, 260.0);
    });

    test('compact 上界：(maxWidth - 48) 超过 640 被 clamp 到 640', () {
      // 759（仍是 compact）→ 759-48=711 > 640 → clamp 到 640
      final layout = resolveStepExecutionLayout(759);
      expect(layout.isCompact, isTrue);
      expect(layout.cardWidth, 640.0);
    });

    test('compact 边界：maxWidth = 0', () {
      // 0 - 48 = -48 < 260 → clamp 到 260
      final layout = resolveStepExecutionLayout(0);
      expect(layout.isCompact, isTrue);
      expect(layout.cardWidth, 260.0);
    });

    test('wide 边界：maxWidth 极大（同样固定 240）', () {
      final layout = resolveStepExecutionLayout(99999);
      expect(layout.isCompact, isFalse);
      expect(layout.cardWidth, 240.0);
    });
  });

  group('StepCardPalette', () {
    test('值相等性（5 个 Color 全部用 toARGB32 比较）', () {
      const a = StepCardPalette(
        accent: Color(0xFF1E6AA8),
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
      const b = StepCardPalette(
        accent: Color(0xFF1E6AA8),
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一字段不同 → 不等（accent 改一位）', () {
      const a = StepCardPalette(
        accent: Color(0xFF1E6AA8),
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
      const b = StepCardPalette(
        accent: Color(0xFF1E6AA9), // 末位不同
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
      expect(a == b, isFalse);
    });

    test('toString 含全部 5 个十六进制色值（便于排查色板回归）', () {
      const palette = StepCardPalette(
        accent: Color(0xFF1E6AA8),
        border: Color(0xFF8DB7D8),
        background: Color(0xFFEFF6FB),
        chipBackground: Color(0xFFDCECF8),
        text: Color(0xFF14354F),
      );
      final str = palette.toString();
      expect(str.contains('1e6aa8'), isTrue);
      expect(str.contains('8db7d8'), isTrue);
      expect(str.contains('eff6fb'), isTrue);
      expect(str.contains('dcecf8'), isTrue);
      expect(str.contains('14354f'), isTrue);
    });
  });

  group('resolveStepCardPalette', () {
    // 显式锁定全部 5 套调色板的字面量——任何一个色被误改都会立即红。
    // 这是本轮的核心保护：原 widget 内 25 个 const Color 散落在 _paletteFor switch 里，
    // 没有单测覆盖；只要有人手滑改一位，过去无法被发现。

    test('running → 蓝色系（accent=0xFF1E6AA8）', () {
      expect(
        resolveStepCardPalette(StepVisualState.running),
        const StepCardPalette(
          accent: Color(0xFF1E6AA8),
          border: Color(0xFF8DB7D8),
          background: Color(0xFFEFF6FB),
          chipBackground: Color(0xFFDCECF8),
          text: Color(0xFF14354F),
        ),
      );
    });

    test('completed → 绿色系（accent=0xFF2E8B57）', () {
      expect(
        resolveStepCardPalette(StepVisualState.completed),
        const StepCardPalette(
          accent: Color(0xFF2E8B57),
          border: Color(0xFFA8D0B7),
          background: Color(0xFFF1FAF4),
          chipBackground: Color(0xFFDFF2E5),
          text: Color(0xFF1E5A39),
        ),
      );
    });

    test('failed → 橙色系（accent=0xFFD97A2B，刻意不是红）', () {
      // 与 JobStatus.failed 卡片用红色刻意分裂——step 失败语义偏"需要人工处理"，
      // 更接近 paused，所以用橙不用红。注释里明确写了这条契约。
      expect(
        resolveStepCardPalette(StepVisualState.failed),
        const StepCardPalette(
          accent: Color(0xFFD97A2B),
          border: Color(0xFFF0BE90),
          background: Color(0xFFFFF6EE),
          chipBackground: Color(0xFFFCE3CC),
          text: Color(0xFF7A4519),
        ),
      );
    });

    test('skipped → 中性灰（accent=0xFF7A8894，比 pending 更亮一档：淡出已决策跳过的 step）', () {
      expect(
        resolveStepCardPalette(StepVisualState.skipped),
        const StepCardPalette(
          accent: Color(0xFF7A8894),
          border: Color(0xFFCCD4DA),
          background: Color(0xFFF6F8F9),
          chipBackground: Color(0xFFE8EDF0),
          text: Color(0xFF4F5B64),
        ),
      );
    });

    test('pending → 深灰（accent=0xFF66747F，比 skipped 略暗：还未开始但仍占位）', () {
      expect(
        resolveStepCardPalette(StepVisualState.pending),
        const StepCardPalette(
          accent: Color(0xFF66747F),
          border: Color(0xFFD5DDE2),
          background: Color(0xFFFFFFFF),
          chipBackground: Color(0xFFF1F4F6),
          text: Color(0xFF27323A),
        ),
      );
    });

    test('pending vs skipped accent 强度对比锁定（pending 比 skipped 更暗）', () {
      // 设计意图：skipped 是"已决策跳过 / 淡出"，pending 是"还没轮到但占位"，
      // 后者强调更高（更深的灰）。用 luminance 比较两个 accent 的明暗——值小代表更暗 / 更"重"。
      // 单测撞红时帮助我修正了注释里凭直觉写的反向判断（一开始我以为 skipped 更暗），
      // 这是"用第三方真理（计算的 luminance）反向 review 设计意图"的典型案例。
      final pending = resolveStepCardPalette(StepVisualState.pending).accent;
      final skipped = resolveStepCardPalette(StepVisualState.skipped).accent;
      expect(pending.computeLuminance() < skipped.computeLuminance(), isTrue,
          reason: 'pending 应当比 skipped 更暗（占位强调更高）');
    });

    test('5 套调色板的 accent 字面量两两不同（防止误把两个 state 染成同色）', () {
      final accents = StepVisualState.values
          .map((s) => resolveStepCardPalette(s).accent.toARGB32())
          .toSet();
      expect(accents.length, StepVisualState.values.length,
          reason: '每个 visual state 都该有独立的 accent 色');
    });

    test('全部 StepVisualState.values 真值表覆盖（防漏配 enum）', () {
      // 与 Round 56/57/58 同款"防漏配 enum"契约：未来若 StepVisualState 加新值，
      // 本测会因 length 不再 == 5 而红，强制 review resolveStepCardPalette 是否覆盖。
      // 因为函数体是穷举式 switch（无 default），加新 enum 值会让编译器先报错——
      // 这条单测是第二道护栏（运行期），与编译期检查互补。
      expect(
        StepVisualState.values.length,
        5,
        reason:
            '当 StepVisualState 新增枚举值时本测会红，强制 review resolveStepCardPalette',
      );
      // 逐个调用一遍，确认没有抛 throw（即便编译器漏了某个 case 也能在运行期捕获）：
      for (final state in StepVisualState.values) {
        expect(() => resolveStepCardPalette(state), returnsNormally);
      }
    });
  });

  group('isStepCardEmphasized', () {
    test('双 false → false（普通态）', () {
      expect(isStepCardEmphasized(isCurrent: false, isSelected: false),
          isFalse);
    });

    test('isCurrent==true → true', () {
      expect(
          isStepCardEmphasized(isCurrent: true, isSelected: false), isTrue);
    });

    test('isSelected==true → true', () {
      expect(
          isStepCardEmphasized(isCurrent: false, isSelected: true), isTrue);
    });

    test('双 true → true（不重复强调，仅关心 OR 的结果）', () {
      expect(isStepCardEmphasized(isCurrent: true, isSelected: true), isTrue);
    });

    test('真值表 4 象限齐全（防止有人改成 AND 而非 OR）', () {
      // 显式断言 OR 语义：仅 (false, false) 才是 false。
      final results = {
        for (final c in [false, true])
          for (final s in [false, true])
            (c, s): isStepCardEmphasized(isCurrent: c, isSelected: s),
      };
      expect(results[(false, false)], isFalse);
      expect(results[(false, true)], isTrue);
      expect(results[(true, false)], isTrue);
      expect(results[(true, true)], isTrue);
    });
  });

  group('resolveStepCardTapTarget', () {
    test('selectedStepId == stepId → 返回 null（toggle off：再次点击 = 取消选中）', () {
      expect(
        resolveStepCardTapTarget(selectedStepId: 'a', stepId: 'a'),
        isNull,
      );
    });

    test('selectedStepId 与 stepId 不同 → 返回 stepId（切到这张卡）', () {
      expect(
        resolveStepCardTapTarget(selectedStepId: 'a', stepId: 'b'),
        'b',
      );
    });

    test('selectedStepId == null（无任何卡被选中）→ 返回 stepId', () {
      // null == 'a' 永远 false，自然走"切到这张卡"分支
      expect(
        resolveStepCardTapTarget(selectedStepId: null, stepId: 'a'),
        'a',
      );
    });

    test('toggle 语义不对称：点 selected 返回 null，点 unselected 返回 stepId（前者切走，后者切来）', () {
      // 显式锁定语义不对称——防止有人误把它写成"恒等映射"或"始终返回 stepId"
      final selectedTap =
          resolveStepCardTapTarget(selectedStepId: 'x', stepId: 'x');
      final unselectedTap =
          resolveStepCardTapTarget(selectedStepId: 'x', stepId: 'y');
      expect(selectedTap, isNull);
      expect(unselectedTap, 'y');
    });

    test('空字符串 stepId（不做合法性校验，原样比较）', () {
      expect(
        resolveStepCardTapTarget(selectedStepId: '', stepId: ''),
        isNull,
      );
      expect(
        resolveStepCardTapTarget(selectedStepId: 'a', stepId: ''),
        '',
      );
    });
  });

  group('StepCardEmphasisStyle', () {
    test('值相等性：5 个字段都相同 → 相等', () {
      const a = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 2.4,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.24,
        shadowBlur: 24.0,
      );
      const b = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 2.4,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.24,
        shadowBlur: 24.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('borderWidth 不同 → 不等（防止字面量误改 1.3↔2.4）', () {
      const a = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 2.4,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      const b = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 1.3, // 不同
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('shadowAlpha 不同 → 不等（防止字面量误改 0.12↔0.24）', () {
      const a = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.24,
        shadowBlur: 16.0,
      );
      const b = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.12, // 不同
        shadowBlur: 16.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString 含全部 5 个字段（便于排查 emphasis 回归）', () {
      const style = StepCardEmphasisStyle(
        borderColor: Color(0xFF1E6AA8),
        borderWidth: 2.4,
        shadowBaseColor: Color(0xFF1E6AA8),
        shadowAlpha: 0.24,
        shadowBlur: 24.0,
      );
      final str = style.toString();
      expect(str, contains('borderColor'));
      expect(str, contains('borderWidth: 2.4'));
      expect(str, contains('shadowBaseColor'));
      expect(str, contains('shadowAlpha: 0.24'));
      expect(str, contains('shadowBlur: 24'));
    });
  });

  group('resolveStepCardEmphasisStyle', () {
    const palette = StepCardPalette(
      accent: Color(0xFF1E6AA8),
      border: Color(0xFF8DB7D8),
      background: Color(0xFFEFF6FB),
      chipBackground: Color(0xFFDCECF8),
      text: Color(0xFF14354F),
    );

    test('(emphasized=false, isCurrent=false) → 默认态：border 色 + 细 + 淡阴影', () {
      final style = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: false,
        isCurrent: false,
      );
      expect(style.borderColor.toARGB32(), palette.border.toARGB32());
      expect(style.borderWidth, 1.3);
      expect(style.shadowBaseColor.toARGB32(), palette.border.toARGB32());
      expect(style.shadowAlpha, 0.12);
      expect(style.shadowBlur, 16.0);
    });

    test('(emphasized=true, isCurrent=false) → 已选未跑：accent 边框 + 粗 + 仍淡阴影', () {
      // 关键真值：用户点选了一张非当前卡——边框加粗指示焦点，但**不**脉冲发光
      final style = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: true,
        isCurrent: false,
      );
      expect(style.borderColor.toARGB32(), palette.accent.toARGB32());
      expect(style.borderWidth, 2.4);
      // shadowBaseColor 跟 emphasized 走（与 borderColor 同源）
      expect(style.shadowBaseColor.toARGB32(), palette.accent.toARGB32());
      // shadowAlpha / shadowBlur 跟 isCurrent 走 —— 仍是淡档
      expect(style.shadowAlpha, 0.12);
      expect(style.shadowBlur, 16.0);
    });

    test('(emphasized=false, isCurrent=true) → 理论不可达组合也能正常构造（caller 不变量错误时不抛）', () {
      // 不变量：isCurrent=true 应蕴含 emphasized=true（因 isStepCardEmphasized 是 OR）。
      // 但本函数只读两个 bool，不强制断言，构造出"细边框 + 浓阴影"的奇怪组合也允许；
      // 仅作 caller 端不变量违规的暴露窗口。
      final style = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: false,
        isCurrent: true,
      );
      expect(style.borderColor.toARGB32(), palette.border.toARGB32());
      expect(style.borderWidth, 1.3);
      expect(style.shadowAlpha, 0.24);
      expect(style.shadowBlur, 24.0);
    });

    test('(emphasized=true, isCurrent=true) → 当前在跑：accent 边框 + 粗 + 浓阴影', () {
      final style = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: true,
        isCurrent: true,
      );
      expect(style.borderColor.toARGB32(), palette.accent.toARGB32());
      expect(style.borderWidth, 2.4);
      expect(style.shadowBaseColor.toARGB32(), palette.accent.toARGB32());
      expect(style.shadowAlpha, 0.24);
      expect(style.shadowBlur, 24.0);
    });

    test('反向断言：已选未跑 ≠ 当前在跑（独立维度契约——shadowAlpha/shadowBlur 必须随 isCurrent 而变）', () {
      // 这条测试的目的：构造一个"看似对称但应当不同"的对照对，
      // 防止有人把 shadowAlpha/shadowBlur 误改为读 emphasized（而非 isCurrent）。
      // 若被误改，下面两个 style 会变成完全相等——撞红立即暴露。
      final selectedNotCurrent = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: true,
        isCurrent: false,
      );
      final currentRunning = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: true,
        isCurrent: true,
      );
      // 边框两者一致（同 emphasized）
      expect(
        selectedNotCurrent.borderColor.toARGB32(),
        currentRunning.borderColor.toARGB32(),
      );
      expect(selectedNotCurrent.borderWidth, currentRunning.borderWidth);
      // 阴影两者必须不同（不同 isCurrent）
      expect(
        selectedNotCurrent.shadowAlpha,
        isNot(equals(currentRunning.shadowAlpha)),
      );
      expect(
        selectedNotCurrent.shadowBlur,
        isNot(equals(currentRunning.shadowBlur)),
      );
      // 整体 != 锁定整个对象不等
      expect(selectedNotCurrent, isNot(equals(currentRunning)));
    });

    test('反向断言：已选未跑 ≠ 默认态（emphasized 维度独立——borderWidth 必须随 emphasized 而变）', () {
      // 对称同款：把 emphasized 维度也用反向对照锁定一次。
      // 若有人把 borderWidth 改为读 isCurrent（而非 emphasized），下面两者会撞同。
      final selectedNotCurrent = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: true,
        isCurrent: false,
      );
      final neither = resolveStepCardEmphasisStyle(
        palette: palette,
        emphasized: false,
        isCurrent: false,
      );
      // 阴影两者一致（同 isCurrent=false）
      expect(selectedNotCurrent.shadowAlpha, neither.shadowAlpha);
      expect(selectedNotCurrent.shadowBlur, neither.shadowBlur);
      // 边框两者必须不同（不同 emphasized）
      expect(
        selectedNotCurrent.borderColor.toARGB32(),
        isNot(equals(neither.borderColor.toARGB32())),
      );
      expect(
        selectedNotCurrent.borderWidth,
        isNot(equals(neither.borderWidth)),
      );
      expect(selectedNotCurrent, isNot(equals(neither)));
    });

    test('palette 切换：accent 与 border 字面量都正确透传到 borderColor / shadowBaseColor', () {
      // 防止有人误把 baseColor 写死为常量（如固定写 palette.accent），
      // 用一个**与 default 调色板完全不同**的 palette 验证字面量真的来自传参 palette。
      const customPalette = StepCardPalette(
        accent: Color(0xFFD97A2B), // failed 的橙
        border: Color(0xFFF0BE90), // failed 的浅橙
        background: Color(0xFFFFF6EE),
        chipBackground: Color(0xFFFCE3CC),
        text: Color(0xFF7A4519),
      );
      final emphasized = resolveStepCardEmphasisStyle(
        palette: customPalette,
        emphasized: true,
        isCurrent: false,
      );
      expect(
        emphasized.borderColor.toARGB32(),
        customPalette.accent.toARGB32(),
      );
      expect(
        emphasized.shadowBaseColor.toARGB32(),
        customPalette.accent.toARGB32(),
      );

      final neither = resolveStepCardEmphasisStyle(
        palette: customPalette,
        emphasized: false,
        isCurrent: false,
      );
      expect(
        neither.borderColor.toARGB32(),
        customPalette.border.toARGB32(),
      );
      expect(
        neither.shadowBaseColor.toARGB32(),
        customPalette.border.toARGB32(),
      );
    });

    test('borderColor 与 shadowBaseColor 始终同源（共享 baseColor 变量）', () {
      // 契约：emphasis style 内的 borderColor 与 shadowBaseColor 必须永远相等
      // （都来自 emphasized ? accent : border 这一个三元表达式）。
      // 4 种组合都验一遍；防止有人误把两者拆成不同分支。
      for (final emphasized in [false, true]) {
        for (final isCurrent in [false, true]) {
          final style = resolveStepCardEmphasisStyle(
            palette: palette,
            emphasized: emphasized,
            isCurrent: isCurrent,
          );
          expect(
            style.borderColor.toARGB32(),
            style.shadowBaseColor.toARGB32(),
            reason: 'emphasized=$emphasized, isCurrent=$isCurrent',
          );
        }
      }
    });
  });

  group('StepCardPalette == / hashCode 对称性（R103）', () {
    const baseline = StepCardPalette(
      accent: Color(0xFF111111),
      border: Color(0xFF222222),
      background: Color(0xFF333333),
      chipBackground: Color(0xFF444444),
      text: Color(0xFF555555),
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = StepCardPalette(
        accent: Color(0xFF111111),
        border: Color(0xFF222222),
        background: Color(0xFF333333),
        chipBackground: Color(0xFF444444),
        text: Color(0xFF555555),
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（5 字段对称性矩阵）', () {
      const diffAccent = StepCardPalette(
        accent: Color(0xFFAA1111),
        border: Color(0xFF222222),
        background: Color(0xFF333333),
        chipBackground: Color(0xFF444444),
        text: Color(0xFF555555),
      );
      const diffBorder = StepCardPalette(
        accent: Color(0xFF111111),
        border: Color(0xFFAA2222),
        background: Color(0xFF333333),
        chipBackground: Color(0xFF444444),
        text: Color(0xFF555555),
      );
      const diffBackground = StepCardPalette(
        accent: Color(0xFF111111),
        border: Color(0xFF222222),
        background: Color(0xFFAA3333),
        chipBackground: Color(0xFF444444),
        text: Color(0xFF555555),
      );
      const diffChip = StepCardPalette(
        accent: Color(0xFF111111),
        border: Color(0xFF222222),
        background: Color(0xFF333333),
        chipBackground: Color(0xFFAA4444),
        text: Color(0xFF555555),
      );
      const diffText = StepCardPalette(
        accent: Color(0xFF111111),
        border: Color(0xFF222222),
        background: Color(0xFF333333),
        chipBackground: Color(0xFF444444),
        text: Color(0xFFAA5555),
      );
      for (final v in [
        diffAccent,
        diffBorder,
        diffBackground,
        diffChip,
        diffText,
      ]) {
        expect(v, isNot(equals(baseline)));
      }
      final s = <StepCardPalette>{
        baseline,
        diffAccent,
        diffBorder,
        diffBackground,
        diffChip,
        diffText,
      };
      expect(s.length, 6,
          reason: '5 字段对称性矩阵：每字段独立修改都应让 Set 多 1 元素');
    });
  });

  group('StepCardEmphasisStyle == / hashCode 对称性（R103）', () {
    const baseline = StepCardEmphasisStyle(
      borderColor: Color(0xFF111111),
      borderWidth: 1.3,
      shadowBaseColor: Color(0xFF222222),
      shadowAlpha: 0.12,
      shadowBlur: 16.0,
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = StepCardEmphasisStyle(
        borderColor: Color(0xFF111111),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF222222),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（5 字段对称性矩阵）', () {
      const diffBorderColor = StepCardEmphasisStyle(
        borderColor: Color(0xFFAA1111),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF222222),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      const diffBorderWidth = StepCardEmphasisStyle(
        borderColor: Color(0xFF111111),
        borderWidth: 2.4,
        shadowBaseColor: Color(0xFF222222),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      const diffShadowBase = StepCardEmphasisStyle(
        borderColor: Color(0xFF111111),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFFAA2222),
        shadowAlpha: 0.12,
        shadowBlur: 16.0,
      );
      const diffShadowAlpha = StepCardEmphasisStyle(
        borderColor: Color(0xFF111111),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF222222),
        shadowAlpha: 0.24,
        shadowBlur: 16.0,
      );
      const diffShadowBlur = StepCardEmphasisStyle(
        borderColor: Color(0xFF111111),
        borderWidth: 1.3,
        shadowBaseColor: Color(0xFF222222),
        shadowAlpha: 0.12,
        shadowBlur: 24.0,
      );
      for (final v in [
        diffBorderColor,
        diffBorderWidth,
        diffShadowBase,
        diffShadowAlpha,
        diffShadowBlur,
      ]) {
        expect(v, isNot(equals(baseline)));
      }
      final s = <StepCardEmphasisStyle>{
        baseline,
        diffBorderColor,
        diffBorderWidth,
        diffShadowBase,
        diffShadowAlpha,
        diffShadowBlur,
      };
      expect(s.length, 6,
          reason: '5 字段对称性矩阵：每字段独立修改都应让 Set 多 1 元素');
    });
  });
}
