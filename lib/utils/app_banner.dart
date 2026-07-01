import 'dart:async';

import 'package:flutter/material.dart';

/// 顶部横幅语义类型（对应原 SnackBar 颜色语义）。
enum AppBannerKind {
  info,
  success,
  error,
  warning,
}

/// 统一顶部浮层提示，替代 MaterialBanner / 底部 SnackBar。
///
/// 通过 [OverlayEntry] 插入全局 Overlay，不参与 Scaffold body 布局，
/// 因此不会把页面内容往下推或影响底部「开始合并」等操作区域。
class AppBanner {
  AppBanner._();

  static const Duration defaultDuration = Duration(seconds: 4);

  @visibleForTesting
  static const Key overlayKey = Key('app_banner_overlay');

  @visibleForTesting
  static const Key bannerMaterialKey = Key('app_banner_material');

  static OverlayEntry? _currentEntry;
  static Timer? _pendingHideTimer;

  @visibleForTesting
  static OverlayEntry? get currentEntryForTest => _currentEntry;

  @visibleForTesting
  static void cancelPendingHideTimer() {
    _pendingHideTimer?.cancel();
    _pendingHideTimer = null;
  }

  @visibleForTesting
  static void dismissForTest() {
    _removeEntry();
  }

  static void _removeEntry() {
    cancelPendingHideTimer();
    _currentEntry?.remove();
    _currentEntry = null;
  }

  /// 在 [overlayHostContext] 所在子树对应的 Overlay 上展示顶部浮层横幅。
  ///
  /// [overlayHostContext] 必须是 [Navigator] / [Overlay] 的子节点（如 [Scaffold] body），
  /// 不能是 [ScaffoldMessenger] 的 context。
  ///
  /// [actionLabel] / [onAction] 对偶原 SnackBarAction；点击后会先关闭横幅再执行回调。
  static void show(
    BuildContext overlayHostContext, {
    required String message,
    AppBannerKind kind = AppBannerKind.info,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.maybeOf(overlayHostContext)?.hideCurrentSnackBar();
    showContext(
      overlayHostContext,
      message: message,
      kind: kind,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 在已解析的 [overlay] 上展示横幅，适用于 `await` 前捕获 [OverlayState] 的场景。
  static void showOnOverlay(
    OverlayState overlay, {
    required String message,
    AppBannerKind kind = AppBannerKind.info,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _removeEntry();

    void dismiss() {
      if (_currentEntry != null) {
        _removeEntry();
      }
    }

    void onActionPressed() {
      dismiss();
      onAction?.call();
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return _AppBannerOverlay(
          key: overlayKey,
          message: message,
          kind: kind,
          actionLabel: actionLabel,
          onAction: onAction != null ? onActionPressed : null,
          onDismiss: dismiss,
        );
      },
    );

    _currentEntry = entry;
    overlay.insert(entry);

    if (duration > Duration.zero) {
      _pendingHideTimer = Timer(duration, () {
        _pendingHideTimer = null;
        dismiss();
      });
    }
  }

  static OverlayState? _findOverlay(BuildContext context) {
    final rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
    if (rootNavigator?.overlay != null) {
      return rootNavigator!.overlay;
    }
    return Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
  }

  static void showContext(
    BuildContext context, {
    required String message,
    AppBannerKind kind = AppBannerKind.info,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = _findOverlay(context);
    if (overlay == null) {
      return;
    }

    showOnOverlay(
      overlay,
      message: message,
      kind: kind,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _AppBannerOverlay extends StatefulWidget {
  const _AppBannerOverlay({
    super.key,
    required this.message,
    required this.kind,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  final String message;
  final AppBannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<_AppBannerOverlay> createState() => _AppBannerOverlayState();
}

class _AppBannerOverlayState extends State<_AppBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final palette = bannerPaletteForKind(widget.kind, context);
    final topInset = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topInset + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          key: AppBanner.bannerMaterialKey,
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          color: palette.backgroundColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(palette.icon, color: palette.contentColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(color: palette.contentColor),
                  ),
                ),
                if (widget.actionLabel != null && widget.onAction != null)
                  TextButton(
                    onPressed: widget.onAction,
                    child: Text(
                      widget.actionLabel!,
                      style: TextStyle(color: palette.actionColor),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _handleDismiss,
                    child: Text(
                      '关闭',
                      style: TextStyle(color: palette.actionColor),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class AppBannerPalette {
  const AppBannerPalette({
    required this.backgroundColor,
    required this.contentColor,
    required this.actionColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color contentColor;
  final Color actionColor;
  final IconData icon;
}

@visibleForTesting
AppBannerPalette bannerPaletteForKind(AppBannerKind kind, BuildContext context) {
  switch (kind) {
    case AppBannerKind.success:
      return const AppBannerPalette(
        backgroundColor: Colors.green,
        contentColor: Colors.white,
        actionColor: Colors.white,
        icon: Icons.check_circle_outline,
      );
    case AppBannerKind.error:
      return const AppBannerPalette(
        backgroundColor: Colors.red,
        contentColor: Colors.white,
        actionColor: Colors.white,
        icon: Icons.error_outline,
      );
    case AppBannerKind.warning:
      return const AppBannerPalette(
        backgroundColor: Colors.orange,
        contentColor: Colors.white,
        actionColor: Colors.white,
        icon: Icons.warning_amber_outlined,
      );
    case AppBannerKind.info:
      final scheme = Theme.of(context).colorScheme;
      return AppBannerPalette(
        backgroundColor: scheme.inverseSurface,
        contentColor: scheme.onInverseSurface,
        actionColor: scheme.primary,
        icon: Icons.info_outline,
      );
  }
}
