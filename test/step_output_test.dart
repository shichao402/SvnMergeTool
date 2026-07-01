import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/step_output.dart';

void main() {
  group('StepOutput', () {
    test('success factory builds success output', () {
      final output = StepOutput.success(data: {'revision': 123}, message: 'ok');

      expect(output.port, 'success');
      expect(output.data['revision'], 123);
      expect(output.message, 'ok');
      expect(output.isSuccess, isTrue);
      expect(output.isCancelled, isFalse);
    });

    test('failure factory builds failure output', () {
      final output = StepOutput.failure(message: 'bad');

      expect(output.port, 'failure');
      expect(output.message, 'bad');
      expect(output.isSuccess, isFalse);
      expect(output.isCancelled, isFalse);
    });

    test('cancelled factory marks output as cancelled', () {
      final output = StepOutput.cancelled();

      expect(output.port, 'cancelled');
      expect(output.isSuccess, isFalse);
      expect(output.isCancelled, isTrue);
    });
  });

  group('StepOutput 工厂边界', () {
    test('cancelled 默认消息是 "已取消"', () {
      // 锁定面向用户的默认文案——单测会"硬碰硬"提醒这是 UI 字符串决策。
      final output = StepOutput.cancelled();
      expect(output.message, '已取消');
    });

    test('cancelled 自定义消息覆盖默认值', () {
      final output = StepOutput.cancelled(message: '用户主动取消');
      expect(output.message, '用户主动取消');
    });

    test('failure 自定义 port 覆盖默认 "failure"', () {
      // 锁住"port: port ?? failure"——allow caller 用业务专属错误通道（如 'timeout'）。
      // 这条契约决定了 step 注册器可以挂 N 个 failure 分支
      final output = StepOutput.failure(port: 'timeout', message: 'svn 超时');
      expect(output.port, 'timeout');
      expect(output.isSuccess, isFalse);
    });

    test('failure 不传 port → 默认 "failure"', () {
      final output = StepOutput.failure(message: 'bad');
      expect(output.port, 'failure');
    });

    test('port 工厂：自定义通道，默认 isSuccess=true', () {
      // 锁 `isSuccess = true` 默认值——port 工厂语义是"业务自定义通道"，
      // caller 通常用于成功的多分支输出（例如 'noChange' / 'mergedClean'）
      final output = StepOutput.port('noChange', data: {'reason': 'identical'});
      expect(output.port, 'noChange');
      expect(output.data['reason'], 'identical');
      expect(output.isSuccess, isTrue);
    });

    test('port 工厂：可显式传 isSuccess=false', () {
      // 业务也可能定义"非典型失败"通道（既不是 success 也不是 failure）
      final output = StepOutput.port('skipped', isSuccess: false);
      expect(output.port, 'skipped');
      expect(output.isSuccess, isFalse);
    });

    test('success 不传 data → 空 map（不是 null）', () {
      // 锁 `data ?? const {}` 兜底——caller 永远拿到 non-null Map，无需空判
      final output = StepOutput.success();
      expect(output.data, isNotNull);
      expect(output.data, isEmpty);
    });

    test('failure 不传 data → 空 map', () {
      final output = StepOutput.failure();
      expect(output.data, isEmpty);
    });

    test('cancelled 默认 isCancelled=true 且 isSuccess=false', () {
      // 同时锁住两个 bool——cancelled 不能算 success
      final output = StepOutput.cancelled();
      expect(output.isCancelled, isTrue);
      expect(output.isSuccess, isFalse);
    });

    test('默认构造器：isSuccess 默认 true、isCancelled 默认 false、data 空 map', () {
      // 锁住 const StepOutput 的默认值——直接 new 而不走工厂时的契约
      const output = StepOutput(port: 'custom');
      expect(output.isSuccess, isTrue);
      expect(output.isCancelled, isFalse);
      expect(output.data, isEmpty);
      expect(output.message, isNull);
    });
  });

  group('StepOutput.copyWith', () {
    test('不传任何参数 → 完全复制', () {
      final original = StepOutput.failure(
        port: 'timeout',
        data: {'k': 1},
        message: 'bad',
      );
      final copy = original.copyWith();
      expect(copy.port, original.port);
      expect(copy.data, original.data);
      expect(copy.message, original.message);
      expect(copy.isSuccess, original.isSuccess);
      expect(copy.isCancelled, original.isCancelled);
    });

    test('单字段覆盖：仅 port 改变', () {
      final original = StepOutput.success(data: {'k': 1});
      final copy = original.copyWith(port: 'newPort');
      expect(copy.port, 'newPort');
      expect(copy.data, original.data);
      expect(copy.isSuccess, isTrue);
    });

    test('copyWith 无法把 message 设回 null（?? this.message 限制）', () {
      // 现状锁定：copyWith 用 `?? this.message`，所以传 null 不会清除原值。
      // 如果未来需要"显式置空"语义（用 sentinel 或 wrapper），必须改实现，
      // 这条测试会爆出来提醒——不是 bug，是设计决策。
      final original = StepOutput.success(message: 'old');
      final copy = original.copyWith(message: null);
      expect(copy.message, 'old');
    });

    test('copyWith 切换 isSuccess', () {
      final original = StepOutput.success();
      final copy = original.copyWith(isSuccess: false);
      expect(copy.isSuccess, isFalse);
      expect(copy.port, 'success');  // port 不变
    });

    test('copyWith 切换 isCancelled', () {
      final original = StepOutput.failure();
      final copy = original.copyWith(isCancelled: true);
      expect(copy.isCancelled, isTrue);
    });

    // R102 补漏：data 字段独立可改性 + 全字段对称矩阵
    // 原有测试覆盖了 port / message-null / isSuccess / isCancelled 四个字段，
    // 但 data (Map) 字段从未单独 cover——这条 fill the gap。
    test('单字段覆盖：仅 data 改变（R102 补漏）', () {
      final original = StepOutput.success(data: {'k': 1}, message: 'old-msg');
      final copy = original.copyWith(data: const {'new': 2});
      expect(copy.data, {'new': 2});
      // 其他 4 字段保持原值
      expect(copy.port, original.port);
      expect(copy.message, original.message);
      expect(copy.isSuccess, original.isSuccess);
      expect(copy.isCancelled, original.isCancelled);
    });
  });

  // -------------------------------------------------------------------------
  // R114 StepOutput.toString 4 字段格式锁
  //
  // lib/execution/step_output.dart:100 输出
  // 'StepOutput(port: $port, isSuccess: $isSuccess, data: $data, message: $message)'。
  // 仅 4/5 字段（缺 isCancelled）——R114 doc 化此**故意省略**：isCancelled 由
  // port 'cancelled' 隐式表达，避免日志冗余但需要测试侧 doc 化"为何省略"。
  // -------------------------------------------------------------------------

  group('R114 StepOutput.toString 格式锁', () {
    test('toString 含 4 字段（port / isSuccess / data / message），故意省略 isCancelled',
        () {
      // R114 实测契约 doc 化：lib :100 输出 4 字段——若有人改成 5 字段
      // 把 isCancelled 也加进去，日志冗余但不影响功能；若改成 3 字段（漏写
      // 任一字段）则丢失诊断信息。锁住"恰 4 字段 + isCancelled 故意省略"。
      final output = StepOutput.success(
        data: {'revision': 123},
        message: 'ok',
      );
      final s = output.toString();
      expect(s.contains('port: '), isTrue, reason: 'port 字段必须出现');
      expect(s.contains('isSuccess: '), isTrue, reason: 'isSuccess 字段必须出现');
      expect(s.contains('data: '), isTrue, reason: 'data 字段必须出现');
      expect(s.contains('message: '), isTrue, reason: 'message 字段必须出现');
      // 故意 doc 化：isCancelled 不在 toString 中——由 port 'cancelled' 隐式表达。
      expect(s.contains('isCancelled'), isFalse,
          reason: 'isCancelled 故意省略——R114 doc 化此设计选择，'
              '若未来加入 isCancelled 字段 toString 需更新本 reason 文案');
    });

    test('toString 形如 "StepOutput(port: X, isSuccess: Y, data: Z, message: W)"',
        () {
      // 锁住"括号 + 逗号空格分隔 + key:space:value"风格。
      final output = StepOutput.success(data: {'k': 1}, message: 'ok');
      expect(
        output.toString(),
        'StepOutput(port: success, isSuccess: true, data: {k: 1}, message: ok)',
      );
    });

    test('字段顺序固定：port → isSuccess → data → message（不按字母序）', () {
      // 锁住字段顺序——日志聚合系统按字段位置切片时不能因字母排序破坏解析。
      final output = StepOutput.success(message: 'm', data: {'k': 1});
      final s = output.toString();
      expect(s.indexOf('port:') < s.indexOf('isSuccess:'), isTrue,
          reason: 'port 必须在 isSuccess 之前');
      expect(s.indexOf('isSuccess:') < s.indexOf('data:'), isTrue,
          reason: 'isSuccess 必须在 data 之前');
      expect(s.indexOf('data:') < s.indexOf('message:'), isTrue,
          reason: 'data 必须在 message 之前');
    });

    test('cancelled output → port 是 "cancelled" 字面量', () {
      // 与 isCancelled 故意省略对应——port 字面量是 cancelled 状态的唯一日志体现。
      final output = StepOutput.cancelled();
      final s = output.toString();
      expect(s.contains('port: cancelled'), isTrue,
          reason: 'cancelled output 在日志里仅靠 port 字面量识别——'
              '若 lib 改 cancelled 工厂的 port 默认值，会破坏日志聚合规则');
    });

    test('failure 也走 4 字段格式（无前缀分支）', () {
      // 锁住"无前缀"约定——若有人为 failure 加 'StepOutput.failure(...)' 前缀，
      // 上层 catch 日志格式漂移。
      final output = StepOutput.failure(port: 'timeout', message: 'svn 超时');
      expect(output.toString().startsWith('StepOutput('), isTrue,
          reason: 'toString 必须以 StepOutput( 开头——'
              '若 failure 改成 StepOutput.failure(... 前缀会破坏日志聚合');
    });
  });
}
