import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'scaled_checkbox.dart';
import '../../core/utils/number_formatter.dart';

class HoldingDialog extends StatefulWidget {
  final String fundCode;
  final String fundName;
  final bool initialIsHeld;
  final double initialAmount;
  final double initialYieldRate;
  final Function(bool isHeld, double amount, double yieldRate) onSave;

  const HoldingDialog({
    super.key,
    required this.fundCode,
    required this.fundName,
    required this.initialIsHeld,
    required this.initialAmount,
    required this.initialYieldRate,
    required this.onSave,
  });

  @override
  State<HoldingDialog> createState() => _HoldingDialogState();
}

class _HoldingDialogState extends State<HoldingDialog> {
  late bool _isHeld;
  late TextEditingController _amountController;
  late TextEditingController _yieldController;

  @override
  void initState() {
    super.initState();
    _isHeld = widget.initialIsHeld;
    _amountController = TextEditingController(
      text: widget.initialAmount > 0 ? widget.initialAmount.toThousand(precision: 2) : '',
    );
    _yieldController = TextEditingController(
      text: widget.initialYieldRate > 0 ? widget.initialYieldRate.toThousand(precision: 2) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _yieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return fluent.ContentDialog(
      title: Text(
        '修改持有信息 - ${widget.fundName}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: fluent.Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '基金代码: ${widget.fundCode}',
            style: const TextStyle(color: fluent.Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ScaledCheckbox(
            checked: _isHeld,
            onChanged: (v) {
              setState(() {
                _isHeld = v ?? false;
              });
            },
            content: const Text('我已持有该基金(场外)'),
          ),
          if (_isHeld) ...[
            const SizedBox(height: 16),
            const Text('持有金额 (元)', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            fluent.TextBox(
              controller: _amountController,
              placeholder: '输入持有本金，例如: 10,000.00',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^[0-9,]*\.?[0-9]{0,2}')),
              ],
            ),
            const SizedBox(height: 12),
            const Text('持有收益率 (%)', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            fluent.TextBox(
              controller: _yieldController,
              placeholder: '输入持仓收益率，例如: 5.5 (代表 5.5%)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9,]*\.?[0-9]{0,4}')),
              ],
            ),
          ],
        ],
      ),
      actions: [
        fluent.Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        fluent.FilledButton(
          child: const Text('保存'),
          onPressed: () {
            double amount = 0.0;
            double yieldRate = 0.0;
            if (_isHeld) {
              amount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
              yieldRate = double.tryParse(_yieldController.text.replaceAll(',', '')) ?? 0.0;
            }
            widget.onSave(_isHeld, amount, yieldRate);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
