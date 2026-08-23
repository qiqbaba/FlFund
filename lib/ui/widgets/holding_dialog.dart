import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'scaled_checkbox.dart';
import '../../core/models/fund_info.dart';
import '../../core/utils/number_formatter.dart';

class HoldingDialog extends StatefulWidget {
  final String fundCode;
  final String fundName;
  final bool initialIsHeld;
  final double initialAmount;
  final double initialYieldRate;
  final FundType? initialFundType;
  final double initialShares;
  final double initialCostPrice;
  final Function(
    bool isHeld,
    double amount,
    double yieldRate, {
    FundType? fundType,
    double? shares,
    double? costPrice,
  }) onSave;

  const HoldingDialog({
    super.key,
    required this.fundCode,
    required this.fundName,
    required this.initialIsHeld,
    required this.initialAmount,
    required this.initialYieldRate,
    this.initialFundType,
    this.initialShares = 0.0,
    this.initialCostPrice = 0.0,
    required this.onSave,
  });

  @override
  State<HoldingDialog> createState() => _HoldingDialogState();
}

class _HoldingDialogState extends State<HoldingDialog> {
  late bool _isHeld;
  late FundType _fundType;
  late TextEditingController _amountController;
  late TextEditingController _yieldController;
  late TextEditingController _sharesController;
  late TextEditingController _costPriceController;

  @override
  void initState() {
    super.initState();
    _isHeld = widget.initialIsHeld;
    _fundType = widget.initialFundType ??
        FundInfo.autoDetectFundType(widget.fundCode);
    _amountController = TextEditingController(
      text: widget.initialAmount > 0
          ? widget.initialAmount.toThousand(precision: 2)
          : '',
    );
    _yieldController = TextEditingController(
      text: widget.initialYieldRate != 0.0
          ? widget.initialYieldRate.toThousand(precision: 2)
          : '',
    );
    _sharesController = TextEditingController(
      text: widget.initialShares > 0
          ? widget.initialShares.toStringAsFixed(0)
          : '',
    );
    _costPriceController = TextEditingController(
      text: widget.initialCostPrice > 0
          ? widget.initialCostPrice.toStringAsFixed(3)
          : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _yieldController.dispose();
    _sharesController.dispose();
    _costPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExchange = _fundType.isExchangeTraded;

    return fluent.ContentDialog(
      title: Text(
        '修改持有信息 - ${widget.fundName}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: fluent.Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '标的代码: ${widget.fundCode} (${FundInfo.getMarketPrefix(widget.fundCode).toUpperCase()})',
              style: const TextStyle(color: fluent.Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('标的类型: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                fluent.ComboBox<FundType>(
                  value: _fundType,
                  items: FundType.values.map((t) {
                    return fluent.ComboBoxItem<FundType>(
                      value: t,
                      child: Text(t.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _fundType = val;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            ScaledCheckbox(
              checked: _isHeld,
              onChanged: (v) {
                setState(() {
                  _isHeld = v ?? false;
                });
              },
              content: Text(isExchange ? '我已持有该标的 (场内交易)' : '我已持有该基金 (场外申购)'),
            ),
            if (_isHeld) ...[
              const SizedBox(height: 16),
              if (isExchange) ...[
                const Text('持仓数量 (股/份/手)', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                fluent.TextBox(
                  controller: _sharesController,
                  placeholder: '输入持仓数量，例如: 10000 (100手)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^[0-9,]*')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('持仓均价 / 成本价 (元)', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                fluent.TextBox(
                  controller: _costPriceController,
                  placeholder: '输入买入均价，例如: 1.250',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^[0-9,]*\.?[0-9]{0,4}')),
                  ],
                ),
              ] else ...[
                const Text('持有金额 (元)', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                fluent.TextBox(
                  controller: _amountController,
                  placeholder: '输入持有本金，例如: 10,000.00',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^[0-9,]*\.?[0-9]{0,2}')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('持有收益率 (%)', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                fluent.TextBox(
                  controller: _yieldController,
                  placeholder: '输入持仓收益率，例如: 5.5 (代表 5.5%)',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^-?[0-9,]*\.?[0-9]{0,4}')),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        fluent.Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        fluent.FilledButton(
          child: const Text('保存'),
          onPressed: () {
            // 以原值兜底：仅覆盖当前标的类型下可编辑的字段，
            // 避免误切换类型后把另一类型已录入的持仓数据静默清零
            double amount = widget.initialAmount;
            double yieldRate = widget.initialYieldRate;
            double shares = widget.initialShares;
            double costPrice = widget.initialCostPrice;

            if (_isHeld) {
              if (isExchange) {
                final sharesText =
                    _sharesController.text.replaceAll(',', '').trim();
                final costText =
                    _costPriceController.text.replaceAll(',', '').trim();
                if (sharesText.isNotEmpty) {
                  shares = double.tryParse(sharesText) ?? 0.0;
                }
                if (costText.isNotEmpty) {
                  costPrice = double.tryParse(costText) ?? 0.0;
                }
                final computedAmount = shares * costPrice;
                if (computedAmount > 0) {
                  amount = computedAmount;
                }
              } else {
                final amountText =
                    _amountController.text.replaceAll(',', '').trim();
                final yieldText =
                    _yieldController.text.replaceAll(',', '').trim();
                if (amountText.isNotEmpty) {
                  amount = double.tryParse(amountText) ?? 0.0;
                }
                if (yieldText.isNotEmpty) {
                  yieldRate = double.tryParse(yieldText) ?? 0.0;
                }
              }
            } else {
              amount = 0.0;
              yieldRate = 0.0;
              shares = 0.0;
              costPrice = 0.0;
            }
            widget.onSave(
              _isHeld,
              amount,
              yieldRate,
              fundType: _fundType,
              shares: shares,
              costPrice: costPrice,
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

