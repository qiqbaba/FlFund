import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

/// 构建针对未寻优/策略为空单元格的提示 Badge
Widget buildUnoptimizedBadge({
  required bool isSell,
  required Map<String, dynamic>? optimalStrategy,
  double fontSize = 11,
}) {
  String label = '未寻优';
  String tooltipMessage = '';

  final bool hasRecord = optimalStrategy != null;
  final bool hasBuyStrategy = hasRecord && optimalStrategy['buy_days'] != null;
  final bool hasSellStrategy = hasRecord && optimalStrategy['sell_x'] != null;

  if (isSell) {
    if (hasBuyStrategy && !hasSellStrategy) {
      label = '未寻优';
      tooltipMessage =
          '未生成卖出策略：买入策略已生效，但历史大涨后回调样本不足 3 次，按稳健性规则未生成卖出策略。';
    } else {
      label = '未寻优';
      tooltipMessage =
          '未生成卖出策略：尚未对此基金运行卖出寻优，或历史大涨后回调样本不足 3 次。';
    }
  } else {
    if (hasRecord && !hasBuyStrategy) {
      label = '无有效策略';
      tooltipMessage =
          '无有效策略：已运行参数寻优，但历史净值未能筛选出满足高胜率与稳健性要求的买入策略。';
    } else {
      label = '未寻优';
      tooltipMessage =
          '未生成买入策略：尚未对此基金运行寻优，或历史净值未能筛选出满足高胜率要求的买入参数。';
    }
  }

  return fluent.Tooltip(
    message: tooltipMessage,
    useMousePosition: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.orange,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
        ),
      ),
    ),
  );
}
