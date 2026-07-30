import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/simulation_provider.dart';
import '../../core/fund_provider.dart';
import '../../core/utils/theme_colors.dart';
import '../widgets/fund_chart_dialog.dart';
import '../widgets/mobile_header.dart';
import '../widgets/copyable_text.dart';

class SimulationTab extends StatefulWidget {
  const SimulationTab({super.key});

  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  final TextEditingController _buyAmountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final simProvider = Provider.of<SimulationProvider>(context, listen: false);
    _buyAmountController.text =
        simProvider.defaultBuyAmount.toThousand(precision: 0);
  }

  @override
  void dispose() {
    _buyAmountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 渲染大卡片面板
  Widget _buildOverviewCard({
    required BuildContext context,
    required String title,
    required String value,
    required Color color,
    String? subTitle,
    String? subValue,
    Color? subColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subTitle != null && subValue != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    subTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    subValue,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: subColor ??
                          (isDark ? Colors.white70 : Colors.black87),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 二次重置账户的弹窗
  void _showResetDialog(BuildContext context, SimulationProvider simProvider) {
    final TextEditingController initBalController =
        TextEditingController(text: '1000000');
    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: const Text('重置模拟盘账户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('重置后，将清空当前所有持仓和历史交易记录。此操作不可撤销！',
                  style: TextStyle(color: Colors.orange)),
              const SizedBox(height: 16),
              const Text('请输入初始模拟资金 (元):'),
              const SizedBox(height: 8),
              fluent.TextBox(
                controller: initBalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                placeholder: '请输入初始资金',
              ),
            ],
          ),
          actions: [
            fluent.Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            fluent.FilledButton(
              style: fluent.ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.redAccent),
              ),
              child: const Text('确认重置'),
              onPressed: () {
                final double? val =
                    double.tryParse(initBalController.text.replaceAll(',', ''));
                if (val != null && val > 0) {
                  simProvider.resetAccount(val);
                  Navigator.pop(context);
                  fluent.displayInfoBar(
                    context,
                    builder: (context, close) => fluent.InfoBar(
                      title: const Text('重置成功'),
                      content: const Text('模拟盘已重置成功'),
                      severity: fluent.InfoBarSeverity.success,
                      onClose: close,
                    ),
                    duration: const Duration(seconds: 3),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 手动扫描信号二次确认
  void _triggerScan(BuildContext context, SimulationProvider simProvider,
      FundProvider fundProvider) async {
    fluent.displayInfoBar(
      context,
      builder: (context, close) => const fluent.InfoBar(
        title: Text('扫描中'),
        content: Text('正在拉取信号并扫描模拟交易...'),
        severity: fluent.InfoBarSeverity.info,
      ),
      duration: const Duration(seconds: 2),
    );
    await simProvider.checkAndExecute(fundProvider.myFunds.values.toList());
    if (!context.mounted) return;
    fluent.displayInfoBar(
      context,
      builder: (context, close) => fluent.InfoBar(
        title: const Text('扫描完成'),
        content: const Text('信号交易检测已运行完毕'),
        severity: fluent.InfoBarSeverity.success,
        onClose: close,
      ),
      duration: const Duration(seconds: 3),
    );
  }

  // 手动卖出平仓确认弹窗
  void _showSellConfirm(BuildContext context, SimulationProvider simProvider,
      SimulatedPosition pos) {
    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: const Text('确认手动平仓'),
          content: Text(
              '确认以当前价格 ￥${pos.currentPrice.toThousand(precision: 4)} 卖出全部持有的 ${pos.name} (${pos.code}) 吗？\n交易所得金额将返回模拟可用资金。'),
          actions: [
            fluent.Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            fluent.FilledButton(
              style: fluent.ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.redAccent),
              ),
              child: const Text('确认卖出'),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final success =
                    await simProvider.manualSell(pos.code, pos.currentPrice);
                navigator.pop();
                if (success && context.mounted) {
                  fluent.displayInfoBar(
                    context,
                    builder: (context, close) => fluent.InfoBar(
                      title: const Text('平仓成功'),
                      content: Text('已手动卖出 ${pos.name}'),
                      severity: fluent.InfoBarSeverity.success,
                      onClose: close,
                    ),
                    duration: const Duration(seconds: 3),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final simProvider = Provider.of<SimulationProvider>(context);
    final fundProvider = Provider.of<FundProvider>(context);
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    // 总览面板颜色
    final Color assetsColor = isDark ? Colors.white : Colors.black87;
    final double profit = simProvider.totalProfit;
    final double profitRate = simProvider.totalProfitRate;
    final Color profitColor = profit >= 0
        ? ThemeColors.getRedText(isDark)
        : ThemeColors.getGreenText(isDark);
    final String profitSign = profit >= 0 ? '+' : '';

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSmallScreen) const MobileHeader(title: '模拟盘'),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 顶部总览卡片
                  if (isSmallScreen)
                    Column(
                      children: [
                        _buildOverviewCard(
                          context: context,
                          title: '当前模拟总资产 (元)',
                          value:
                              '￥${simProvider.totalAssets.toThousand(precision: 2)}',
                          color: assetsColor,
                          subTitle: '初始资金',
                          subValue:
                              '￥${simProvider.initialBalance.toThousand(precision: 2)}',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildOverviewCard(
                          context: context,
                          title: '账户盈亏 / 收益率',
                          value:
                              '$profitSign￥${profit.toThousand(precision: 2)}',
                          color: profitColor,
                          subTitle: '总盈亏比例',
                          subValue:
                              '${profitRate.toThousand(precision: 2, showSign: true)}%',
                          subColor: profitColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildOverviewCard(
                          context: context,
                          title: '可用模拟资金 (元)',
                          value:
                              '￥${simProvider.availableBalance.toThousand(precision: 2)}',
                          color: assetsColor,
                          subTitle: '持仓总市值',
                          subValue:
                              '￥${simProvider.totalPositionValue.toThousand(precision: 2)}',
                          isDark: isDark,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _buildOverviewCard(
                            context: context,
                            title: '当前模拟总资产 (元)',
                            value:
                                '￥${simProvider.totalAssets.toThousand(precision: 2)}',
                            color: assetsColor,
                            subTitle: '初始资金',
                            subValue:
                                '￥${simProvider.initialBalance.toThousand(precision: 2)}',
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildOverviewCard(
                            context: context,
                            title: '账户盈亏 / 收益率',
                            value:
                                '$profitSign￥${profit.toThousand(precision: 2)}',
                            color: profitColor,
                            subTitle: '总盈亏比例',
                            subValue:
                                '${profitRate.toThousand(precision: 2, showSign: true)}%',
                            subColor: profitColor,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildOverviewCard(
                            context: context,
                            title: '可用模拟资金 (元)',
                            value:
                                '￥${simProvider.availableBalance.toThousand(precision: 2)}',
                            color: assetsColor,
                            subTitle: '持仓总市值',
                            subValue:
                                '￥${simProvider.totalPositionValue.toThousand(precision: 2)}',
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // 2. 自动交易配置模块
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.02)
                          : Colors.black.withValues(alpha: 0.015),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        // 第一行：自动交易开关 + 单笔买入定额
                        if (isSmallScreen)
                          Column(
                            children: [
                              Row(
                                children: [
                                  const Text('自动模拟交易:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  fluent.ToggleSwitch(
                                    checked: simProvider.isAutoTradeEnabled,
                                    onChanged: (val) {
                                      simProvider.toggleAutoTrade(val);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('单笔买入定额 (元):',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 120,
                                    child: fluent.TextBox(
                                      controller: _buyAmountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'^[0-9,]*')),
                                      ],
                                      onSubmitted: (val) {
                                        final double? parsed = double.tryParse(
                                            val.replaceAll(',', ''));
                                        if (parsed != null && parsed > 0) {
                                          simProvider
                                              .updateDefaultBuyAmount(parsed);
                                          fluent.displayInfoBar(
                                            context,
                                            builder: (context, close) =>
                                                fluent.InfoBar(
                                              title: const Text('修改成功'),
                                              content: Text(
                                                  '单笔买入定额已更新为 ￥${parsed.toThousand(precision: 0)}'),
                                              severity: fluent
                                                  .InfoBarSeverity.success,
                                              onClose: close,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              const Text('自动模拟交易:',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              fluent.ToggleSwitch(
                                checked: simProvider.isAutoTradeEnabled,
                                onChanged: (val) {
                                  simProvider.toggleAutoTrade(val);
                                },
                              ),
                              const Spacer(),
                              const Text('单笔买入定额 (元):',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 100,
                                child: fluent.TextBox(
                                  controller: _buyAmountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^[0-9,]*')),
                                  ],
                                  onSubmitted: (val) {
                                    final double? parsed = double.tryParse(
                                        val.replaceAll(',', ''));
                                    if (parsed != null && parsed > 0) {
                                      simProvider
                                          .updateDefaultBuyAmount(parsed);
                                      fluent.displayInfoBar(
                                        context,
                                        builder: (context, close) =>
                                            fluent.InfoBar(
                                          title: const Text('修改成功'),
                                          content: Text(
                                              '单笔买入定额已更新为 ￥${parsed.toThousand(precision: 0)}'),
                                          severity:
                                              fluent.InfoBarSeverity.success,
                                          onClose: close,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        // 第二行：操作按钮
                        if (isSmallScreen)
                          Column(
                            children: [
                              fluent.FilledButton(
                                child: const Row(
                                  children: [
                                    Icon(Icons.search_rounded, size: 14),
                                    SizedBox(width: 4),
                                    Text('立即扫描信号并交易'),
                                  ],
                                ),
                                onPressed: () => _triggerScan(
                                    context, simProvider, fundProvider),
                              ),
                              const SizedBox(height: 8),
                              fluent.Button(
                                style: fluent.ButtonStyle(
                                  foregroundColor:
                                      WidgetStateProperty.all(Colors.redAccent),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        size: 14, color: Colors.redAccent),
                                    SizedBox(width: 4),
                                    Text('重置账户'),
                                  ],
                                ),
                                onPressed: () =>
                                    _showResetDialog(context, simProvider),
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              fluent.FilledButton(
                                child: const Row(
                                  children: [
                                    Icon(Icons.search_rounded, size: 14),
                                    SizedBox(width: 4),
                                    Text('立即扫描信号并交易'),
                                  ],
                                ),
                                onPressed: () => _triggerScan(
                                    context, simProvider, fundProvider),
                              ),
                              const SizedBox(width: 12),
                              fluent.Button(
                                style: fluent.ButtonStyle(
                                  foregroundColor:
                                      WidgetStateProperty.all(Colors.redAccent),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        size: 14, color: Colors.redAccent),
                                    SizedBox(width: 4),
                                    Text('重置账户'),
                                  ],
                                ),
                                onPressed: () =>
                                    _showResetDialog(context, simProvider),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. 当前持仓表格
                  const Text('📊 当前模拟持仓',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (simProvider.positions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 36,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          const Text('当前无任何模拟持仓。',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)),
                          const Text('等待自选基金收盘净值或尾盘估值买入信号触发...',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: simProvider.positions.length,
                      itemBuilder: (context, index) {
                        final pos =
                            simProvider.positions.values.toList()[index];
                        final Color posProfitColor = pos.profit >= 0
                            ? ThemeColors.getRedText(isDark)
                            : ThemeColors.getGreenText(isDark);
                        final String posProfitSign = pos.profit >= 0 ? '+' : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: isSmallScreen
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 基金名称与代码
                                    GestureDetector(
                                      onTap: () {
                                        final assocFund =
                                            fundProvider.myFunds[pos.code];
                                        if (assocFund != null) {
                                          fluent.showDialog(
                                            context: context,
                                            builder: (context) =>
                                                FundChartDialog(
                                              fundCode: assocFund.code,
                                              fundName: assocFund.name,
                                              navs: assocFund.navs,
                                              dates: assocFund.dates,
                                              todayEstimateNav: double.tryParse(
                                                  assocFund.gsz),
                                              todayEstimatePct: double.tryParse(
                                                  assocFund.gszzl),
                                              todayEstimateTime:
                                                  assocFund.gztime,
                                            ),
                                          );
                                        } else {
                                          fluent.displayInfoBar(
                                            context,
                                            builder: (context, close) =>
                                                const fluent.InfoBar(
                                              title: Text('提示'),
                                              content: Text('该基金不在自选看板，无法查看走势'),
                                              severity: fluent
                                                  .InfoBarSeverity.warning,
                                            ),
                                          );
                                        }
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pos.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            pos.code,
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // 持仓成本/最新价
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('持仓成本/最新价',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11)),
                                        Text(
                                          '${pos.buyPrice.toThousand(precision: 4)} / ${pos.currentPrice.toThousand(precision: 4)}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontFamily: 'monospace'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // 持有份额/持仓市值
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('持有份额/持仓市值',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11)),
                                        Text(
                                          '${pos.volume.toThousand(precision: 0)} 份 / ￥${pos.amount.toThousand(precision: 2)}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontFamily: 'monospace'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // 浮动盈亏
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('持仓浮动盈亏',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11)),
                                        Text(
                                          '$posProfitSign￥${pos.profit.toThousand(precision: 2)} ($posProfitSign${pos.profitRate.toThousand(precision: 2)}%)',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: posProfitColor,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // 手动平仓按钮
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: fluent.Button(
                                        style: fluent.ButtonStyle(
                                          backgroundColor:
                                              WidgetStateProperty.all(Colors
                                                  .redAccent
                                                  .withValues(alpha: 0.1)),
                                          foregroundColor:
                                              WidgetStateProperty.all(
                                                  Colors.redAccent),
                                        ),
                                        child: const Text('手动平仓'),
                                        onPressed: () => _showSellConfirm(
                                            context, simProvider, pos),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    // 基金名称与代码
                                    Expanded(
                                      flex: 3,
                                      child: GestureDetector(
                                        onTap: () {
                                          final assocFund =
                                              fundProvider.myFunds[pos.code];
                                          if (assocFund != null) {
                                            fluent.showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  FundChartDialog(
                                                fundCode: assocFund.code,
                                                fundName: assocFund.name,
                                                navs: assocFund.navs,
                                                dates: assocFund.dates,
                                                todayEstimateNav:
                                                    double.tryParse(
                                                        assocFund.gsz),
                                                todayEstimatePct:
                                                    double.tryParse(
                                                        assocFund.gszzl),
                                                todayEstimateTime:
                                                    assocFund.gztime,
                                              ),
                                            );
                                          } else {
                                            fluent.displayInfoBar(
                                              context,
                                              builder: (context, close) =>
                                                  const fluent.InfoBar(
                                                title: Text('提示'),
                                                content:
                                                    Text('该基金不在自选看板，无法查看走势'),
                                                severity: fluent
                                                    .InfoBarSeverity.warning,
                                              ),
                                            );
                                          }
                                        },
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CopyableText(
                                              pos.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            CopyableText(
                                              pos.code,
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11,
                                                  fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // 平均买入成本
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('持仓成本/最新价',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${pos.buyPrice.toThousand(precision: 4)} / ${pos.currentPrice.toThousand(precision: 4)}',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 持有份额与持仓市值
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('持有份额/持仓市值',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${pos.volume.toThousand(precision: 0)} 份 / ￥${pos.amount.toThousand(precision: 2)}',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 浮动盈亏
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('持仓浮动盈亏',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$posProfitSign￥${pos.profit.toThousand(precision: 2)} ($posProfitSign${pos.profitRate.toThousand(precision: 2)}%)',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: posProfitColor,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 手动平仓按钮
                                    const SizedBox(width: 16),
                                    fluent.Button(
                                      style: fluent.ButtonStyle(
                                        backgroundColor:
                                            WidgetStateProperty.all(Colors
                                                .redAccent
                                                .withValues(alpha: 0.1)),
                                        foregroundColor:
                                            WidgetStateProperty.all(
                                                Colors.redAccent),
                                      ),
                                      child: const Text('手动平仓'),
                                      onPressed: () => _showSellConfirm(
                                          context, simProvider, pos),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                  const SizedBox(height: 28),

                  // 4. 交易记录流水
                  const Text('📜 历史交易记录',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (simProvider.transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      alignment: Alignment.center,
                      child: const Text('暂无模拟交易历史记录。',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: simProvider.transactions.length,
                      itemBuilder: (context, index) {
                        final tx = simProvider.transactions[index];
                        final isBuy = tx.type == 'BUY';
                        final Color txColor = isBuy
                            ? ThemeColors.getRedText(isDark)
                            : ThemeColors.getGreenText(isDark);
                        final String systemTimeStr =
                            tx.dateTime.toIso8601String().substring(11, 16);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.015)
                                : Colors.black.withValues(alpha: 0.01),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.04),
                            ),
                          ),
                          child: isSmallScreen
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 成交方向 Tag + 基金名字与代码
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                txColor.withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isBuy ? '买入' : '卖出',
                                            style: TextStyle(
                                                color: txColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CopyableText(tx.name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 2),
                                              CopyableText(tx.code,
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 10,
                                                      fontFamily: 'monospace')),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    // 成交价格与金额
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('成交价/成交额',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 10)),
                                        Text(
                                          '${tx.price.toThousand(precision: 4)} / ￥${tx.amount.toThousand(precision: 0)}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // 结算净值日期与系统操作时间
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('净值结算日/操作时间',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 10)),
                                        Text(
                                          '${tx.dateTimeStr} ${tx.dateTime.toIso8601String().substring(0, 10) == tx.dateTimeStr ? systemTimeStr : '[$systemTimeStr]'}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // 信号成因
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('成因说明',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 10)),
                                        Flexible(
                                          child: Text(
                                            tx.signalReason,
                                            style: TextStyle(
                                                color: isDark
                                                    ? Colors.white60
                                                    : Colors.black54,
                                                fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    // 成交方向 Tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: txColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isBuy ? '买入' : '卖出',
                                        style: TextStyle(
                                            color: txColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // 基金名字与代码
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CopyableText(tx.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          CopyableText(tx.code,
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 10,
                                                  fontFamily: 'monospace')),
                                        ],
                                      ),
                                    ),
                                    // 成交价格与金额
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('成交价/成交额',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 10)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${tx.price.toThousand(precision: 4)} / ￥${tx.amount.toThousand(precision: 0)}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 结算净值日期与系统操作时间
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('净值结算日/操作时间',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 10)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${tx.dateTimeStr} ${tx.dateTime.toIso8601String().substring(0, 10) == tx.dateTimeStr ? systemTimeStr : '[$systemTimeStr]'}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 信号成因
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text('成因说明',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 10)),
                                          const SizedBox(height: 2),
                                          Text(
                                            tx.signalReason,
                                            style: TextStyle(
                                                color: isDark
                                                    ? Colors.white60
                                                    : Colors.black54,
                                                fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
