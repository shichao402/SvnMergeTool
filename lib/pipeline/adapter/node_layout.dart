/// 节点布局常量和计算工具
/// 
/// 统一所有节点创建的布局逻辑，确保：
/// - 编辑器节点和执行节点使用相同的布局参数
/// - 端口位置计算一致
library;

import 'dart:math' as math;
import 'dart:ui';

/// 节点布局常量和计算工具
class NodeLayout {
  // ===== 尺寸常量 =====
  
  /// 标题栏高度（图标 + 名称）
  static const double headerHeight = 28.0;
  
  /// 端口垂直间距
  static const double portSpacing = 22.0;
  
  /// 端口区域顶部边距（标题栏下方到第一个端口的距离）
  static const double portAreaTopPadding = 18.0;
  
  /// 端口区域底部边距
  static const double portAreaBottomPadding = 18.0;
  
  /// 节点最小宽度
  static const double minWidth = 120.0;
  
  /// 节点最大宽度
  static const double maxWidth = 220.0;
  
  /// 节点内边距（水平）
  static const double horizontalPadding = 8.0;
  
  /// 端口标签估算字符宽度（中文约 12px，英文约 7px，取平均）
  static const double charWidth = 9.0;
  
  /// 标题字符宽度（稍大）
  static const double titleCharWidth = 10.0;
  
  /// 图标宽度 + 间距
  static const double iconWidth = 20.0;
  
  // ===== 间距常量 =====
  
  /// 节点水平间距
  static const double nodeHSpacing = 180.0;
  
  /// 节点垂直间距
  static const double nodeVSpacing = 100.0;
  
  // ===== 计算方法 =====
  
  /// 计算节点尺寸
  /// 
  /// 根据标题、输入端口名、输出端口名计算合适的节点尺寸
  static Size calculateSize({
    required String title,
    required List<String> inputPortNames,
    required List<String> outputPortNames,
  }) {
    final width = calculateWidth(
      title: title,
      inputPortNames: inputPortNames,
      outputPortNames: outputPortNames,
    );
    final height = calculateHeight(inputPortNames.length, outputPortNames.length);
    return Size(width, height);
  }
  
  /// 计算节点宽度
  /// 
  /// 考虑：标题长度、左侧端口名最大长度、右侧端口名最大长度
  static double calculateWidth({
    required String title,
    required List<String> inputPortNames,
    required List<String> outputPortNames,
  }) {
    // 标题宽度 = 图标 + 标题文字
    final titleWidth = iconWidth + title.length * titleCharWidth + horizontalPadding * 2;
    
    // 端口区域宽度 = 左侧端口名 + 中间间隔 + 右侧端口名
    final maxInputLen = inputPortNames.isEmpty 
        ? 0 
        : inputPortNames.map((n) => n.length).reduce(math.max);
    final maxOutputLen = outputPortNames.isEmpty 
        ? 0 
        : outputPortNames.map((n) => n.length).reduce(math.max);
    
    // 端口名宽度 + 端口图标宽度(约10) + 间隔
    final portAreaWidth = (maxInputLen + maxOutputLen) * charWidth + 40;
    
    // 取最大值，并限制在范围内
    final width = math.max(titleWidth, portAreaWidth);
    return width.clamp(minWidth, maxWidth);
  }
  
  /// 计算节点高度
  /// 
  /// 高度 = 标题栏 + 端口区域（端口数 × 间距 + 上下边距）
  static double calculateHeight(int inputCount, int outputCount) {
    final maxPorts = math.max(inputCount, outputCount);
    if (maxPorts == 0) {
      return headerHeight + portAreaTopPadding + portAreaBottomPadding;
    }
    
    // 端口区域高度 = (端口数 - 1) × 间距 + 上下边距
    // 第一个端口在 topPadding 处，最后一个端口在 bottomPadding 前
    final portAreaHeight = maxPorts == 1 
        ? portAreaTopPadding + portAreaBottomPadding
        : (maxPorts - 1) * portSpacing + portAreaTopPadding + portAreaBottomPadding;
    
    return headerHeight + portAreaHeight;
  }
  
  /// 计算端口 Y 偏移
  /// 
  /// 第一个端口从标题栏下方开始，后续端口等距分布
  static double calculatePortOffsetY(int index, int totalPorts) {
    // 第一个端口位置 = 标题栏高度 + 顶部边距
    final firstPortY = headerHeight + portAreaTopPadding;
    return firstPortY + index * portSpacing;
  }
}
