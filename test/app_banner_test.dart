import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/utils/app_banner.dart';

void main() {
  tearDown(() {
    AppBanner.cancelPendingHideTimer();
    AppBanner.dismissForTest();
  });

  group('bannerPaletteForKind', () {
    testWidgets('success 使用绿色背景', (tester) async {
      late AppBannerPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = bannerPaletteForKind(AppBannerKind.success, context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(palette.backgroundColor, Colors.green);
      expect(palette.contentColor, Colors.white);
    });

    testWidgets('error 使用红色背景', (tester) async {
      late AppBannerPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = bannerPaletteForKind(AppBannerKind.error, context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(palette.backgroundColor, Colors.red);
    });

    testWidgets('warning 使用橙色背景', (tester) async {
      late AppBannerPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = bannerPaletteForKind(AppBannerKind.warning, context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(palette.backgroundColor, Colors.orange);
    });
  });

  group('AppBanner.showContext', () {
    testWidgets('展示 Overlay 横幅并在 duration 后自动关闭', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppBanner.showContext(
                      context,
                      message: '测试横幅',
                      kind: AppBannerKind.info,
                      duration: const Duration(milliseconds: 500),
                    );
                  },
                  child: const Text('显示'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('显示'));
      await tester.pump();
      expect(find.text('测试横幅'), findsOneWidget);
      expect(find.byKey(AppBanner.overlayKey), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(AppBanner.overlayKey), findsNothing);
    });

    testWidgets('带 action 按钮时展示并可点击', (tester) async {
      var actionTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppBanner.showContext(
                      context,
                      message: '导出完成',
                      actionLabel: '打开',
                      onAction: () => actionTapped = true,
                      duration: Duration.zero,
                    );
                  },
                  child: const Text('显示'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('显示'));
      await tester.pumpAndSettle();
      expect(find.text('打开'), findsOneWidget);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(actionTapped, isTrue);
      expect(find.byKey(AppBanner.overlayKey), findsNothing);
    });

    testWidgets('error 横幅使用红色背景', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppBanner.showContext(
                      context,
                      message: '操作失败',
                      kind: AppBannerKind.error,
                      duration: Duration.zero,
                    );
                  },
                  child: const Text('显示'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('显示'));
      await tester.pump();

      final material = tester.widget<Material>(
        find.byKey(AppBanner.bannerMaterialKey),
      );
      expect(material.color, Colors.red);
      expect(find.text('操作失败'), findsOneWidget);
    });

    testWidgets('Overlay 横幅不推动 Scaffold body 布局', (tester) async {
      final bodyKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  key: bodyKey,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        AppBanner.showContext(
                          context,
                          message: '浮层提示',
                          duration: Duration.zero,
                        );
                      },
                      child: const Text('显示'),
                    ),
                    const Expanded(child: Placeholder()),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      final topBefore = tester.getTopLeft(find.byKey(bodyKey));

      await tester.tap(find.text('显示'));
      await tester.pump();

      final topAfter = tester.getTopLeft(find.byKey(bodyKey));

      expect(find.text('浮层提示'), findsOneWidget);
      expect(topAfter, topBefore);
    });
  });
}
