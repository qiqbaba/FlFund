import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart'
    show
        Colors,
        Icons,
        showMenu,
        PopupMenuItem,
        RelativeRect,
        Theme,
        Brightness,
        RefreshIndicator,
        AlwaysScrollableScrollPhysics;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/fund_provider.dart';
import '../../core/config.dart';
import '../../core/utils/theme_colors.dart';
import '../widgets/holding_dialog.dart';
import '../widgets/sparkline.dart';
import '../widgets/fund_chart_dialog.dart';
import '../widgets/expandable_search_box.dart';
import '../widgets/mobile_header.dart';
import '../widgets/copyable_text.dart';
import '../widgets/unoptimized_badge.dart';

class RankingTab extends StatefulWidget {
  const RankingTab({super.key});

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> {
  final ScrollController _topHorizontalController = ScrollController();
  final ScrollController _topLeftVerticalController = ScrollController();
  final ScrollController _topRightVerticalController = ScrollController();
  int _tabIndex = 0;
  final ScrollController _botHorizontalController = ScrollController();
  final ScrollController _botLeftVerticalController = ScrollController();
  final ScrollController _botRightVerticalController = ScrollController();
  final TextEditingController _localSearchController = TextEditingController();
  String _searchText = '';
  bool _onlyShowBuySignals = false;
  bool _onlyShowSellSignals = false;
  bool _onlyShowRecentBuySignals = false;
  String? _topSortKey;
  bool _topSortAscending = false;
  String? _botSortKey;
  bool _botSortAscending = false;

  @override
  void initState() {
    super.initState();
    _topLeftVerticalController.addListener(() {
      if (_topLeftVerticalController.hasClients &&
          _topRightVerticalController.hasClients) {
        if (_topLeftVerticalController.offset <= 0 ||
            _topRightVerticalController.offset <= 0) {
          return;
        }
        if (_topLeftVerticalController.offset !=
            _topRightVerticalController.offset) {
          _topRightVerticalController.jumpTo(_topLeftVerticalController.offset);
        }
      }
    });
    _topRightVerticalController.addListener(() {
      if (_topLeftVerticalController.hasClients &&
          _topRightVerticalController.hasClients) {
        if (_topLeftVerticalController.offset <= 0 ||
            _topRightVerticalController.offset <= 0) {
          return;
        }
        if (_topRightVerticalController.offset !=
            _topLeftVerticalController.offset) {
          _topLeftVerticalController.jumpTo(_topRightVerticalController.offset);
        }
      }
    });
    _botLeftVerticalController.addListener(() {
      if (_botLeftVerticalController.hasClients &&
          _botRightVerticalController.hasClients) {
        if (_botLeftVerticalController.offset <= 0 ||
            _botRightVerticalController.offset <= 0) {
          return;
        }
        if (_botLeftVerticalController.offset !=
            _botRightVerticalController.offset) {
          _botRightVerticalController.jumpTo(_botLeftVerticalController.offset);
        }
      }
    });
    _botRightVerticalController.addListener(() {
      if (_botRightVerticalController.hasClients &&
          _botLeftVerticalController.hasClients) {
        if (_botLeftVerticalController.offset <= 0 ||
            _botRightVerticalController.offset <= 0) {
          return;
        }
        if (_botRightVerticalController.offset !=
            _botLeftVerticalController.offset) {
          _botLeftVerticalController.jumpTo(_botRightVerticalController.offset);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FundProvider>(context, listen: false).fetchRankings();
    });
  }

  @override
  void dispose() {
    _topHorizontalController.dispose();
    _topLeftVerticalController.dispose();
    _topRightVerticalController.dispose();
    _botHorizontalController.dispose();
    _botLeftVerticalController.dispose();
    _botRightVerticalController.dispose();
    _localSearchController.dispose();
    super.dispose();
  }

  void _showContextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required FundUIModel model,
    required AppConfig appConfig,
    required FundProvider fundProvider,
  }) async {
    final bool alreadyInMyFunds = fundProvider.myFunds.containsKey(model.code);
    final currentModel =
        alreadyInMyFunds ? fundProvider.myFunds[model.code]! : model;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showMenu<String>(
      context: context,
      position: position,
      color: isDark ? const Color(0xFF25343D) : Colors.white,
      items: [
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                currentModel.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 16,
                color: currentModel.isPinned ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(currentModel.isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'special',
          child: Row(
            children: [
              Icon(
                currentModel.isSpecial
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 16,
                color: currentModel.isSpecial ? Colors.orange : null,
              ),
              const SizedBox(width: 8),
              Text(currentModel.isSpecial ? '取消特别关注' : '特别关注'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'chart',
          child: Row(
            children: [
              Icon(Icons.show_chart_rounded, size: 16, color: Colors.green),
              SizedBox(width: 8),
              Text('打开趋势图'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 16, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('编辑持仓信息'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'backtest',
          child: Row(
            children: [
              Icon(Icons.psychology_rounded,
                  size: 16, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('跳转策略回测'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'toggle_add',
          child: Row(
            children: [
              Icon(
                alreadyInMyFunds
                    ? Icons.delete_outline_rounded
                    : Icons.add_circle_outline_rounded,
                size: 16,
                color: alreadyInMyFunds
                    ? ThemeColors.getRedText(
                        Theme.of(context).brightness == Brightness.dark)
                    : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                alreadyInMyFunds ? '从自选删除' : '加入自选',
                style: TextStyle(
                  color: alreadyInMyFunds
                      ? ThemeColors.getRedText(
                          Theme.of(context).brightness == Brightness.dark)
                      : Colors.blue,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'pin') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(model.code, model.name, model.sector);
        }
        appConfig.togglePinned(model.code);
        fundProvider.loadMyFunds();
      } else if (value == 'special') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(model.code, model.name, model.sector);
        }
        appConfig.toggleSpecial(model.code);
        fundProvider.loadMyFunds();
      } else if (value == 'chart') {
        fluent.showDialog(
          context: context,
          builder: (context) => FundChartDialog(
            fundCode: currentModel.code,
            fundName: currentModel.name,
            navs: currentModel.navs,
            dates: currentModel.dates,
            todayEstimateNav: double.tryParse(currentModel.gsz),
            todayEstimatePct: double.tryParse(currentModel.gszzl),
            todayEstimateTime: currentModel.gztime,
          ),
        );
      } else if (value == 'edit') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(model.code, model.name, model.sector);
          fundProvider.loadMyFunds();
        }
        // 由于上面可能有异步添加操作，取最新 model 并延时弹窗
        final updatedModel = fundProvider.myFunds[model.code]!;
        _editHoldingInfo(context, updatedModel, appConfig, fundProvider);
      } else if (value == 'backtest') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(model.code, model.name, model.sector);
          fundProvider.loadMyFunds();
        }
        fundProvider.switchToBacktest(model.code);
      } else if (value == 'toggle_add') {
        if (alreadyInMyFunds) {
          appConfig.removeFund(model.code);
        } else {
          appConfig.addFund(model.code, model.name, model.sector);
        }
        fundProvider.loadMyFunds();
      }
    });
  }

  void _editHoldingInfo(BuildContext context, FundUIModel model,
      AppConfig appConfig, FundProvider fundProvider) {
    fluent.showDialog(
      context: context,
      builder: (context) => HoldingDialog(
        fundCode: model.code,
        fundName: model.name,
        initialIsHeld: model.isHeld,
        initialAmount: model.amount,
        initialYieldRate: model.yieldRate,
        onSave: (isHeld, amount, yieldRate) {
          appConfig.updateHoldInfo(model.code, isHeld, amount, yieldRate);
          fundProvider.loadMyFunds();
          fundProvider.refreshAll();
        },
      ),
    );
  }

  Widget _buildList(
    List<FundUIModel> list,
    bool isTop,
    bool isDark,
    AppConfig appConfig,
    FundProvider fundProvider,
    ScrollController horizontalController,
    ScrollController leftVerticalController,
    ScrollController rightVerticalController,
    String? sortKey,
    bool sortAscending,
    void Function(String?, bool) onSortChanged, {
    bool isFullHeight = false,
  }) {
    final filteredList = list.where((model) {
      if (_onlyShowRecentBuySignals) {
        final bool alreadyInMyFunds =
            fundProvider.myFunds.containsKey(model.code);
        final currentModel =
            alreadyInMyFunds ? fundProvider.myFunds[model.code]! : model;
        if (!currentModel.isBuySignal &&
            currentModel.getRecentBuyTriggerIndex(maxDays: 3) == null) {
          return false;
        }
      }
      if (_onlyShowBuySignals) {
        final bool alreadyInMyFunds =
            fundProvider.myFunds.containsKey(model.code);
        final currentModel =
            alreadyInMyFunds ? fundProvider.myFunds[model.code]! : model;
        if (!currentModel.isBuySignal) return false;
      }
      if (_onlyShowSellSignals) {
        final bool alreadyInMyFunds =
            fundProvider.myFunds.containsKey(model.code);
        final currentModel =
            alreadyInMyFunds ? fundProvider.myFunds[model.code]! : model;
        if (!currentModel.isSellSignal) return false;
      }
      if (_searchText.isEmpty) return true;
      final q = _searchText.toLowerCase();
      return model.code.toLowerCase().contains(q) ||
          model.name.toLowerCase().contains(q) ||
          model.sector.toLowerCase().contains(q);
    }).toList();

    // 排序逻辑
    if (sortKey != null) {
      filteredList.sort((a, b) {
        return FundSorter.compare(a, b, sortKey, sortAscending);
      });
    }

    if (filteredList.isEmpty) {
      return const Center(
          child: Text('无匹配排行数据', style: TextStyle(color: Colors.grey)));
    }

    final List<ColConfig> columns = [
      ColConfig(title: '', width: 30),
      ColConfig(title: '基金名称', width: 160, alignLeft: true, sortKey: 'name'),
      ColConfig(title: '代码', width: 70, sortKey: 'code'),
      ColConfig(title: '板块分类', width: 70, alignLeft: true, sortKey: 'sector'),
      ColConfig(title: '买入信号', width: 100, sortKey: 'optimal'),
      ColConfig(title: '卖出信号', width: 100, sortKey: 'sell_optimal'),
      ColConfig(title: '今日收益/\n收益率', width: 95, sortKey: 'gszzl'),
      ColConfig(title: '昨日', width: 60, sortKey: 'yestZdf'),
      ...appConfig.dropDays.map(
          (d) => ColConfig(title: '近$d日\n涨跌', width: 55, sortKey: 'drop_$d')),
      ...appConfig.percentileMonths.map((m) =>
          ColConfig(title: '近$m月\n百分位', width: 55, sortKey: 'percentile_$m')),
      ColConfig(title: '趋势', width: 80),
      ColConfig(title: '数据源', width: 70, sortKey: 'src'),
      ColConfig(title: '估值时间', width: 130, sortKey: 'gztime'),
      ColConfig(title: '操作', width: 100),
    ];

    final double totalWidth =
        columns.map((c) => c.width).reduce((a, b) => a + b);

    Widget buildHeaderCell(ColConfig col) {
      final hasSort = col.sortKey != null;
      final isCurrentSort = sortKey == col.sortKey;

      Widget headerText = Text(
        col.title,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            height: 1.1),
        textAlign: col.alignLeft ? TextAlign.left : TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );

      Widget headerContent;
      if (hasSort) {
        headerContent = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (sortKey == col.sortKey) {
                if (!sortAscending) {
                  onSortChanged(col.sortKey, true);
                } else {
                  onSortChanged(null, false);
                }
              } else {
                onSortChanged(col.sortKey, false);
              }
            },
            child: Row(
              mainAxisAlignment: col.alignLeft
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (col.alignLeft) ...[
                  Expanded(child: headerText),
                  const SizedBox(width: 2),
                ] else ...[
                  const SizedBox(width: 8),
                  Flexible(child: headerText),
                ],
                Icon(
                  isCurrentSort
                      ? (sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                      : Icons.unfold_more_rounded,
                  size: 12,
                  color: isCurrentSort
                      ? Colors.blue
                      : (isDark ? Colors.white38 : Colors.black26),
                ),
              ],
            ),
          ),
        );
      } else {
        headerContent = headerText;
      }

      return SizedBox(
        width: col.width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: headerContent,
        ),
      );
    }

    Widget buildRow(FundUIModel model, int orderIndex, List<ColConfig> rowCols,
        {bool isLeftPart = false}) {
      final bool alreadyInMyFunds =
          fundProvider.myFunds.containsKey(model.code);
      final currentModel =
          alreadyInMyFunds ? fundProvider.myFunds[model.code]! : model;

      final double change = currentModel.isTodayValuation
          ? (double.tryParse(currentModel.gszzl) ?? 0.0)
          : 0.0;
      final Color changeColor = currentModel.isTodayValuation
          ? (change > 0
              ? ThemeColors.getRedText(isDark)
              : (change < 0
                  ? ThemeColors.getGreenText(isDark)
                  : ThemeColors.getNormalText(isDark)))
          : ThemeColors.getNormalText(isDark);

      double todayProfit = 0.0;
      if (currentModel.isHeld && currentModel.amount > 0) {
        todayProfit = (currentModel.amount * change) / 100.0;
      }

      final bool isBuySignal = currentModel.isBuySignal;
      final bool isSellSignal = currentModel.isSellSignal;
      final double currentDrop = currentModel.currentDrop;
      final double currentRise = currentModel.currentRise;

      // 优先触发了买入信号的行高亮显示（淡红色），其次触发了卖出信号的行高亮显示（淡绿色），再次置顶行高亮背景，普通行无背景
      final Color? rowBgColor = isBuySignal
          ? ThemeColors.getRedText(isDark)
              .withValues(alpha: isDark ? 0.20 : 0.12)
          : (isSellSignal
              ? ThemeColors.getGreenText(isDark)
                  .withValues(alpha: isDark ? 0.20 : 0.12)
              : (currentModel.isPinned
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.yellow.withValues(alpha: 0.05))
                  : null));

      // 提取长按/右键回调，传递给 CopyableText 确保手势统一处理
      void longPressCallback(LongPressStartDetails details) {
        _showContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          model: model,
          appConfig: appConfig,
          fundProvider: fundProvider,
        );
      }

      void secondaryTapCallback(TapDownDetails details) {
        _showContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          model: model,
          appConfig: appConfig,
          fundProvider: fundProvider,
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: secondaryTapCallback,
        onLongPressStart: longPressCallback,
        child: Container(
          height: 55,
          decoration: BoxDecoration(
            color: rowBgColor,
            border: Border(
              bottom:
                  BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              left: BorderSide.none,
              right: BorderSide(
                color: isLeftPart
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : Colors.transparent,
                width: isLeftPart ? 1 : 0,
              ),
            ),
          ),
          padding: EdgeInsets.zero,
          child: Row(
            children: rowCols.map((col) {
              Widget cellContent = const SizedBox.shrink();
              final cleanTitle = col.title.replaceAll('\n', '');

              switch (cleanTitle) {
                case '#':
                case '':
                  cellContent = Text(
                    currentModel.isPinned ? '📌' : '$orderIndex',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isTop
                          ? (orderIndex <= 3
                              ? ThemeColors.getRedText(isDark)
                              : Colors.grey)
                          : (orderIndex <= 3
                              ? ThemeColors.getGreenText(isDark)
                              : Colors.grey),
                    ),
                  );
                  break;
                case '代码':
                  cellContent = CopyableText(
                    currentModel.code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    onLongPressStart: longPressCallback,
                    onSecondaryTapDown: secondaryTapCallback,
                  );
                  break;
                case '基金名称':
                  cellContent = Row(
                    children: [
                      Expanded(
                        child: CopyableText(
                          currentModel.name,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          onLongPressStart: longPressCallback,
                          onSecondaryTapDown: secondaryTapCallback,
                        ),
                      ),
                      if (currentModel.errorMsg != null) ...[
                        const SizedBox(width: 4),
                        fluent.Tooltip(
                          message: currentModel.errorMsg!,
                          useMousePosition: true,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: ThemeColors.getRedText(isDark),
                            size: 14,
                          ),
                        ),
                      ],
                      if (currentModel.isHeld) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber
                                .withValues(alpha: isDark ? 0.15 : 0.12),
                            border: Border.all(
                                color: Colors.amber
                                    .withValues(alpha: isDark ? 0.4 : 0.6),
                                width: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '持',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFFFD54F)
                                  : const Color(0xFFE65100),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ]
                    ],
                  );
                  break;
                case '板块分类':
                  cellContent = Text(
                    currentModel.sector,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontSize: 12),
                  );
                  break;
                case '买入信号':
                  if (currentModel.optimalStrategy != null) {
                    final s = currentModel.optimalStrategy!;
                    final buyText = '买:${s['buy_days']}天>${s['buy_drop']}%';
                    final profitText = '盈:>${s['target_profit']}%';

                    if (isBuySignal) {
                      final badgeBg = isDark
                          ? const Color(0xFFC62828).withValues(alpha: 0.9)
                          : const Color(0xFFFFEBEE);
                      final badgeBorder = isDark
                          ? const Color(0xFFE57373)
                          : const Color(0xFFEF9A9A);
                      final badgeTextColor =
                          isDark ? Colors.white : const Color(0xFFC62828);
                      final dropTextColor = isDark
                          ? const Color(0xFFFFCDD2)
                          : const Color(0xFFB71C1C);

                      cellContent = Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$buyText\n$profitText',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white60 : Colors.black54,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              border: Border.all(color: badgeBorder, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '💥 触发',
                                  style: TextStyle(
                                    color: badgeTextColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '(${currentDrop.toThousand(precision: 1)}%)',
                                  style: TextStyle(
                                    color: dropTextColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      final recentBuyIdx =
                          currentModel.getRecentBuyTriggerIndex(maxDays: 3);
                      if (recentBuyIdx != null) {
                        final badgeBg = isDark
                            ? Colors.red.withValues(alpha: 0.15)
                            : const Color(0xFFFFEBEE).withValues(alpha: 0.4);
                        final badgeBorder = isDark
                            ? Colors.red.withValues(alpha: 0.4)
                            : const Color(0xFFEF9A9A).withValues(alpha: 0.5);
                        final badgeTextColor = isDark
                            ? Colors.white70
                            : const Color(0xFFC62828).withValues(alpha: 0.8);
                        final String dayText =
                            recentBuyIdx == 1 ? '昨日' : '$recentBuyIdx天前';

                        cellContent = fluent.Tooltip(
                          message: '当前处于网格加仓降噪期，但仍处于上一次买点附近的合理建仓区间',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$buyText\n$profitText',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  border: Border.all(
                                      color: badgeBorder, width: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '⏳ $dayText已触发',
                                  style: TextStyle(
                                    color: badgeTextColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        cellContent = Text(
                          '$buyText\n$profitText',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        );
                      }
                    }
                  } else {
                    cellContent = buildUnoptimizedBadge(
                      isSell: false,
                      optimalStrategy: currentModel.optimalStrategy,
                    );
                  }
                  break;
                case '卖出信号':
                  if (currentModel.optimalStrategy != null &&
                      currentModel.optimalStrategy!['sell_x'] != null) {
                    final s = currentModel.optimalStrategy!;
                    final int encodedVal = s['sell_x'];
                    int sellX = encodedVal;
                    double sellPct = encodedVal.toDouble();
                    if (encodedVal >= 100) {
                      sellX = encodedVal ~/ 1000;
                      sellPct = (encodedVal % 1000).toDouble();
                    }
                    final double sellWinRate = s['sell_win_rate'] ?? 0.0;
                    final sellText = '卖:$sellX天>$sellPct%';
                    final winRateText =
                        '概率:${sellWinRate.toThousand(precision: 1)}%';

                    if (isSellSignal) {
                      final badgeBg = isDark
                          ? const Color(0xFF2E7D32).withValues(alpha: 0.9)
                          : const Color(0xFFE8F5E9);
                      final badgeBorder = isDark
                          ? const Color(0xFF81C784)
                          : const Color(0xFFA5D6A7);
                      final badgeTextColor =
                          isDark ? Colors.white : const Color(0xFF2E7D32);
                      final dropTextColor = isDark
                          ? const Color(0xFFC8E6C9)
                          : const Color(0xFF1B5E20);

                      cellContent = Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$sellText\n$winRateText',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white60 : Colors.black54,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              border: Border.all(color: badgeBorder, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '💥 触发',
                                  style: TextStyle(
                                    color: badgeTextColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '(${currentRise.toThousand(precision: 1)}%)',
                                  style: TextStyle(
                                    color: dropTextColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      cellContent = Text(
                        '$sellText\n$winRateText',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF81C784)
                              : const Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      );
                    }
                  } else {
                    cellContent = buildUnoptimizedBadge(
                      isSell: true,
                      optimalStrategy: currentModel.optimalStrategy,
                    );
                  }
                  break;
                case '昨日':
                  final yestChange =
                      double.tryParse(currentModel.yestZdf) ?? 0.0;
                  final yestColor = yestChange > 0
                      ? ThemeColors.getRedText(isDark)
                      : (yestChange < 0
                          ? ThemeColors.getGreenText(isDark)
                          : ThemeColors.getNormalText(isDark));
                  cellContent = Text(
                    '${yestChange > 0 ? '+' : ''}${currentModel.yestZdf}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: yestColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                  break;
                case '今日收益/收益率':
                  cellContent = MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => _editHoldingInfo(
                          context, currentModel, appConfig, fundProvider),
                      child: Text(
                        currentModel.isHeld && currentModel.amount > 0
                            ? '${todayProfit.toThousand(precision: 2, showSign: true)} 元\n${change.toThousand(precision: 2, showSign: true)}%'
                            : '-\n${change.toThousand(precision: 2, showSign: true)}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: changeColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                  break;
                case '趋势':
                  cellContent = MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () {
                        fluent.showDialog(
                          context: context,
                          builder: (context) => FundChartDialog(
                            fundCode: currentModel.code,
                            fundName: currentModel.name,
                            navs: currentModel.navs,
                            dates: currentModel.dates,
                            todayEstimateNav: double.tryParse(currentModel.gsz),
                            todayEstimatePct:
                                double.tryParse(currentModel.gszzl),
                            todayEstimateTime: currentModel.gztime,
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4.0, horizontal: 2.0),
                          child: Sparkline(data: currentModel.navs),
                        ),
                      ),
                    ),
                  );
                  break;
                case '数据源':
                  cellContent = Text(
                    currentModel.source.isEmpty ? '-' : currentModel.source,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  );
                  break;
                case '估值时间':
                  String timeStr = currentModel.gztime;
                  if (timeStr.contains(' [')) {
                    timeStr = timeStr.substring(0, timeStr.indexOf(' ['));
                  }
                  cellContent = Text(
                    timeStr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  );
                  break;
                case '操作':
                  cellContent = Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      fluent.IconButton(
                        icon: Icon(
                          alreadyInMyFunds
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 16,
                          color: alreadyInMyFunds ? Colors.grey : Colors.blue,
                        ),
                        onPressed: alreadyInMyFunds
                            ? null
                            : () {
                                appConfig.addFund(currentModel.code,
                                    currentModel.name, currentModel.sector);
                                fundProvider.loadMyFunds();
                                fluent.displayInfoBar(
                                  context,
                                  builder: (context, close) {
                                    return fluent.InfoBar(
                                      title: const Text('自选添加成功'),
                                      content:
                                          Text('${currentModel.name} 已成功加入自选。'),
                                      severity: fluent.InfoBarSeverity.success,
                                      onClose: close,
                                    );
                                  },
                                );
                              },
                      ),
                      const SizedBox(width: 4),
                      fluent.IconButton(
                        icon: const Icon(Icons.psychology_rounded,
                            size: 16, color: Colors.purpleAccent),
                        onPressed: () {
                          if (!alreadyInMyFunds) {
                            appConfig.addFund(currentModel.code,
                                currentModel.name, currentModel.sector);
                            fundProvider.loadMyFunds();
                          }
                          fundProvider.switchToBacktest(currentModel.code);
                        },
                      ),
                    ],
                  );
                  break;
                default:
                  if (cleanTitle.startsWith('近') &&
                      cleanTitle.endsWith('日涨跌')) {
                    final dayStr =
                        cleanTitle.replaceAll('近', '').replaceAll('日涨跌', '');
                    final int d = int.tryParse(dayStr) ?? 0;
                    final val = currentModel.drops[d] ?? 0.0;
                    final color = val > 0
                        ? ThemeColors.getRedText(isDark)
                        : (val < 0
                            ? ThemeColors.getGreenText(isDark)
                            : ThemeColors.getNormalText(isDark));
                    cellContent = Text(
                      val == 0.0
                          ? '--'
                          : '${val.toThousand(precision: 2, showSign: true)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: color),
                    );
                  } else if (cleanTitle.startsWith('近') &&
                      cleanTitle.endsWith('月百分位')) {
                    final monthStr =
                        cleanTitle.replaceAll('近', '').replaceAll('月百分位', '');
                    final int m = int.tryParse(monthStr) ?? 0;
                    final val = currentModel.pcts[m] ?? -1.0;

                    Color? cellBg;
                    Color textColor = ThemeColors.getNormalText(isDark);
                    if (val >= 0) {
                      if (val <= 20.0) {
                        cellBg = ThemeColors.getLowPercentileBg(isDark);
                        textColor = ThemeColors.getLowPercentileText(isDark);
                      } else if (val >= 80.0) {
                        cellBg = ThemeColors.getHighPercentileBg(isDark);
                        textColor = ThemeColors.getHighPercentileText(isDark);
                      }
                    }

                    cellContent = Container(
                      color: cellBg,
                      alignment: Alignment.center,
                      child: Text(
                        val < 0 ? '--' : '${val.toThousand(precision: 1)}%',
                        style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: (val <= 20 || val >= 80)
                                ? FontWeight.bold
                                : null),
                      ),
                    );
                  }
                  break;
              }

              return SizedBox(
                width: col.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: cellContent,
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    if (appConfig.freezeColumns) {
      final List<ColConfig> leftColumns = columns
          .where((col) => col.title == '#' || col.title == '' || col.title == '基金名称')
          .toList();
      final List<ColConfig> rightColumns = columns
          .where((col) => col.title != '#' && col.title != '' && col.title != '基金名称')
          .toList();
      final double leftTableWidth = leftColumns.isEmpty
          ? 0.0
          : leftColumns.map((c) => c.width).reduce((a, b) => a + b);
      final double rightTableWidth = rightColumns.isEmpty
          ? 0.0
          : rightColumns.map((c) => c.width).reduce((a, b) => a + b);

      return Container(
        height: isFullHeight ? null : 380,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            right: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: leftTableWidth + 1,
                child: Column(
                  children: [
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        border: Border(
                          bottom: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12),
                          right: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                              width: 1),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      child: Row(
                        children: leftColumns
                            .map((col) => buildHeaderCell(col))
                            .toList(),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          await fundProvider.fetchRankings(isForce: true);
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          controller: leftVerticalController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredList.length,
                          itemBuilder: (context, idx) {
                            final model = filteredList[idx];
                            return buildRow(model, idx + 1, leftColumns,
                                isLeftPart: true);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: fluent.Scrollbar(
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                  controller: rightVerticalController,
                  child: fluent.Scrollbar(
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                    controller: horizontalController,
                    child: SingleChildScrollView(
                    controller: horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rightTableWidth,
                      child: Column(
                        children: [
                          Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.04),
                              border: Border(
                                bottom: BorderSide(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12),
                              ),
                            ),
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: rightColumns
                                  .map((col) => buildHeaderCell(col))
                                  .toList(),
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                                onRefresh: () async {
                                  await fundProvider.fetchRankings(
                                      isForce: true);
                                },
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  controller: rightVerticalController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: filteredList.length,
                                  itemBuilder: (context, idx) {
                                    final model = filteredList[idx];
                                    return buildRow(
                                        model, idx + 1, rightColumns);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Container(
        height: isFullHeight ? null : 380,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            right: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          child: fluent.Scrollbar(
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            controller: rightVerticalController,
            child: fluent.Scrollbar(
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              controller: horizontalController,
              child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        border: Border(
                          bottom: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      child: Row(
                        children:
                            columns.map((col) => buildHeaderCell(col)).toList(),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                          onRefresh: () async {
                            await fundProvider.fetchRankings(isForce: true);
                          },
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            controller: rightVerticalController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filteredList.length,
                            itemBuilder: (context, idx) {
                              final model = filteredList[idx];
                              return buildRow(model, idx + 1, columns);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildTabBar(
      bool isDark,
      bool isSmallScreen,
      FundProvider fundProvider,
      AppConfig appConfig,
      Widget searchBox,
      Widget moreBtn) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: isSmallScreen ? 0.0 : 12.0,
          bottom: 8.0),
      child: Row(
        children: [
          _buildTabButton(0, '今日领涨', Icons.trending_up_rounded,
              ThemeColors.getRedText(isDark), isDark),
          const SizedBox(width: 8),
          _buildTabButton(1, '今日领跌', Icons.trending_down_rounded,
              ThemeColors.getGreenText(isDark), isDark),
          if (!isSmallScreen) ...[
            const Spacer(),
            searchBox,
            const SizedBox(width: 12),
            moreBtn,
          ],
        ],
      ),
    );
  }

  Widget _buildTabButton(
      int index, String text, IconData icon, Color color, bool isDark) {
    final bool isSelected = _tabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.1))
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fundProvider = Provider.of<FundProvider>(context);
    final appConfig = Provider.of<AppConfig>(context);
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 720;

    final Widget searchBox = ExpandableSearchBox(
      controller: _localSearchController,
      placeholder: isSmallScreen ? '搜索...' : '搜索当前列表基金...',
      width: isSmallScreen ? 130 : 180,
      onChanged: (val) {
        setState(() {
          _searchText = val;
        });
      },
    );

    final Widget moreBtn = fluent.DropDownButton(
      buttonBuilder: (context, onOpen) => fluent.IconButton(
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.blue),
        onPressed: onOpen,
      ),
      items: [
        fluent.MenuFlyoutItem(
          leading:
              const Icon(Icons.refresh_rounded, size: 14, color: Colors.blue),
          text: Text(isSmallScreen ? '刷新排行' : '一键刷新排行',
              style: const TextStyle(fontSize: 12)),
          onPressed: () {
            fundProvider.fetchRankings(isForce: true);
          },
        ),
        fluent.MenuFlyoutItem(
          leading: Icon(
            _onlyShowBuySignals
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: _onlyShowBuySignals ? Colors.blue : Colors.grey,
          ),
          text: const Text('只看买入触发', style: TextStyle(fontSize: 12)),
          onPressed: () {
            setState(() {
              _onlyShowBuySignals = !_onlyShowBuySignals;
              if (_onlyShowBuySignals) {
                _onlyShowSellSignals = false;
                _onlyShowRecentBuySignals = false;
              }
            });
          },
        ),
        fluent.MenuFlyoutItem(
          leading: Icon(
            _onlyShowRecentBuySignals
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: _onlyShowRecentBuySignals ? Colors.blue : Colors.grey,
          ),
          text: const Text('只看近日买入触发', style: TextStyle(fontSize: 12)),
          onPressed: () {
            setState(() {
              _onlyShowRecentBuySignals = !_onlyShowRecentBuySignals;
              if (_onlyShowRecentBuySignals) {
                _onlyShowBuySignals = false;
                _onlyShowSellSignals = false;
              }
            });
          },
        ),
        fluent.MenuFlyoutItem(
          leading: Icon(
            _onlyShowSellSignals
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: _onlyShowSellSignals ? Colors.green : Colors.grey,
          ),
          text: const Text('只看卖出触发', style: TextStyle(fontSize: 12)),
          onPressed: () {
            setState(() {
              _onlyShowSellSignals = !_onlyShowSellSignals;
              if (_onlyShowSellSignals) {
                _onlyShowBuySignals = false;
                _onlyShowRecentBuySignals = false;
              }
            });
          },
        ),
        fluent.MenuFlyoutItem(
          leading: Icon(
            appConfig.freezeColumns
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: appConfig.freezeColumns ? Colors.blue : Colors.grey,
          ),
          text: const Text('冻结列(基金名称)', style: TextStyle(fontSize: 12)),
          onPressed: () {
            appConfig.toggleFreezeColumns(!appConfig.freezeColumns);
          },
        ),
      ],
    );

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSmallScreen)
            MobileHeader(
              title: 'ETF涨跌榜',
              searchBox: searchBox,
              moreBtn: moreBtn,
            ),
          _buildTabBar(isDark, isSmallScreen, fundProvider, appConfig,
              searchBox, moreBtn),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10.0, bottom: 10.0),
              child: !fundProvider.rankingLoaded
                  ? const Center(child: fluent.ProgressRing())
                  : (_tabIndex == 0
                      ? _buildList(
                          fundProvider.topFunds,
                          true,
                          isDark,
                          appConfig,
                          fundProvider,
                          _topHorizontalController,
                          _topLeftVerticalController,
                          _topRightVerticalController,
                          _topSortKey,
                          _topSortAscending,
                          (key, ascending) {
                            setState(() {
                              _topSortKey = key;
                              _topSortAscending = ascending;
                            });
                          },
                          isFullHeight: true,
                        )
                      : _buildList(
                          fundProvider.botFunds,
                          false,
                          isDark,
                          appConfig,
                          fundProvider,
                          _botHorizontalController,
                          _botLeftVerticalController,
                          _botRightVerticalController,
                          _botSortKey,
                          _botSortAscending,
                          (key, ascending) {
                            setState(() {
                              _botSortKey = key;
                              _botSortAscending = ascending;
                            });
                          },
                          isFullHeight: true,
                        )),
            ),
          ),
        ],
      ),
    );
  }
}
