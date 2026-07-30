import 'package:flutter/material.dart' show Icons, Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

/// 可点击复制的文本组件
/// 点击后复制内容到剪贴板，并显示 SnackBar 提示
/// 支持通过 onLongPressStart / onSecondaryTapDown 转发长按/右键事件
class CopyableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final String copyLabel;
  final bool showCopyIcon;
  final double? iconSize;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureTapDownCallback? onSecondaryTapDown;

  const CopyableText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.copyLabel = '已复制',
    this.showCopyIcon = false,
    this.iconSize,
    this.onLongPressStart,
    this.onSecondaryTapDown,
  });

  void _onTap(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    fluent.displayInfoBar(
      context,
      builder: (context, close) => fluent.InfoBar(
        title: Text(copyLabel),
        content: Text(text),
        severity: fluent.InfoBarSeverity.success,
        onClose: close,
      ),
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      onLongPressStart: onLongPressStart,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              style: overflow != null
                  ? (style ?? const TextStyle()).copyWith(overflow: overflow)
                  : style,
              textAlign: textAlign,
              maxLines: maxLines,
            ),
          ),
          if (showCopyIcon) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.copy_rounded,
              size: iconSize ?? 12,
              color: Colors.grey,
            ),
          ],
        ],
      ),
    );
  }
}
