import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/window_state_service.dart';

void main() {
  group('hasReasonableDisplayIntersection', () {
    test('窗口与当前屏幕有足够交集 → true', () {
      expect(
        hasReasonableDisplayIntersection(
          const Rect.fromLTWH(100, 100, 1280, 720),
          [const Rect.fromLTWH(0, 0, 1920, 1080)],
        ),
        isTrue,
      );
    });

    test('窗口只剩极窄边缘在屏幕内 → false', () {
      expect(
        hasReasonableDisplayIntersection(
          const Rect.fromLTWH(1900, 100, 1280, 720),
          [const Rect.fromLTWH(0, 0, 1920, 1080)],
        ),
        isFalse,
      );
    });

    test('负坐标外接屏仍按当前显示器区域判断 → true', () {
      expect(
        hasReasonableDisplayIntersection(
          const Rect.fromLTWH(-1300, 100, 800, 600),
          [
            const Rect.fromLTWH(0, 0, 1920, 1080),
            const Rect.fromLTWH(-1440, 0, 1440, 900),
          ],
        ),
        isTrue,
      );
    });
  });

  group('resolveInitialWindowBounds', () {
    test('已保存窗口在任一显示器可见区域内 → 使用保存值', () {
      const savedBounds = Rect.fromLTWH(-1300, 100, 800, 600);
      final resolution = resolveInitialWindowBounds(
        savedBounds: savedBounds,
        displayVisibleAreas: const [
          Rect.fromLTWH(0, 0, 1920, 1080),
          Rect.fromLTWH(-1440, 0, 1440, 900),
        ],
      );

      expect(
          resolution.reason, WindowBoundsResolutionReason.restoredSavedBounds);
      expect(resolution.bounds, savedBounds);
    });

    test('已保存窗口在已拔掉外接屏位置 → 回退到主屏居中', () {
      final resolution = resolveInitialWindowBounds(
        savedBounds: const Rect.fromLTWH(2600, 100, 1280, 720),
        displayVisibleAreas: const [Rect.fromLTWH(0, 0, 1920, 1080)],
      );

      expect(
          resolution.reason, WindowBoundsResolutionReason.savedBoundsOffscreen);
      expect(resolution.bounds, const Rect.fromLTWH(320, 180, 1280, 720));
    });

    test('没有保存值 → 使用主屏居中默认窗口', () {
      final resolution = resolveInitialWindowBounds(
        savedBounds: null,
        displayVisibleAreas: const [Rect.fromLTWH(0, 0, 1440, 900)],
      );

      expect(resolution.reason, WindowBoundsResolutionReason.noSavedBounds);
      expect(resolution.bounds, const Rect.fromLTWH(80, 90, 1280, 720));
    });

    test('无法获取显示器区域且有保存值 → 保留保存值', () {
      const savedBounds = Rect.fromLTWH(100, 100, 1000, 700);
      final resolution = resolveInitialWindowBounds(
        savedBounds: savedBounds,
        displayVisibleAreas: const [],
      );

      expect(resolution.reason, WindowBoundsResolutionReason.noDisplayAreas);
      expect(resolution.bounds, savedBounds);
    });
  });
}
