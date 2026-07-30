import 'package:flutter/material.dart' show Colors, Icons, showMenu, PopupMenuItem, RelativeRect;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

class PasteHelper {
  /// 弹出自定义的粘贴菜单
  static void showPasteMenu(BuildContext context, Offset globalPosition, TextEditingController controller) async {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    final isDark = fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final result = await showMenu<String>(
      context: context,
      position: position,
      color: isDark ? const Color(0xFF25343D) : Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'paste',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.paste_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87),
              const SizedBox(width: 8),
              Text('粘贴', style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ],
    );

    if (result == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        final text = data.text!;
        final selection = controller.selection;
        if (selection.isValid) {
          final start = selection.start;
          final end = selection.end;
          final currentText = controller.text;
          final newText = currentText.replaceRange(start, end, text);
          controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: start + text.length),
          );
        } else {
          controller.text = controller.text + text;
        }
      }
    }
  }

  /// 构建用于文本框末尾的粘贴后缀图标
  static Widget buildPasteSuffix({
    required BuildContext context,
    required TextEditingController controller,
    String tooltipMessage = '粘贴密钥',
  }) {
    return fluent.Tooltip(
      message: tooltipMessage,
      child: fluent.IconButton(
        icon: const Icon(Icons.paste_rounded, size: 16),
        onPressed: () async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data != null && data.text != null) {
            final text = data.text!;
            final selection = controller.selection;
            if (selection.isValid) {
              final start = selection.start;
              final end = selection.end;
              final currentText = controller.text;
              final newText = currentText.replaceRange(start, end, text);
              controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: start + text.length),
              );
            } else {
              controller.text = controller.text + text;
            }
          }
        },
      ),
    );
  }
}
