import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';

class ScaledCheckbox extends StatelessWidget {
  final bool? checked;
  final ValueChanged<bool?>? onChanged;
  final fluent.CheckboxThemeData? style;
  final Widget? content;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;

  const ScaledCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    this.style,
    this.content,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.scale = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final double visualSize = 20.0 * scale;

    Widget checkbox = SizedBox(
      width: visualSize,
      height: visualSize,
      child: OverflowBox(
        minWidth: 20.0,
        maxWidth: 20.0,
        minHeight: 20.0,
        maxHeight: 20.0,
        child: Transform.scale(
          scale: scale,
          child: fluent.Checkbox(
            checked: checked,
            onChanged: onChanged,
            style: style,
            semanticLabel: semanticLabel,
            focusNode: focusNode,
            autofocus: autofocus,
          ),
        ),
      ),
    );

    if (content == null) {
      return checkbox;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged != null
          ? () {
              if (checked == null) {
                onChanged!(true);
              } else {
                onChanged!(!checked!);
              }
            }
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          checkbox,
          const SizedBox(width: 4),
          Flexible(child: content!),
        ],
      ),
    );
  }
}
