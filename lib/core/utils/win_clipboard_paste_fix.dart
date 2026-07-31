import 'dart:ui';

/// Windows 11 剪贴板历史（Win+V）粘贴修复
///
/// 背景：在 Windows 11 上点击剪贴板历史面板中的条目时，系统会向应用注入一组
/// 特殊的按键事件，但 Flutter 引擎会将其上报为错误的 physical/logical 键码
/// （physical=0x1600000000 的异常序列），导致框架无法识别为 Ctrl+V 快捷键，
/// 输入框始终无法收到粘贴内容。
/// 详见上游未修复问题：https://github.com/flutter/flutter/issues/143997
///
/// 方案：在 [PlatformDispatcher.onKeyData] 层拦截该异常事件序列，将其还原为
/// 标准的「Ctrl 按下 → V 按下 → V 抬起 → Ctrl 抬起」序列后再交还给框架，
/// 使系统级粘贴与普通 Ctrl+V 行为完全一致。
class WinClipboardPasteFix {
  WinClipboardPasteFix._();

  static final WinClipboardPasteFix instance = WinClipboardPasteFix._();

  /// 剪贴板历史注入事件上报的异常物理键码
  static const int _brokenPhysical = 0x1600000000;

  /// ControlLeft 的逻辑键码（异常序列均携带该值）
  static const int _logicalControlLeft = 0x200000100;

  /// USB HID 标准键码：ControlLeft 与 KeyV
  static const int _physicalControlLeft = 0x700e0;
  static const int _physicalKeyV = 0x70019;
  static const int _logicalKeyV = 0x76;

  bool _installed = false;
  bool _inBrokenSequence = false;

  /// 安装按键事件修正拦截器（仅需在应用启动时调用一次）
  void install() {
    if (_installed) return;
    final KeyDataCallback? original = PlatformDispatcher.instance.onKeyData;
    if (original == null) {
      // 框架回调尚未就绪，延迟重试一次
      Future.delayed(const Duration(seconds: 1), () {
        if (!_installed) install();
      });
      return;
    }
    _installed = true;
    PlatformDispatcher.instance.onKeyData = (KeyData data) {
      final KeyData? remapped = _remap(data);
      if (remapped == null) {
        // 序列中夹杂的无效空事件，直接吞掉，避免框架断言失败
        return true;
      }
      return original(remapped);
    };
  }

  /// 将剪贴板历史注入的异常事件序列还原为标准 Ctrl+V 序列；
  /// 返回 null 表示该事件应被拦截丢弃
  KeyData? _remap(KeyData data) {
    final bool isBrokenKey =
        data.physical == _brokenPhysical && data.logical == _logicalControlLeft;

    if (!_inBrokenSequence &&
        isBrokenKey &&
        data.type == KeyEventType.down &&
        !data.synthesized) {
      // 序列第 1 个事件 → ControlLeft 按下
      _inBrokenSequence = true;
      return _keyData(
          data, KeyEventType.down, _physicalControlLeft, _logicalControlLeft);
    }

    if (_inBrokenSequence) {
      if (isBrokenKey && data.type == KeyEventType.up && !data.synthesized) {
        // 序列第 2 个事件 → V 按下
        return _keyData(data, KeyEventType.down, _physicalKeyV, _logicalKeyV);
      }
      if (isBrokenKey && data.type == KeyEventType.down && data.synthesized) {
        // 序列第 3 个事件 → V 抬起
        return _keyData(data, KeyEventType.up, _physicalKeyV, _logicalKeyV);
      }
      if (isBrokenKey && data.type == KeyEventType.up && data.synthesized) {
        // 序列第 4 个事件 → ControlLeft 抬起，序列结束
        _inBrokenSequence = false;
        return _keyData(
            data, KeyEventType.up, _physicalControlLeft, _logicalControlLeft);
      }
      if (data.physical == 0 &&
          data.logical == 0 &&
          data.type == KeyEventType.down) {
        // 序列中夹杂的空事件，拦截丢弃
        return null;
      }
      // 出现其他事件说明不是目标序列，恢复正常状态
      _inBrokenSequence = false;
    }
    return data;
  }

  KeyData _keyData(
      KeyData source, KeyEventType type, int physical, int logical) {
    return KeyData(
      timeStamp: source.timeStamp,
      type: type,
      physical: physical,
      logical: logical,
      character: null,
      synthesized: false,
    );
  }
}
