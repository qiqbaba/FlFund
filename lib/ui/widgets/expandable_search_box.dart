import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

class ExpandableSearchBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final double width;

  const ExpandableSearchBox({
    super.key,
    required this.controller,
    this.focusNode,
    required this.placeholder,
    this.onChanged,
    required this.width,
  });

  @override
  State<ExpandableSearchBox> createState() => _ExpandableSearchBoxState();
}

class _ExpandableSearchBoxState extends State<ExpandableSearchBox> {
  late final FocusNode _effectiveFocusNode;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    // 如果一开始 Controller 中有文字，直接默认展开
    _isExpanded = widget.controller.text.isNotEmpty;
    _effectiveFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (_effectiveFocusNode.hasFocus) {
      if (!_isExpanded) {
        setState(() {
          _isExpanded = true;
        });
        // 在下一帧重新请求焦点以确保已经渲染出来的 TextBox 能够正确获取光标
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _effectiveFocusNode.requestFocus();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;
    final double targetWidth = _isExpanded ? widget.width : 32.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: targetWidth,
      height: 32,
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: widget.width,
            child: _isExpanded ? _buildTextBox(isDark) : _buildSearchIconButton(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchIconButton(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 32,
        height: 32,
        child: fluent.Tooltip(
          message: widget.placeholder,
          child: fluent.IconButton(
            icon: Icon(
              Icons.search,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            style: fluent.ButtonStyle(
              backgroundColor: fluent.WidgetStateProperty.all(
                isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)
              ),
              shape: fluent.WidgetStateProperty.all(const CircleBorder()),
            ),
            onPressed: () {
              setState(() {
                _isExpanded = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _effectiveFocusNode.requestFocus();
                }
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextBox(bool isDark) {
    return fluent.TextBox(
      controller: widget.controller,
      focusNode: _effectiveFocusNode,
      placeholder: widget.placeholder,
      onChanged: (val) {
        widget.onChanged?.call(val);
      },
      prefix: const Padding(
        padding: EdgeInsets.only(left: 8.0),
        child: Icon(Icons.search, size: 14, color: Colors.grey),
      ),
      suffix: fluent.IconButton(
        icon: Icon(
          widget.controller.text.isNotEmpty ? Icons.clear : Icons.close,
          size: 12,
        ),
        onPressed: () {
          if (widget.controller.text.isNotEmpty) {
            widget.controller.clear();
            widget.onChanged?.call('');
            // 清空文本时保留展开状态，如果需要可在这里添加逻辑
            setState(() {});
          } else {
            setState(() {
              _isExpanded = false;
            });
            _effectiveFocusNode.unfocus();
          }
        },
      ),
    );
  }
}
