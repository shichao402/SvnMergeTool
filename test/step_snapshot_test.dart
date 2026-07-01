import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/step_output.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';

void main() {
  group('StepSnapshot', () {
    test('serializes and deserializes snapshot', () {
      final snapshot = StepSnapshot(
        stepId: 'merge',
        stepTypeId: 'merge',
        stepName: '合并',
        status: StepExecutionStatus.completed,
        inputData: const {'revision': 123},
        config: const {'maxRetries': 5},
        output: StepOutput.success(data: {'sourceUrl': 'svn://source'}),
        error: null,
        startTime: DateTime.parse('2026-01-01T10:00:00Z'),
        endTime: DateTime.parse('2026-01-01T10:00:01Z'),
      );

      final restored = StepSnapshot.fromJson(snapshot.toJson());

      expect(restored.stepId, snapshot.stepId);
      expect(restored.stepTypeId, snapshot.stepTypeId);
      expect(restored.stepName, snapshot.stepName);
      expect(restored.status, snapshot.status);
      expect(restored.inputData, snapshot.inputData);
      expect(restored.config, snapshot.config);
      expect(restored.output?.port, 'success');
      expect(restored.output?.data['sourceUrl'], 'svn://source');
      expect(restored.durationMs, 1000);
    });

    test('execution snapshot collection stores global context', () {
      final snapshots = ExecutionStepSnapshots();
      snapshots.setGlobalContext(const {
        'job': {'jobId': 1}
      });
      snapshots.set(
        'prepare',
        StepSnapshot(
          stepId: 'prepare',
          stepTypeId: 'prepare',
          stepName: '准备',
          status: StepExecutionStatus.running,
          inputData: const {},
          config: const {},
          startTime: DateTime.parse('2026-01-01T10:00:00Z'),
        ),
      );

      final restored = ExecutionStepSnapshots.fromJson(snapshots.toJson());

      expect(restored.globalContext['job']['jobId'], 1);
      expect(restored.get('prepare')?.stepName, '准备');
      expect(restored.length, 1);
    });
  });

  group('StepSnapshot.isSuccess (双条件 AND 契约)', () {
    StepSnapshot snap({
      required StepExecutionStatus status,
      StepOutput? output,
    }) {
      return StepSnapshot(
        stepId: 's1',
        stepTypeId: 't',
        status: status,
        inputData: const {},
        config: const {},
        output: output,
        startTime: DateTime.parse('2026-01-01T10:00:00Z'),
      );
    }

    test('completed + output.isSuccess=true → true', () {
      // 仅此一种组合 → true
      expect(
        snap(
          status: StepExecutionStatus.completed,
          output: StepOutput.success(),
        ).isSuccess,
        isTrue,
      );
    });

    test('completed 但 output==null → false（output? 兜底为 false）', () {
      // 容易踩的坑：状态完成不代表成功，必须 output 也成功。
      // 这条契约锁 `output?.isSuccess ?? false` 这条 false 兜底。
      expect(
        snap(status: StepExecutionStatus.completed, output: null).isSuccess,
        isFalse,
      );
    });

    test('completed 但 output.isSuccess=false → false', () {
      // 同上：双条件 AND，任一 false 即 false
      expect(
        snap(
          status: StepExecutionStatus.completed,
          output: StepOutput.failure(),
        ).isSuccess,
        isFalse,
      );
    });

    test('非 completed 状态全部 → false（即便 output.isSuccess=true）', () {
      // 显式遍历——未来加新 enum 值时会自动落入"非 completed"分支，
      // 测试直接检验"只有 completed 才可能 true"是想要的默认。
      for (final status in StepExecutionStatus.values) {
        if (status == StepExecutionStatus.completed) continue;
        expect(
          snap(status: status, output: StepOutput.success()).isSuccess,
          isFalse,
          reason: 'status=$status 即便 output 成功，也不应判为 isSuccess',
        );
      }
    });
  });

  group('StepSnapshot.fromJson 反序列化容错', () {
    Map<String, dynamic> baseJson({String? status}) {
      return {
        'stepId': 's1',
        'stepTypeId': 't',
        'stepName': null,
        'status': status,
        'inputData': {},
        'config': {},
        'output': null,
        'error': null,
        'startTime': '2026-01-01T10:00:00Z',
        'endTime': null,
      };
    }

    test('未知 status 字符串 → 兜底为 pending', () {
      // 锁定"未知 status → pending"——这是反序列化容错的核心契约。
      // 历史快照在 enum 删值/重命名后必须仍能加载，否则用户的执行历史会全炸。
      final restored = StepSnapshot.fromJson(baseJson(status: 'wat_is_this'));
      expect(restored.status, StepExecutionStatus.pending);
    });

    test('null status → 兜底为 pending（firstWhere 无匹配）', () {
      final restored = StepSnapshot.fromJson(baseJson(status: null));
      expect(restored.status, StepExecutionStatus.pending);
    });

    test('空字符串 status → 兜底为 pending', () {
      final restored = StepSnapshot.fromJson(baseJson(status: ''));
      expect(restored.status, StepExecutionStatus.pending);
    });

    test('合法的所有 enum name 都能往返', () {
      // 反过来锁——保证当前所有 enum 值的 name 都是反序列化合法值。
      // 任何人改 enum 名字（dart 重构常见）会立刻爆这个测试。
      for (final status in StepExecutionStatus.values) {
        final restored = StepSnapshot.fromJson(baseJson(status: status.name));
        expect(restored.status, status, reason: '$status 的 name=${status.name} 应能往返');
      }
    });

    test('output 嵌套对象的 isSuccess 缺失 → 兜底为 true（向后兼容老快照）', () {
      // 老版本 StepOutput 没有 isSuccess 字段，反序列化时必须默认 true，
      // 否则历史成功快照在新版本会全部"被失败"。锁定 `as bool? ?? true`。
      final json = baseJson(status: 'completed');
      json['output'] = {
        'port': 'success',
        'data': {},
        'message': null,
        // 故意不给 isSuccess
      };
      final restored = StepSnapshot.fromJson(json);
      expect(restored.output?.isSuccess, isTrue);
    });

    test('output.data 缺失 → 兜底为空 map', () {
      // 锁 `Map<String, dynamic>.from(json['output']['data'] as Map? ?? {})`
      final json = baseJson(status: 'completed');
      json['output'] = {
        'port': 'success',
        // 故意不给 data
      };
      final restored = StepSnapshot.fromJson(json);
      expect(restored.output?.data, isEmpty);
    });

    test('inputData / config 缺失 → 兜底为空 map', () {
      final json = baseJson(status: 'pending');
      json.remove('inputData');
      json.remove('config');
      final restored = StepSnapshot.fromJson(json);
      expect(restored.inputData, isEmpty);
      expect(restored.config, isEmpty);
    });

    test('endTime 为 null 时不解析、durationMs 返回 null', () {
      final json = baseJson(status: 'pending');
      final restored = StepSnapshot.fromJson(json);
      expect(restored.endTime, isNull);
      expect(restored.durationMs, isNull);
    });
  });

  group('ExecutionStepSnapshots.fromJson 双格式兼容（重要历史包袱）', () {
    test('新格式：{globalContext, snapshots} → 都解析', () {
      final json = {
        'globalContext': {'jobId': 7},
        'snapshots': {
          'a': {
            'stepId': 'a',
            'stepTypeId': 't',
            'stepName': null,
            'status': 'completed',
            'inputData': {},
            'config': {},
            'output': null,
            'error': null,
            'startTime': '2026-01-01T10:00:00Z',
            'endTime': null,
          },
        },
      };
      final restored = ExecutionStepSnapshots.fromJson(json);
      expect(restored.globalContext['jobId'], 7);
      expect(restored.length, 1);
      expect(restored.get('a')?.status, StepExecutionStatus.completed);
    });

    test('老格式：整个 json 直接当 snapshots map（无 globalContext / snapshots key）→ 仍能加载',
        () {
      // 这是关键的历史向后兼容契约——老版本快照根本没有外层 wrapper，
      // 直接把 stepId 当 key、StepSnapshot.toJson 当 value。
      // `final snapshotsData = json['snapshots'] as Map<String, dynamic>? ?? json;`
      // 这条 ?? 兜底如果有人手贱删了，旧用户的历史快照全炸。
      final json = {
        'stepA': {
          'stepId': 'stepA',
          'stepTypeId': 't',
          'stepName': null,
          'status': 'completed',
          'inputData': {},
          'config': {},
          'output': null,
          'error': null,
          'startTime': '2026-01-01T10:00:00Z',
          'endTime': null,
        },
        'stepB': {
          'stepId': 'stepB',
          'stepTypeId': 't',
          'stepName': null,
          'status': 'pending',
          'inputData': {},
          'config': {},
          'output': null,
          'error': null,
          'startTime': '2026-01-01T10:00:00Z',
          'endTime': null,
        },
      };
      final restored = ExecutionStepSnapshots.fromJson(json);
      expect(restored.length, 2);
      expect(restored.get('stepA')?.status, StepExecutionStatus.completed);
      expect(restored.get('stepB')?.status, StepExecutionStatus.pending);
      expect(restored.globalContext, isEmpty);
    });

    test('老格式 + 包含非 Map 值的 entry → 跳过非 Map 值（容错）', () {
      // `if (entry.value is Map<String, dynamic>)` 这条守卫——
      // 防止老格式里混进了别的字段（理论不会，但守卫存在就锁住）。
      final json = {
        'someJunk': 'this is a string, not a map',
        'realStep': {
          'stepId': 'realStep',
          'stepTypeId': 't',
          'stepName': null,
          'status': 'pending',
          'inputData': {},
          'config': {},
          'output': null,
          'error': null,
          'startTime': '2026-01-01T10:00:00Z',
          'endTime': null,
        },
      };
      final restored = ExecutionStepSnapshots.fromJson(json);
      expect(restored.length, 1);
      expect(restored.get('realStep'), isNotNull);
      expect(restored.get('someJunk'), isNull);
    });

    test('空 json → 空集合，globalContext 也空', () {
      final restored = ExecutionStepSnapshots.fromJson({});
      expect(restored.length, 0);
      expect(restored.globalContext, isEmpty);
    });
  });

  group('StepSnapshot.durationMs', () {
    test('endTime == null → null', () {
      final s = StepSnapshot(
        stepId: 's',
        stepTypeId: 't',
        status: StepExecutionStatus.running,
        inputData: const {},
        config: const {},
        startTime: DateTime.parse('2026-01-01T10:00:00Z'),
      );
      expect(s.durationMs, isNull);
    });

    test('endTime 早于 startTime → 负数（不夹紧；现状锁定）', () {
      // 锁定"不做合法性校验"——caller 自己决定要不要兜底负数。
      // 把这条文档化是为了避免未来有人误以为"durationMs 永远 >= 0"。
      final s = StepSnapshot(
        stepId: 's',
        stepTypeId: 't',
        status: StepExecutionStatus.completed,
        inputData: const {},
        config: const {},
        startTime: DateTime.parse('2026-01-01T10:00:01Z'),
        endTime: DateTime.parse('2026-01-01T10:00:00Z'),
      );
      expect(s.durationMs, -1000);
    });
  });

  group('computeDurationMs (顶层纯函数直接调用)', () {
    test('endTime == null → null', () {
      expect(
        computeDurationMs(DateTime.parse('2026-01-01T10:00:00Z'), null),
        isNull,
      );
    });

    test('正常情况：endTime - startTime 的毫秒差', () {
      expect(
        computeDurationMs(
          DateTime.parse('2026-01-01T10:00:00Z'),
          DateTime.parse('2026-01-01T10:00:01Z'),
        ),
        1000,
      );
    });

    test('endTime 早于 startTime → 负数（锁定不夹紧）', () {
      expect(
        computeDurationMs(
          DateTime.parse('2026-01-01T10:00:05Z'),
          DateTime.parse('2026-01-01T10:00:00Z'),
        ),
        -5000,
      );
    });

    test('startTime == endTime → 0（边界）', () {
      final t = DateTime.parse('2026-01-01T10:00:00Z');
      expect(computeDurationMs(t, t), 0);
    });

    test('跨小时正确累加', () {
      expect(
        computeDurationMs(
          DateTime.parse('2026-01-01T10:00:00Z'),
          DateTime.parse('2026-01-01T11:30:00Z'),
        ),
        5400000, // 90 min
      );
    });

    test('与 StepSnapshot.durationMs 输出等价', () {
      final s = StepSnapshot(
        stepId: 's',
        stepTypeId: 't',
        status: StepExecutionStatus.completed,
        inputData: const {},
        config: const {},
        startTime: DateTime.parse('2026-01-01T10:00:00Z'),
        endTime: DateTime.parse('2026-01-01T10:00:02Z'),
      );
      expect(s.durationMs, computeDurationMs(s.startTime, s.endTime));
    });
  });

  group('evaluateStepSuccess (顶层纯函数直接调用)', () {
    test('completed + output.isSuccess=true → true', () {
      expect(
        evaluateStepSuccess(
          StepExecutionStatus.completed,
          StepOutput.success(),
        ),
        isTrue,
      );
    });

    test('completed + output==null → false（output? 兜底）', () {
      expect(
        evaluateStepSuccess(StepExecutionStatus.completed, null),
        isFalse,
      );
    });

    test('completed + output.isSuccess=false → false', () {
      expect(
        evaluateStepSuccess(
          StepExecutionStatus.completed,
          StepOutput.failure(),
        ),
        isFalse,
      );
    });

    test('真值表：5×3=15 种组合中只有一种为 true', () {
      // 全枚举遍历 × {null, success, failure}——锁定"completed && output 成功"是唯一真值。
      final outputs = [
        null,
        StepOutput.success(),
        StepOutput.failure(),
      ];
      var trueCount = 0;
      for (final status in StepExecutionStatus.values) {
        for (final output in outputs) {
          if (evaluateStepSuccess(status, output)) trueCount++;
        }
      }
      expect(trueCount, 1);
    });

    test('cancelled output（StepOutput.cancelled() 工厂自带 isSuccess=false）→ false', () {
      // 即使状态是 completed，cancelled 工厂里 isSuccess=false → 整体 false。
      // 锁定"不需要单独处理 isCancelled"——已经被 isSuccess 字段表达。
      expect(
        evaluateStepSuccess(
          StepExecutionStatus.completed,
          StepOutput.cancelled(),
        ),
        isFalse,
      );
    });
  });

  group('formatStepSnapshotShort (顶层纯函数直接调用)', () {
    test('正常情况：3 段固定结构', () {
      final line = formatStepSnapshotShort(
        stepId: 'merge',
        status: StepExecutionStatus.completed,
        durationMs: 1500,
      );
      expect(
        line,
        'StepSnapshot(stepId: merge, status: StepExecutionStatus.completed, duration: 1500ms)',
      );
    });

    test('status 渲染包含枚举类名前缀（与 .name 不同）', () {
      // Dart enum 默认 toString 是 'StepExecutionStatus.completed' 而非仅 'completed'。
      // 锁定调试输出当前格式。
      final line = formatStepSnapshotShort(
        stepId: 's',
        status: StepExecutionStatus.completed,
        durationMs: 0,
      );
      expect(line.contains('StepExecutionStatus.completed'), isTrue);
    });

    test('durationMs == null → 末尾 "duration: nullms"（现状锁定，刻意不美化）', () {
      // 看到 nullms 就知道步骤未结束——是 bug 信号，故意保留。
      final line = formatStepSnapshotShort(
        stepId: 's',
        status: StepExecutionStatus.running,
        durationMs: null,
      );
      expect(line.endsWith('duration: nullms)'), isTrue);
    });

    test('风格分层：使用 ", "（半角逗号 + 空格），不含 " | " 或 " - "', () {
      // 与日志生态的 ' | '（formatLogEntryShort）、UI 标签的 ' - '
      // （formatSourceUrlDisplayText）刻意都不同——这是 Dart 标准 toString 风格。
      final line = formatStepSnapshotShort(
        stepId: 's',
        status: StepExecutionStatus.pending,
        durationMs: 0,
      );
      expect(line.contains(', '), isTrue);
      expect(line.contains(' | '), isFalse);
      expect(line.contains(' - '), isFalse);
    });

    test('与 StepSnapshot.toString 输出等价', () {
      final s = StepSnapshot(
        stepId: 'abc',
        stepTypeId: 't',
        status: StepExecutionStatus.failed,
        inputData: const {},
        config: const {},
        startTime: DateTime.parse('2026-01-01T10:00:00Z'),
        endTime: DateTime.parse('2026-01-01T10:00:03Z'),
      );
      expect(
        s.toString(),
        formatStepSnapshotShort(
          stepId: 'abc',
          status: StepExecutionStatus.failed,
          durationMs: 3000,
        ),
      );
    });
  });

  group('resolveStepStatusFromName (顶层纯函数直接调用)', () {
    test('合法 enum name → 对应枚举', () {
      expect(resolveStepStatusFromName('completed'),
          StepExecutionStatus.completed);
      expect(resolveStepStatusFromName('pending'),
          StepExecutionStatus.pending);
      expect(resolveStepStatusFromName('running'),
          StepExecutionStatus.running);
      expect(resolveStepStatusFromName('failed'), StepExecutionStatus.failed);
      expect(resolveStepStatusFromName('skipped'),
          StepExecutionStatus.skipped);
    });

    test('null → pending（兜底，反序列化容错核心）', () {
      expect(resolveStepStatusFromName(null), StepExecutionStatus.pending);
    });

    test('空字符串 → pending', () {
      expect(resolveStepStatusFromName(''), StepExecutionStatus.pending);
    });

    test('未知字符串 → pending', () {
      expect(resolveStepStatusFromName('wat_is_this'),
          StepExecutionStatus.pending);
      expect(resolveStepStatusFromName('done'),
          StepExecutionStatus.pending);
    });

    test('大小写敏感：Completed → pending（按字面比较，不归一化）', () {
      // Dart enum .name 是小写驼峰；JSON 里大写不识别。
      expect(resolveStepStatusFromName('Completed'),
          StepExecutionStatus.pending);
      expect(resolveStepStatusFromName('COMPLETED'),
          StepExecutionStatus.pending);
    });

    test('所有 enum 值 .name 往返合法（任何人改 enum 名字会立刻爆）', () {
      for (final status in StepExecutionStatus.values) {
        expect(resolveStepStatusFromName(status.name), status,
            reason: '${status.name} 应能往返');
      }
    });
  });

  // R102 StepSnapshot.copyWith 全字段对称性 + nullable reset 限制审计：
  // step_snapshot.dart:167 StepSnapshot copyWith 10 字段，4 个 nullable
  // （stepName / output / error / endTime）全用 `?? this.X` 模式——无法通过 copyWith
  // reset 回 null。原本 0 个 copyWith 测试——本轮补对称性 + 4 条 reset 限制 doc。
  group('StepSnapshot copyWith 全字段对称性（R102）', () {
    final baseline = StepSnapshot(
      stepId: 'baseline-step',
      stepTypeId: 'baseline-type',
      stepName: 'Baseline Step',
      status: StepExecutionStatus.running,
      inputData: const {'key': 'value'},
      config: const {'timeout': 30},
      output: const StepOutput(port: 'success', message: 'baseline-output'),
      error: 'baseline-error',
      startTime: DateTime(2024, 1, 1, 10, 0, 0),
      endTime: DateTime(2024, 1, 1, 10, 5, 0),
    );

    test('修改单个字段时其他 9 字段全部保持原值', () {
      final modStepId = baseline.copyWith(stepId: 'new-id');
      expect(modStepId.stepId, 'new-id');
      expect(modStepId.stepTypeId, baseline.stepTypeId);
      expect(modStepId.stepName, baseline.stepName);
      expect(modStepId.status, baseline.status);
      expect(modStepId.inputData, baseline.inputData);
      expect(modStepId.config, baseline.config);
      expect(modStepId.output, baseline.output);
      expect(modStepId.error, baseline.error);
      expect(modStepId.startTime, baseline.startTime);
      expect(modStepId.endTime, baseline.endTime);

      final modStepTypeId = baseline.copyWith(stepTypeId: 'new-type');
      expect(modStepTypeId.stepTypeId, 'new-type');
      expect(modStepTypeId.stepId, baseline.stepId);

      final modStepName = baseline.copyWith(stepName: 'New Name');
      expect(modStepName.stepName, 'New Name');
      expect(modStepName.stepId, baseline.stepId);

      final modStatus =
          baseline.copyWith(status: StepExecutionStatus.completed);
      expect(modStatus.status, StepExecutionStatus.completed);
      expect(modStatus.stepName, baseline.stepName);

      final modInputData = baseline.copyWith(inputData: const {'new': 'data'});
      expect(modInputData.inputData, {'new': 'data'});
      expect(modInputData.config, baseline.config);

      final modConfig = baseline.copyWith(config: const {'new-cfg': 1});
      expect(modConfig.config, {'new-cfg': 1});
      expect(modConfig.inputData, baseline.inputData);

      final modOutput =
          baseline.copyWith(output: const StepOutput(port: 'success', message: 'new-out'));
      expect(modOutput.output?.message, 'new-out');
      expect(modOutput.error, baseline.error);

      final modError = baseline.copyWith(error: 'new-error');
      expect(modError.error, 'new-error');
      expect(modError.output, baseline.output);

      final newStart = DateTime(2025, 6, 6, 6, 6, 6);
      final modStartTime = baseline.copyWith(startTime: newStart);
      expect(modStartTime.startTime, newStart);
      expect(modStartTime.endTime, baseline.endTime);

      final newEnd = DateTime(2025, 6, 6, 7, 7, 7);
      final modEndTime = baseline.copyWith(endTime: newEnd);
      expect(modEndTime.endTime, newEnd);
      expect(modEndTime.startTime, baseline.startTime);
    });

    test('R102 lib 实测契约 doc 化：4 个 nullable 字段无法通过 copyWith reset 回 null', () {
      // 现状锁定：StepSnapshot.copyWith 用 `X ?? this.X` 模式——
      // 4 个 nullable 字段（stepName / output / error / endTime）传 null 会回退到原值。
      // **判据**：与 MergeJob.copyWith 的 _unset sentinel 模式不一致。若调用方需要清空
      // 任一字段，必须直接 new StepSnapshot(...) 重建，或在 lib 加 clearXxx flag。
      // **当前现状**：lib/providers/merge_execution_state.dart 的 4 处 snapshot.copyWith
      // 调用都只是修改字段（不清空），所以暂无修 lib 的紧迫性——但本测试锁定限制契约。

      // stepName reset 失败
      final tryClearName = baseline.copyWith(stepName: null);
      expect(tryClearName.stepName, baseline.stepName,
          reason: 'copyWith(stepName: null) 不能清空——`?? this.stepName` 会回退到原值。');

      // output reset 失败
      final tryClearOutput = baseline.copyWith(output: null);
      expect(tryClearOutput.output, baseline.output,
          reason: 'copyWith(output: null) 不能清空——`?? this.output` 会回退到原值。');

      // error reset 失败
      final tryClearError = baseline.copyWith(error: null);
      expect(tryClearError.error, baseline.error,
          reason: 'copyWith(error: null) 不能清空——`?? this.error` 会回退到原值。');

      // endTime reset 失败
      final tryClearEndTime = baseline.copyWith(endTime: null);
      expect(tryClearEndTime.endTime, baseline.endTime,
          reason: 'copyWith(endTime: null) 不能清空——`?? this.endTime` 会回退到原值。');
    });

    test('无参 copyWith 等价于副本（保留所有原值）', () {
      final copy = baseline.copyWith();
      expect(copy.stepId, baseline.stepId);
      expect(copy.stepTypeId, baseline.stepTypeId);
      expect(copy.stepName, baseline.stepName);
      expect(copy.status, baseline.status);
      expect(copy.inputData, baseline.inputData);
      expect(copy.config, baseline.config);
      expect(copy.output, baseline.output);
      expect(copy.error, baseline.error);
      expect(copy.startTime, baseline.startTime);
      expect(copy.endTime, baseline.endTime);
    });
  });

  // R115 enum 序列化字面量 schema 锁：
  // StepExecutionStatus **不**用 @JsonValue 注解——`StepSnapshot.toJson` 直接写 `status.name`
  //（lib/execution/step_snapshot.dart:198）。这意味着：
  // - wire 字符串 == enum.name 是 **当前 schema** 的隐式现状；
  // - 任何人改 enum 名字（Dart 重构常见，IDE rename 一键就能改）会让所有已写入磁盘的旧
  //   快照 wire 值不再匹配新 enum，反序列化兜底走 pending（已在 resolveStepStatusFromName
  //   group 里覆盖，但用户**看不到改名导致的丢失**）；
  // - 之前测试已锁 round-trip + name→enum 反向解析，但**没有**把 5 个 wire 字面量字符串
  //   单独"指字"——本 group 补这个维度，与 R115 JobStatus group 形成对仗（@JsonValue
  //   显式 vs .name 隐式两条 schema 路径都被锁定）。
  group('StepExecutionStatus 序列化字面量 schema 锁（R115）', () {
    // wire 直接读 toJson 的 status 字段——必须用 toJson 实测，
    // 而非引用 enum.name（否则只是在测试 .name == .name 的恒等式）。
    String wireOf(StepExecutionStatus status) {
      final snap = StepSnapshot(
        stepId: 'x',
        stepTypeId: 't',
        status: status,
        inputData: const {},
        config: const {},
        startTime: DateTime.parse('2026-01-01T00:00:00Z'),
      );
      return snap.toJson()['status'] as String;
    }

    test('5 个 wire 字面量与 enum 名严格对照（手写字符串字面量）', () {
      // 手写右侧字面量——锁的就是"今天 wire 写出来是这 5 个具体字符串"。
      // IDE rename 改 enum 名，本测试立刻撞红，强制走显式 schema 迁移决策。
      expect(wireOf(StepExecutionStatus.pending), 'pending');
      expect(wireOf(StepExecutionStatus.running), 'running');
      expect(wireOf(StepExecutionStatus.completed), 'completed');
      expect(wireOf(StepExecutionStatus.failed), 'failed');
      expect(wireOf(StepExecutionStatus.skipped), 'skipped');
    });

    test('StepExecutionStatus.values.length == 5（新增 enum 值必须 review schema）', () {
      // 与 JobStatus.values.length == 5 护栏对仗。新增任何状态都必须到本 group 添加
      // 字面量断言并 review 反序列化容错（resolveStepStatusFromName）能否识别。
      expect(StepExecutionStatus.values.length, 5,
          reason: '新增 StepExecutionStatus 时，必须 review 本 group 5 行字面量断言、'
              '以及 resolveStepStatusFromName 兜底是否需要更新。');
    });

    test('wire 字面量当前 == enum.name（无 @JsonValue 注解的现状锁）', () {
      // 与 JobStatus 那边的"漂移信号锁"对仗——但语义不同：
      // JobStatus 是 @JsonValue 注解显式控制（理论上注解可以与 .name 分裂）；
      // StepExecutionStatus 是 toJson 用 `status.name` 直接序列化（**没有**注解层）。
      // 因此这里锁的是"toJson 实现仍然走 .name 而非 .toString 或别的路径"——
      // 任何人把 toJson 改成 `status.toString()`（会得 'StepExecutionStatus.completed'）
      // 立刻撞红。
      for (final s in StepExecutionStatus.values) {
        expect(wireOf(s), s.name,
            reason: '${s.name}: 当前 toJson 走 status.name，是隐式 schema 现状的一部分；'
                '若改用 toString / @JsonValue / 其他路径，请在本测试声明并写迁移。');
      }
    });

    test('toJson 输出不含 enum 类名前缀（不是 toString 风格）', () {
      // 反向防漏：明确锁 wire 是 'completed' 而**不是** 'StepExecutionStatus.completed'。
      // toString 会带类名前缀（在 formatStepSnapshotShort 那一侧已锁），但 wire 必须是
      // 纯 enum 名——这是反序列化容错（resolveStepStatusFromName）能正确工作的前提。
      final wire = wireOf(StepExecutionStatus.completed);
      expect(wire.contains('StepExecutionStatus.'), isFalse,
          reason: 'wire 不允许带类名前缀，否则 fromJson 端 .name 比对会全部失败');
      expect(wire, 'completed');
    });
  });
}
