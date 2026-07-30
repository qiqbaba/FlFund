import 'package:flutter/material.dart';

export 'number_formatter.dart';

/// 统一的红绿对比度优化配色管理类
class ThemeColors {
  // === 红绿文本颜色 (对应涨跌) ===

  /// 红色文本 (上涨 / 高估)
  ///
  /// - 浅色模式下采用深红色 (Color(0xFFC62828))，确保与白底形成高对比度。
  /// - 深色模式下采用明亮轻红 (Color(0xFFE57373))，确保夜间清晰可辨。
  static Color getRedText(bool isDark) {
    return isDark ? const Color(0xFFE57373) : const Color(0xFFC62828);
  }

  /// 绿色文本 (下跌 / 低估)
  ///
  /// - 浅色模式下采用深森林绿 (Color(0xFF2E7D32))，将对比度拉升至安全范围。
  /// - 深色模式下采用明亮轻绿 (Color(0xFF81C784))。
  static Color getGreenText(bool isDark) {
    return isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
  }

  /// 默认状态/正常状态文本颜色
  static Color getNormalText(bool isDark) {
    return isDark ? Colors.white70 : Colors.black87;
  }

  // === 百分位背景与文本色彩 (对应低估/高估卡片或单元格) ===

  /// 低估单元格背景色 (绿色系)
  static Color getLowPercentileBg(bool isDark) {
    return isDark
        ? const Color(0xFF1B5E20).withValues(alpha: 0.65)
        : const Color(0xFFA5D6A7);
  }

  /// 低估单元格文字颜色 (绿色系)
  static Color getLowPercentileText(bool isDark) {
    return isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20);
  }

  /// 高估单元格背景色 (红色系)
  static Color getHighPercentileBg(bool isDark) {
    return isDark
        ? const Color(0xFFB71C1C).withValues(alpha: 0.65)
        : const Color(0xFFEF9A9A);
  }

  /// 高估单元格文字颜色 (红色系)
  static Color getHighPercentileText(bool isDark) {
    return isDark ? const Color(0xFFFF8A80) : const Color(0xFFB71C1C);
  }

  // === 强周期模块专用状态色 ===

  /// 萧条筑底期状态色
  static Color getDepressionColor(bool isDark) {
    return isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
  }

  /// 复苏拉升期状态色
  static Color getRecoveryColor(bool isDark) {
    return isDark ? const Color(0xFF66BB6A) : const Color(0xFF43A047);
  }

  /// 均衡期状态色
  static Color getBalanceColor(bool isDark) {
    return isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
  }

  /// 繁荣后期状态色
  static Color getProsperityColor(bool isDark) {
    return isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
  }

  /// 过热泡沫期状态色
  static Color getBubbleColor(bool isDark) {
    return isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F);
  }
}
