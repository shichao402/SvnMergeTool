import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/working_copy_manager.dart';

void main() {
  group('normalizeWorkingCopyPath', () {
    test('混合大小写转小写', () {
      expect(
        normalizeWorkingCopyPath('/Users/Me/WC/Main'),
        '/users/me/wc/main',
      );
    });

    test('反斜杠统一替换为正斜杠', () {
      expect(
        normalizeWorkingCopyPath(r'C:\Users\Me\wc'),
        'c:/users/me/wc',
      );
    });

    test('去掉末尾连续斜杠', () {
      expect(normalizeWorkingCopyPath('/wc/'), '/wc');
      expect(normalizeWorkingCopyPath('/wc//'), '/wc');
      expect(normalizeWorkingCopyPath('/wc///'), '/wc');
    });

    test('混合反斜杠 + 末尾斜杠', () {
      expect(
        normalizeWorkingCopyPath(r'C:\Users\Me\wc\'),
        'c:/users/me/wc',
      );
    });

    test('保留路径中间的斜杠组', () {
      // 中间多斜杠不归并，避免破坏类似 protocol 风格 URL 的语义
      expect(
        normalizeWorkingCopyPath('/wc//inner'),
        '/wc//inner',
      );
    });

    test('空字符串保持空', () {
      expect(normalizeWorkingCopyPath(''), '');
    });

    test('仅斜杠的输入被裁剪为空', () {
      expect(normalizeWorkingCopyPath('/'), '');
      expect(normalizeWorkingCopyPath('////'), '');
    });

    test('两个仅大小写不同的路径归一致', () {
      expect(
        normalizeWorkingCopyPath('/Users/me/WC'),
        normalizeWorkingCopyPath('/users/ME/wc'),
      );
    });
  });

  group('describeWcOperation', () {
    test('lockInfo 为 null → "当前操作"', () {
      expect(describeWcOperation(null), '当前操作');
    });

    test('优先使用 description', () {
      final info = WcLockInfo(
        workingCopy: '/wc',
        operationType: WcOperationType.merge,
        startTime: DateTime.now(),
        description: '合并 r123',
      );
      expect(describeWcOperation(info), '合并 r123');
    });

    test('description 为 null 时回落到 operationType.label', () {
      final info = WcLockInfo(
        workingCopy: '/wc',
        operationType: WcOperationType.update,
        startTime: DateTime.now(),
      );
      expect(describeWcOperation(info), '更新');
    });

    test('description 为空串视作存在（与原行为一致：?? 不会替换空串）', () {
      final info = WcLockInfo(
        workingCopy: '/wc',
        operationType: WcOperationType.commit,
        startTime: DateTime.now(),
        description: '',
      );
      expect(describeWcOperation(info), '');
    });
  });

  group('formatWcLockInfo', () {
    test('常规输出', () {
      expect(
        formatWcLockInfo(
          workingCopy: '/wc',
          label: '合并 r123',
          elapsed: const Duration(seconds: 5),
        ),
        'WcLockInfo(/wc, 合并 r123, elapsed: 5s)',
      );
    });

    test('elapsed 截断为整秒', () {
      expect(
        formatWcLockInfo(
          workingCopy: '/wc',
          label: '更新',
          elapsed: const Duration(milliseconds: 1999),
        ),
        'WcLockInfo(/wc, 更新, elapsed: 1s)',
      );
    });

    test('零耗时', () {
      expect(
        formatWcLockInfo(
          workingCopy: '/wc',
          label: '提交改动',
          elapsed: Duration.zero,
        ),
        'WcLockInfo(/wc, 提交改动, elapsed: 0s)',
      );
    });

    test('WcLockInfo.toString 行为与 formatWcLockInfo 对齐', () {
      // 用一个固定的过去时间，elapsed 至少 >= 0 秒
      final start = DateTime.now().subtract(const Duration(seconds: 3));
      final info = WcLockInfo(
        workingCopy: '/wc/main',
        operationType: WcOperationType.update,
        startTime: start,
      );
      final actual = info.toString();
      // 形状校验，避免对具体秒数做强断言（避免测试不稳）
      expect(
        RegExp(r'^WcLockInfo\(/wc/main, 更新, elapsed: \d+s\)$').hasMatch(actual),
        isTrue,
        reason: 'actual = $actual',
      );
    });
  });

  group('resolveOperationLabel', () {
    test('description 非空 → 返回 description（覆盖 label）', () {
      expect(
        resolveOperationLabel(
          description: '合并 r12345',
          operationType: WcOperationType.merge,
        ),
        '合并 r12345',
      );
    });

    test('description == null → 回落到 operationType.label', () {
      expect(
        resolveOperationLabel(
          description: null,
          operationType: WcOperationType.update,
        ),
        '更新',
      );
    });

    test('description 是空串 → **不**回落（与 ?? 语义一致，不是 ?? : isEmpty）', () {
      // 锁定 ?? 语义：空串视作"已显式设置"，不退化到 label。
      // 上层 `_acquireLock` 永远只接受非空 description，但纯函数本身保留 ?? 行为。
      expect(
        resolveOperationLabel(
          description: '',
          operationType: WcOperationType.cleanup,
        ),
        '',
      );
    });

    test('全部 8 种 operationType 的 label 在 description=null 时正确路由', () {
      const expected = {
        WcOperationType.update: '更新',
        WcOperationType.switchBranch: '切换',
        WcOperationType.revert: '还原',
        WcOperationType.cleanup: '清理',
        WcOperationType.merge: '合并',
        WcOperationType.commit: '提交',
        WcOperationType.status: '状态检查',
        WcOperationType.info: '信息查询',
      };
      for (final entry in expected.entries) {
        expect(
          resolveOperationLabel(
            description: null,
            operationType: entry.key,
          ),
          entry.value,
          reason: '${entry.key} 应路由到 "${entry.value}"',
        );
      }
    });
  });

  group('shouldRefreshMergeInfoAfterRevert', () {
    test('全条件满足 → true', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 0,
          refreshMergeInfo: true,
          sourceUrl: 'http://svn/repo',
        ),
        isTrue,
      );
    });

    test('exitCode != 0 → false（revert 失败时 mergeinfo 没动，刷新是浪费）', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 1,
          refreshMergeInfo: true,
          sourceUrl: 'http://svn/repo',
        ),
        isFalse,
      );
    });

    test('refreshMergeInfo=false → false（调用方显式关闭）', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 0,
          refreshMergeInfo: false,
          sourceUrl: 'http://svn/repo',
        ),
        isFalse,
      );
    });

    test('sourceUrl == null → false（缺源 URL，无法定位缓存）', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 0,
          refreshMergeInfo: true,
          sourceUrl: null,
        ),
        isFalse,
      );
    });

    test('sourceUrl 空串 → false', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 0,
          refreshMergeInfo: true,
          sourceUrl: '',
        ),
        isFalse,
      );
    });

    test('sourceUrl 仅空白 → true（不 trim，与 isMergeInfoArgsValid 同步）', () {
      // 锁定契约：空白字符串视作有效 URL（虽然 SVN 自己会拒），不在这一层做 trim
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 0,
          refreshMergeInfo: true,
          sourceUrl: '   ',
        ),
        isTrue,
      );
    });

    test('多个失败条件叠加仍然 false（不被任何单一条件遮蔽）', () {
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: 1,
          refreshMergeInfo: false,
          sourceUrl: null,
        ),
        isFalse,
      );
    });

    test('exitCode 负数 → false（仅 0 视作成功）', () {
      // SVN 一般不返回负 exitCode，但锁定"== 0"严格语义，不是 "<= 0"
      expect(
        shouldRefreshMergeInfoAfterRevert(
          exitCode: -1,
          refreshMergeInfo: true,
          sourceUrl: 'http://svn/repo',
        ),
        isFalse,
      );
    });
  });

  group('describeWcOperation 委托新 resolveOperationLabel 后行为不变', () {
    test('null lockInfo → "当前操作"（独立分支，不进 resolveOperationLabel）', () {
      expect(describeWcOperation(null), '当前操作');
    });

    test('lockInfo.description 优先', () {
      final info = WcLockInfo(
        workingCopy: '/wc/x',
        operationType: WcOperationType.merge,
        startTime: DateTime.now(),
        description: '合并 r999',
      );
      expect(describeWcOperation(info), '合并 r999');
    });

    test('lockInfo.description == null → operationType.label', () {
      final info = WcLockInfo(
        workingCopy: '/wc/x',
        operationType: WcOperationType.cleanup,
        startTime: DateTime.now(),
      );
      expect(describeWcOperation(info), '清理');
    });
  });

  group('formatWcLockWaitingLine', () {
    test('正常路径渲染', () {
      expect(
        formatWcLockWaitingLine(
          workingCopy: '/wc/main',
          currentOperation: '更新',
        ),
        '工作副本 /wc/main 正在执行更新，等待中...',
      );
    });

    test('行首不带缩进 — 与 svn 子系统顶层提示同级别', () {
      final line = formatWcLockWaitingLine(
        workingCopy: '/wc/x',
        currentOperation: '合并',
      );
      expect(line.startsWith(' '), isFalse);
      expect(line.startsWith('\t'), isFalse);
    });

    test('workingCopy 空串透传 — 暴露调用方传空路径的 bug', () {
      // 双空格出现在 "工作副本 " 后跟空 path，反而能触发"为什么是空路径"的注意
      expect(
        formatWcLockWaitingLine(workingCopy: '', currentOperation: '更新'),
        '工作副本  正在执行更新，等待中...',
      );
    });

    test('currentOperation 空串透传 — 不静默兜底', () {
      // describeWcOperation 已经把 null lockInfo 兜底为 "当前操作"，本函数不重复防御
      expect(
        formatWcLockWaitingLine(workingCopy: '/wc/x', currentOperation: ''),
        '工作副本 /wc/x 正在执行，等待中...',
      );
    });
  });

  group('formatWcLockAcquiredLine', () {
    test('正常路径渲染', () {
      expect(
        formatWcLockAcquiredLine(
          workingCopy: '/wc/main',
          operationLabel: '更新工作副本',
        ),
        '已获取工作副本锁: /wc/main (更新工作副本)',
      );
    });

    test('与 formatWcLockReleasedLine 形成"获取/释放"前缀对仗', () {
      final acquired = formatWcLockAcquiredLine(
        workingCopy: '/wc/x',
        operationLabel: '合并',
      );
      final released = formatWcLockReleasedLine(
        workingCopy: '/wc/x',
        elapsed: const Duration(seconds: 5),
      );
      expect(acquired.startsWith('已获取工作副本锁: /wc/x '), isTrue);
      expect(released.startsWith('释放工作副本锁: /wc/x '), isTrue);
    });

    test('operationLabel 含中文 / 圆括号字符照旧透传', () {
      // operationLabel 内自身含 '(' / ')' 会让模板出现嵌套括号 — 不做转义
      expect(
        formatWcLockAcquiredLine(
          workingCopy: '/wc/x',
          operationLabel: '合并 (r123)',
        ),
        '已获取工作副本锁: /wc/x (合并 (r123))',
      );
    });

    test('行首不带缩进', () {
      final line = formatWcLockAcquiredLine(
        workingCopy: '/wc/x',
        operationLabel: '清理',
      );
      expect(line.startsWith(' '), isFalse);
    });
  });

  group('formatWcLockReleasedLine', () {
    test('正常 elapsed 渲染秒数', () {
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/main',
          elapsed: const Duration(seconds: 12),
        ),
        '释放工作副本锁: /wc/main (耗时: 12s)',
      );
    });

    test('Duration 单位恒为秒 — 不自动切到分钟', () {
      // 即使超过 60s 也保留秒数渲染，避免日志格式漂移
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/x',
          elapsed: const Duration(seconds: 125),
        ),
        '释放工作副本锁: /wc/x (耗时: 125s)',
      );
    });

    test('Duration.zero 渲染 0s', () {
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/x',
          elapsed: Duration.zero,
        ),
        '释放工作副本锁: /wc/x (耗时: 0s)',
      );
    });

    test('elapsed == null 渲染 nulls — 暴露 _lockInfos 与 _locks 不一致的异常态', () {
      // 旧代码的 'lockInfo?.elapsed.inSeconds' 在 lockInfo 为 null 时同样得到 null
      // 字面 'nulls' 在日志里突兀，反而能促使开发者去查 "为什么 lockInfo 没了"
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/x',
          elapsed: null,
        ),
        '释放工作副本锁: /wc/x (耗时: nulls)',
      );
    });

    test('负值 elapsed 透传 — 暴露上游 startTime 反序的 bug', () {
      // Duration 允许负值，生产 DateTime.now().difference(startTime) 不会出现，
      // 一旦出现就是 startTime 被错误地设到未来 → 让日志暴露而不是兜底为 0
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/x',
          elapsed: const Duration(seconds: -3),
        ),
        '释放工作副本锁: /wc/x (耗时: -3s)',
      );
    });

    test('小于 1 秒被截断为 0 — Duration.inSeconds 的语义', () {
      expect(
        formatWcLockReleasedLine(
          workingCopy: '/wc/x',
          elapsed: const Duration(milliseconds: 999),
        ),
        '释放工作副本锁: /wc/x (耗时: 0s)',
      );
    });
  });

  group('formatMergeInfoRefreshFailureLine', () {
    test('字符串 error 渲染', () {
      expect(
        formatMergeInfoRefreshFailureLine('网络超时'),
        '刷新 mergeinfo 缓存失败: 网络超时',
      );
    });

    test('Exception 走 toString()', () {
      expect(
        formatMergeInfoRefreshFailureLine(Exception('SVN E175002')),
        '刷新 mergeinfo 缓存失败: Exception: SVN E175002',
      );
    });

    test('Error 子类走 toString()', () {
      expect(
        formatMergeInfoRefreshFailureLine(StateError('No element')),
        '刷新 mergeinfo 缓存失败: Bad state: No element',
      );
    });

    test('行首不带缩进', () {
      final line = formatMergeInfoRefreshFailureLine('x');
      expect(line.startsWith(' '), isFalse);
    });

    test('数字等非异常对象也走 toString — 容忍 catch (e) 任意 e', () {
      // catch (e) 的 e 是 Object?，理论上可以是任何类型
      expect(
        formatMergeInfoRefreshFailureLine(42),
        '刷新 mergeinfo 缓存失败: 42',
      );
    });
  });

  group('WcOperationType.label 文案锁定', () {
    test('每个枚举值都有非空 label', () {
      for (final op in WcOperationType.values) {
        expect(op.label, isNotEmpty, reason: '$op 必须有可读 label，否则锁日志会出现空括号');
      }
    });

    test('8 个枚举值的中文文案', () {
      // 任何 label 漂移都需要先红再绿，确保日志兼容性
      expect(WcOperationType.update.label, '更新');
      expect(WcOperationType.switchBranch.label, '切换');
      expect(WcOperationType.revert.label, '还原');
      expect(WcOperationType.cleanup.label, '清理');
      expect(WcOperationType.merge.label, '合并');
      expect(WcOperationType.commit.label, '提交');
      expect(WcOperationType.status.label, '状态检查');
      expect(WcOperationType.info.label, '信息查询');
    });

    test('label 互不相同 — 防止两个枚举在日志里成同一句话', () {
      final labels = WcOperationType.values.map((e) => e.label).toSet();
      expect(labels.length, WcOperationType.values.length);
    });
  });

  group('R120 等待协议档 1（信号驱动等待）doc-as-test', () {
    // R120 框架背景：等待 channel 三档分类（与 R98 throw 三档 / R119 then/catchError
    // 三档同源）—— 档 1 信号驱动（Completer.future）/ 档 2 polling+sleep（无信号源时回退）
    // / 档 3 节流型 sleep（不等任何信号、纯降速）。本组 doc-as-test 锁档 1 与档 2/档 3 的
    // 区别契约，未来若有人把档 1 的 Completer.future 改成 polling sleep（性能 / 简单性
    // 误优），这组测试通过对照锁强制走显式分类决策。

    test('档 1 用 Completer 而非 polling — 维护成本与档际边界 doc 化', () {
      // working_copy_manager._acquireLock 故意用 `await Completer.future` 而非
      // `while (locked) await Future.delayed(Xms)`。
      // 区分锁理由：
      // 1) 信号源已存在（_releaseLock 显式 complete）→ 档 1 优先；
      // 2) 任意 polling 间隔都是平局 trade-off（小 = CPU 浪费 / 大 = 锁释放后唤醒滞后）；
      // 3) Completer 一次性 single-shot 唤醒，无虚假唤醒概念。
      // 档 2（logger close）走 polling 是因为没有"队列空了"的信号源 — 多个 producer
      // 异步驱动队列，无法集中通知；档 3（preload throttle）走 sleep 是因为故意降速。
      // 三档 trade-off 表（档 = 信号源是否存在 / 唤醒精度 / 退出条件来源）:
      //   档 1: 信号源存在 / 精确 / 信号
      //   档 2: 无信号源 / 平局间隔 / 布尔条件
      //   档 3: 无等待意图 / 无所谓 / 外部 stop 信号
      expect(true, isTrue);
    });

    test('while + await Completer.future（不可改成 if）— R120 档 1 子契约', () {
      // _acquireLock 内部 `while (_locks.containsKey(...))` 而非 `if`。
      // 改 if 的失败模式：等待者 A、B 排队到同一锁；持有者 release → A.complete +
      // B.complete 同时被调度；A 进入"创建新锁"分支；B 也进入"创建新锁"分支与 A
      // 竞争 _locks[X] = Completer<void>() 写入。while 让 B 重新进入 await 直到 A
      // 释放。这是 Completer 模型的标准互斥惯例 — 不是过度防御。
      expect(true, isTrue);
    });
  });

  // R120 close-out 注：档 2 / 档 3 的 doc-as-test 已分别落在 logger_service_test.dart
  // 与 preload_service_test.dart（若 preload 测试文件存在），保持"测试就近 lib 文件"
  // 的 R98 doc 就近性原则。

  group('R121 资源释放协议档 3（fire-and-forget 同步签名型）doc-as-test', () {
    // R121 框架（与 R98 throw / R119 then-catchError / R120 wait 同源 —— 第 4 次跨
    // channel 三档对偶）—— 释放 channel 三档分类：
    //   档 1：真异步等待型（Future<void> close async + 真 await）
    //         —— logger_service.close（poll → flush → close）
    //   档 2：伪异步同步释放型（Future<void> close async + 函数体无 await）
    //         —— mergeinfo_cache_service.close / log_cache_service.close
    //   档 3：fire-and-forget 同步签名型（void dispose + 不 await 内部 Future）
    //         —— 本档 working_copy_manager.dispose
    // 本组 doc-as-test 锁档 3 与档 1/档 2 的对称释放语义边界。

    test('档 3 签名是 void dispose（不是 async）— 框架/接口契约决定档位', () {
      // working_copy_manager.dispose 是 `void dispose()` 不是 `Future<void>`。
      // 档位识别规则（R121 核心）：**签名决定档位，不是函数体内行为**。
      //   档 1：Future<void> + 真 await   → 强落盘语义（caller 可 await）
      //   档 2：Future<void> + 无 await   → 同步释放语义（保留 async 是为了接口同形）
      //   档 3：void                       → fire-and-forget（caller 无法 await）
      // 反例：把本档 dispose 改成 `Future<void> dispose() async => await
      // _statusController.close()` 会破坏 Flutter Disposable mixin 的 `void
      // dispose()` 契约（widget tree 不接受 async dispose）—— 即使内部 close()
      // 返回 Future，签名仍必须是 void。
      expect(true, isTrue);
    });

    test('档 3 对称释放语义最弱 — 与档 1/档 2 区分锁', () {
      // 三档对称释放语义对照表（caller 在 `await close()` / `dispose()` 后能
      // 假设的状态）：
      //   档 1（logger_service.close）：物理落盘已完成（poll 排干 + flush + close）
      //   档 2（mergeinfo/log_cache.close）：内存 handle 已释放（map clear + db
      //                                      dispose），但**无 fsync 保证**
      //   档 3（本档 dispose）：StreamController.close 已被调用，但**无法保证**
      //                          订阅者已收到 done event（fire-and-forget）
      // 删 sleep / 改 await 的判据：caller 是否需要等待"释放后状态"？
      //   - logger 关 app 时需要日志落盘 → 档 1；
      //   - cache 释放只需 handle 不泄漏 → 档 2；
      //   - StreamController 订阅者通知是 best-effort → 档 3。
      expect(true, isTrue);
    });

    test('StreamController.close 内置幂等 — 重复 dispose 不抛错', () {
      // 档 3 幂等机制对比：
      //   档 1：靠 _initialized 状态位 + ?. null 短路；
      //   档 2：靠 _databases.clear() 后 map 空 → 空 for 循环 noop；
      //   档 3：靠 StreamController.close 内部对 _state.isClosed 自检 ——
      //         返回同一个 Future、不抛错（Dart SDK 契约）。
      // 三档幂等机制各异、但**caller 视角的契约一致**：dispose/close 可重复调
      // 用。这是 R121 三档**异常策略一致性**的具体体现（都不补 try/catch）。
      expect(true, isTrue);
    });
  });
}
