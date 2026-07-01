import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/screens/components/status_bar.dart';

void main() {
  group('statusBarStatusText', () {
    test('covers all ExecutorStatus values', () {
      expect(statusBarStatusText(ExecutorStatus.idle), '就绪');
      expect(statusBarStatusText(ExecutorStatus.running), '运行中');
      expect(statusBarStatusText(ExecutorStatus.paused), '等待处理');
      expect(statusBarStatusText(ExecutorStatus.completed), '已完成');
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      // 与 executorStatusTitle 等 group 同款防漏配契约：底部 status bar 文案
      // 与执行面板顶部文案是不同集合（注意 statusBarStatusText 用"就绪/运行中/等待处理"，
      // executorStatusTitle 用"等待执行/执行中/已暂停"），新增 enum 必须**两边各自决策**。
      expect(ExecutorStatus.values.length, 4,
          reason: '当 ExecutorStatus 新增枚举值时本测会红，强制 review statusBarStatusText 的状态文案');
    });
  });

  group('statusBarStatusIcon', () {
    test('running uses sync icon', () {
      expect(statusBarStatusIcon(ExecutorStatus.running), Icons.sync);
    });

    test('non-running statuses use info_outline icon', () {
      expect(statusBarStatusIcon(ExecutorStatus.idle), Icons.info_outline);
      expect(statusBarStatusIcon(ExecutorStatus.paused), Icons.info_outline);
      expect(statusBarStatusIcon(ExecutorStatus.completed), Icons.info_outline);
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      // statusBarStatusIcon 是二元分类（running=sync / 其它=info_outline），新增 enum
      // 必须决策落入哪一类，避免新值默认走 info_outline 而真应该展示动画反馈。
      expect(ExecutorStatus.values.length, 4,
          reason: '当 ExecutorStatus 新增枚举值时本测会红，强制 review statusBarStatusIcon 的 sync/info_outline 二元分类');
    });
  });

  group('statusBarStatusTooltip（Step 26 - 第二十二层 hover）', () {
    test('idle 给出"无任务可启动"语义', () {
      final tip = statusBarStatusTooltip(ExecutorStatus.idle);
      expect(tip, contains('就绪'));
      expect(tip, contains('开始'));
    });

    test('running 给出"正在执行"语义', () {
      final tip = statusBarStatusTooltip(ExecutorStatus.running);
      expect(tip, contains('运行中'));
      expect(tip, contains('队列'));
    });

    test('paused 给出"需人工处理"引导', () {
      final tip = statusBarStatusTooltip(ExecutorStatus.paused);
      expect(tip, contains('等待处理'));
      expect(tip, anyOf(contains('暂停'), contains('失败')));
    });

    test('completed 给出"全部结束"确认', () {
      final tip = statusBarStatusTooltip(ExecutorStatus.completed);
      expect(tip, contains('已完成'));
      expect(tip, contains('全部'));
    });

    test('扩展文案以 statusBarStatusText 短文为前缀（hover 是它的"超集补充"）', () {
      for (final status in ExecutorStatus.values) {
        expect(
          statusBarStatusTooltip(status).startsWith(statusBarStatusText(status)),
          isTrue,
          reason: 'hover 文案应以短文 "${statusBarStatusText(status)}" 起手，避免与短文割裂',
        );
      }
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      expect(ExecutorStatus.values.length, 4,
          reason: '当 ExecutorStatus 新增枚举值时本测会红，强制 review statusBarStatusTooltip 的扩展语义');
    });
  });

  group('statusBarLogButtonTooltip（Step 26 - 第二十二层 hover）', () {
    test('hasLog=true 给出"查看日志"指引', () {
      final tip = statusBarLogButtonTooltip(hasLog: true);
      expect(tip, contains('查看'));
      expect(tip, contains('日志'));
    });

    test('hasLog=false 给出"为什么按不动"解释', () {
      final tip = statusBarLogButtonTooltip(hasLog: false);
      expect(tip, contains('暂无'));
      expect(tip, contains('日志'));
    });

    test('两态文案不相等，确保 hover 真的能区分 enabled/disabled', () {
      expect(
        statusBarLogButtonTooltip(hasLog: true),
        isNot(equals(statusBarLogButtonTooltip(hasLog: false))),
      );
    });
  });
}
