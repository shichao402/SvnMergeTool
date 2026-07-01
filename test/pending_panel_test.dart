import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/screens/components/pending_panel.dart';

void main() {
  group('shouldShowSourceLabel', () {
    test('returns true only for non-empty string', () {
      expect(shouldShowSourceLabel('trunk'), isTrue);
    });

    test('returns false for null', () {
      expect(shouldShowSourceLabel(null), isFalse);
    });

    test('returns false for empty string', () {
      expect(shouldShowSourceLabel(''), isFalse);
    });
  });

  group('shouldShowSourceWarning', () {
    test('returns true only for non-empty string', () {
      expect(shouldShowSourceWarning('mismatch'), isTrue);
    });

    test('returns false for null', () {
      expect(shouldShowSourceWarning(null), isFalse);
    });

    test('returns false for empty string', () {
      expect(shouldShowSourceWarning(''), isFalse);
    });
  });

  group('shouldShowClearAction', () {
    test('returns true when there are pending revisions', () {
      expect(shouldShowClearAction(pendingRevisions: const [100]), isTrue);
    });

    test('returns false for empty pending list', () {
      expect(shouldShowClearAction(pendingRevisions: const []), isFalse);
    });
  });

  group('shouldShowAddButton', () {
    test('returns true when selectedCount > 0', () {
      expect(shouldShowAddButton(selectedCount: 1), isTrue);
      expect(shouldShowAddButton(selectedCount: 99), isTrue);
    });

    test('returns false when selectedCount == 0', () {
      expect(shouldShowAddButton(selectedCount: 0), isFalse);
    });

    test('returns false for negative (defensive)', () {
      // 不应该出现，但防御性断言：避免被 -1 等异常值误显示按钮。
      expect(shouldShowAddButton(selectedCount: -1), isFalse);
    });
  });

  group('formatPendingHeaderCount', () {
    test('renders count with 个 suffix', () {
      expect(formatPendingHeaderCount(0), '0 个');
      expect(formatPendingHeaderCount(3), '3 个');
      expect(formatPendingHeaderCount(123), '123 个');
    });
  });

  group('formatPendingItemPosition', () {
    test('converts 0-based index to 1-based label', () {
      expect(formatPendingItemPosition(0), '1');
      expect(formatPendingItemPosition(9), '10');
    });
  });

  group('formatPendingRemoveTooltip（Step 23 - 第十九层 hover）', () {
    test('renders 从待合并移除 with r-prefixed revision', () {
      expect(formatPendingRemoveTooltip(12345), '从待合并移除 r12345');
    });

    test('handles small revision', () {
      expect(formatPendingRemoveTooltip(1), '从待合并移除 r1');
    });

    test('handles zero revision (defensive)', () {
      // 不应出现，但防御性断言：模板对零值不会爆炸。
      expect(formatPendingRemoveTooltip(0), '从待合并移除 r0');
    });

    test('handles large revision', () {
      expect(formatPendingRemoveTooltip(999999), '从待合并移除 r999999');
    });

    test('handles negative (defensive)', () {
      // 不应出现，但防御性断言：异常值不破坏模板格式。
      expect(formatPendingRemoveTooltip(-1), '从待合并移除 r-1');
    });
  });

  group('formatPendingSourceLabelTooltip（Step 21）', () {
    test('returns full URL when summarize 真正裁切了 sourceLabel', () {
      // sourceLabel 是 summarize 后的末两段，sourceUrl 是完整路径
      expect(
        formatPendingSourceLabelTooltip(
          'branches/v2',
          'svn://server/repo/branches/v2',
        ),
        'svn://server/repo/branches/v2',
      );
    });

    test('returns empty when sourceLabel == sourceUrl trim 后字面相等', () {
      // summarize 没有真正裁切（segments 不足或恰好就是末两段）
      expect(
        formatPendingSourceLabelTooltip('trunk', 'trunk'),
        '',
      );
    });

    test('returns empty when sourceUrl 含前后空白但 trim 后等于 sourceLabel', () {
      expect(
        formatPendingSourceLabelTooltip('trunk', '  trunk  '),
        '',
      );
    });

    test('trims sourceUrl 前后空白 再返回', () {
      expect(
        formatPendingSourceLabelTooltip(
          'branches/v2',
          '  svn://server/repo/branches/v2  ',
        ),
        'svn://server/repo/branches/v2',
      );
    });

    test('returns empty when sourceUrl is null', () {
      expect(formatPendingSourceLabelTooltip('branches/v2', null), '');
    });

    test('returns empty when sourceUrl is empty/whitespace only', () {
      expect(formatPendingSourceLabelTooltip('branches/v2', ''), '');
      expect(formatPendingSourceLabelTooltip('branches/v2', '   '), '');
    });

    test('returns empty when sourceLabel is null', () {
      expect(
        formatPendingSourceLabelTooltip(
          null,
          'svn://server/repo/branches/v2',
        ),
        '',
      );
    });

    test('returns empty when sourceLabel is empty', () {
      expect(
        formatPendingSourceLabelTooltip(
          '',
          'svn://server/repo/branches/v2',
        ),
        '',
      );
    });
  });
}
