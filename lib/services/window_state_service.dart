/// 桌面窗口位置和大小持久化服务。
///
/// 负责在 macOS / Windows 上恢复上次窗口 bounds，并在移动、调整、关闭时保存。
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'logger_service.dart';
import 'storage_service.dart';

@visibleForTesting
const Size kDefaultWindowSize = Size(1280, 720);

@visibleForTesting
const Size kMinimumReasonableVisibleSize = Size(160, 120);

@visibleForTesting
const Size kMinimumFallbackWindowSize = Size(640, 480);

@visibleForTesting
const double kMinimumVisibleFraction = 0.15;

@visibleForTesting
enum WindowBoundsResolutionReason {
  restoredSavedBounds,
  noSavedBounds,
  savedBoundsOffscreen,
  noDisplayAreas,
}

@visibleForTesting
class WindowBoundsResolution {
  final Rect bounds;
  final WindowBoundsResolutionReason reason;

  const WindowBoundsResolution({
    required this.bounds,
    required this.reason,
  });
}

@visibleForTesting
bool isUsableDisplayArea(Rect area) {
  return area.left.isFinite &&
      area.top.isFinite &&
      area.width.isFinite &&
      area.height.isFinite &&
      area.width > 0 &&
      area.height > 0;
}

@visibleForTesting
Rect displayVisibleBounds(Display display) {
  final position = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  return position & size;
}

double _rectArea(Rect rect) {
  if (rect.width <= 0 || rect.height <= 0) {
    return 0;
  }
  return rect.width * rect.height;
}

@visibleForTesting
bool hasReasonableDisplayIntersection(
  Rect windowBounds,
  List<Rect> displayVisibleAreas, {
  Size minimumVisibleSize = kMinimumReasonableVisibleSize,
  double minimumVisibleFraction = kMinimumVisibleFraction,
}) {
  if (!isStorableWindowBounds(windowBounds)) {
    return false;
  }

  final windowArea = _rectArea(windowBounds);
  if (windowArea <= 0) {
    return false;
  }

  for (final area in displayVisibleAreas.where(isUsableDisplayArea)) {
    final intersection = windowBounds.intersect(area);
    final intersectionArea = _rectArea(intersection);
    if (intersectionArea <= 0) {
      continue;
    }

    final hasEnoughDragSurface =
        intersection.width >= minimumVisibleSize.width &&
            intersection.height >= minimumVisibleSize.height;
    final hasEnoughArea =
        intersectionArea / windowArea >= minimumVisibleFraction;
    if (hasEnoughDragSurface || hasEnoughArea) {
      return true;
    }
  }

  return false;
}

@visibleForTesting
Rect centeredFallbackWindowBounds(
  Rect displayVisibleArea, {
  Size defaultSize = kDefaultWindowSize,
  Size minimumSize = kMinimumFallbackWindowSize,
}) {
  final width = math.min(
    defaultSize.width,
    math.max(minimumSize.width, displayVisibleArea.width),
  );
  final height = math.min(
    defaultSize.height,
    math.max(minimumSize.height, displayVisibleArea.height),
  );

  return Rect.fromLTWH(
    displayVisibleArea.left + (displayVisibleArea.width - width) / 2,
    displayVisibleArea.top + (displayVisibleArea.height - height) / 2,
    width,
    height,
  );
}

@visibleForTesting
WindowBoundsResolution resolveInitialWindowBounds({
  required Rect? savedBounds,
  required List<Rect> displayVisibleAreas,
}) {
  final usableAreas = displayVisibleAreas.where(isUsableDisplayArea).toList();

  if (usableAreas.isEmpty) {
    return WindowBoundsResolution(
      bounds: savedBounds ?? (Offset.zero & kDefaultWindowSize),
      reason: WindowBoundsResolutionReason.noDisplayAreas,
    );
  }

  if (savedBounds != null &&
      hasReasonableDisplayIntersection(savedBounds, usableAreas)) {
    return WindowBoundsResolution(
      bounds: savedBounds,
      reason: WindowBoundsResolutionReason.restoredSavedBounds,
    );
  }

  return WindowBoundsResolution(
    bounds: centeredFallbackWindowBounds(usableAreas.first),
    reason: savedBounds == null
        ? WindowBoundsResolutionReason.noSavedBounds
        : WindowBoundsResolutionReason.savedBoundsOffscreen,
  );
}

String _formatBounds(Rect bounds) {
  return 'x=${bounds.left.toStringAsFixed(0)}, '
      'y=${bounds.top.toStringAsFixed(0)}, '
      'w=${bounds.width.toStringAsFixed(0)}, '
      'h=${bounds.height.toStringAsFixed(0)}';
}

class WindowStateService with WindowListener {
  static final WindowStateService _instance = WindowStateService._internal();
  factory WindowStateService() => _instance;
  WindowStateService._internal();

  final StorageService _storageService = StorageService();

  Timer? _saveTimer;
  bool _initialized = false;
  bool _isClosing = false;

  bool get _isSupportedDesktop => Platform.isMacOS || Platform.isWindows;

  Future<void> initAndRestore() async {
    if (!_isSupportedDesktop || _initialized) {
      return;
    }

    try {
      await windowManager.ensureInitialized();

      final savedBounds = await _storageService.getWindowBounds();
      final displays = await screenRetriever.getAllDisplays();
      final visibleAreas = displays.map(displayVisibleBounds).toList();
      final resolution = resolveInitialWindowBounds(
        savedBounds: savedBounds,
        displayVisibleAreas: visibleAreas,
      );

      await windowManager.setBounds(resolution.bounds);
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      _initialized = true;

      switch (resolution.reason) {
        case WindowBoundsResolutionReason.restoredSavedBounds:
          AppLogger.app.info('已恢复窗口布局：${_formatBounds(resolution.bounds)}');
          break;
        case WindowBoundsResolutionReason.noSavedBounds:
          AppLogger.app
              .info('未找到已保存窗口布局，使用默认居中布局：${_formatBounds(resolution.bounds)}');
          break;
        case WindowBoundsResolutionReason.savedBoundsOffscreen:
          AppLogger.app.warn(
            '已保存窗口布局不在当前屏幕可见区域内，回退默认布局：${_formatBounds(resolution.bounds)}',
          );
          break;
        case WindowBoundsResolutionReason.noDisplayAreas:
          AppLogger.app.warn(
            '无法获取显示器可见区域，使用基础窗口布局：${_formatBounds(resolution.bounds)}',
          );
          break;
      }
    } catch (e, stackTrace) {
      AppLogger.app.error('窗口布局初始化失败，使用平台默认窗口布局', e, stackTrace);
    }
  }

  @override
  void onWindowMoved() {
    _scheduleSave('移动');
  }

  @override
  void onWindowResized() {
    _scheduleSave('调整大小');
  }

  @override
  void onWindowMaximize() {
    _scheduleSave('最大化');
  }

  @override
  void onWindowUnmaximize() {
    _scheduleSave('还原');
  }

  @override
  void onWindowClose() {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    unawaited(_saveAndClose());
  }

  void _scheduleSave(String reason) {
    if (!_initialized || _isClosing) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveCurrentBounds(reason));
    });
  }

  Future<void> _saveCurrentBounds(String reason) async {
    try {
      if (await windowManager.isMinimized()) {
        return;
      }
      final bounds = await windowManager.getBounds();
      if (!isStorableWindowBounds(bounds)) {
        AppLogger.app.warn('跳过无效窗口布局保存：${_formatBounds(bounds)}');
        return;
      }
      await _storageService.saveWindowBounds(bounds);
      AppLogger.app.info('已保存窗口布局（$reason）：${_formatBounds(bounds)}');
    } catch (e, stackTrace) {
      AppLogger.app.error('保存窗口布局失败', e, stackTrace);
    }
  }

  Future<void> _saveAndClose() async {
    _saveTimer?.cancel();
    await _saveCurrentBounds('关闭');
    windowManager.removeListener(this);
    await windowManager.destroy();
  }
}
