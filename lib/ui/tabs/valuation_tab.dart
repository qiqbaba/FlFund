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
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/fund_provider.dart';
import '../../core/config.dart';
import '../../core/utils/pinyin_search.dart';
import '../../core/utils/theme_colors.dart';
import '../widgets/holding_dialog.dart';
import '../widgets/sparkline.dart';
import '../widgets/fund_chart_dialog.dart';
import '../widgets/expandable_search_box.dart';
import '../widgets/mobile_header.dart';
import '../widgets/unoptimized_badge.dart';
import '../widgets/copyable_text.dart';

class ValuationTab extends StatefulWidget {
  const ValuationTab({super.key});

  @override
  State<ValuationTab> createState() => _ValuationTabState();
}

class _ValuationTabState extends State<ValuationTab> {
  final ScrollController _lowHorizontalController = ScrollController();
  final ScrollController _lowLeftVerticalController = ScrollController();
  final ScrollController _lowRightVerticalController = ScrollController();
  int _tabIndex = 0;
  final ScrollController _highHorizontalController = ScrollController();
  final ScrollController _highLeftVerticalController = ScrollController();
  final ScrollController _highRightVerticalController = ScrollController();

  // 历史最低 Tab 的相关控制器和状态
  final ScrollController _lowestHorizontalController = ScrollController();
  final ScrollController _lowestLeftVerticalController = ScrollController();
  final ScrollController _lowestRightVerticalController = ScrollController();

  // 历史最高 Tab 的相关控制器和状态
  final ScrollController _highestHorizontalController = ScrollController();
  final ScrollController _highestLeftVerticalController = ScrollController();
  final ScrollController _highestRightVerticalController = ScrollController();

  final TextEditingController _localSearchController = TextEditingController();
  String _searchText = '';
  bool _onlyShowBuySignals = false;
  bool _onlyShowSellSignals = false;
  bool _onlyShowRecentBuySignals = false;

  void _showValuationGuideDialog(BuildContext context, bool isDark) {
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: Colors.blue, size: 20),
            SizedBox(width: 8),
            Text('PE 与 PB 指标选看指南',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '不同行业的商业模式与资产结构差异巨大，看估值时需选择匹配的指标：',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.2),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📈 主要看 PE (市盈率) 的行业：',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 13)),
                    SizedBox(height: 6),
                    Text(
                      '• 适用行业：消费(白酒/家电/食品)、医药医疗、科技/半导体、互联网、新能源、宽基指数(沪深300/深证100等)。\n'
                      '• 逻辑特征：轻资产模式、企业盈利相对稳定或具备持续成长性，资产以收益能力定价。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🏦 主要看 PB (市净率) 的行业：',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.orange : Colors.deepOrange,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    const Text(
                      '• 适用行业：金融(银行/证券/保险)、强周期品(煤炭/钢铁/有色/化工/石油)、房地产、建筑基建、交通运输等。\n'
                      '• 逻辑特征：重资产、高杠杆或周期性强，企业盈利随宏观周期剧烈波动，看账面净资产价值更客观安全。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.grey),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '💡 避坑提示：周期行业在行业低谷极度亏损时，PE会爆表失真，此时切忌以为高估，应参考 PB 百分位判断探底位置。',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          fluent.Button(
            child: const Text('我知道了'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  String? _lowSortKey;
  bool _lowSortAscending = false;
  String? _highSortKey;
  bool _highSortAscending = false;
  String? _lowestSortKey;
  bool _lowestSortAscending = false;
  String? _highestSortKey;
  bool _highestSortAscending = false;

  bool _isSyncing = false; // 防止 ScrollController 循环触发
  ScrollController? _activeLowScrollController;
  ScrollController? _activeHighScrollController;
  ScrollController? _activeLowestScrollController;
  ScrollController? _activeHighestScrollController;

  @override
  void initState() {
    super.initState();
    _lowLeftVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_lowLeftVerticalController.hasClients &&
          _lowLeftVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeLowScrollController = _lowLeftVerticalController;
      }
      if (_activeLowScrollController == _lowLeftVerticalController) {
        if (_lowLeftVerticalController.hasClients &&
            _lowRightVerticalController.hasClients) {
          if (_lowLeftVerticalController.offset !=
              _lowRightVerticalController.offset) {
            _isSyncing = true;
            _lowRightVerticalController
                .jumpTo(_lowLeftVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });
    _lowRightVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_lowRightVerticalController.hasClients &&
          _lowRightVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeLowScrollController = _lowRightVerticalController;
      }
      if (_activeLowScrollController == _lowRightVerticalController) {
        if (_lowLeftVerticalController.hasClients &&
            _lowRightVerticalController.hasClients) {
          if (_lowRightVerticalController.offset !=
              _lowLeftVerticalController.offset) {
            _isSyncing = true;
            _lowLeftVerticalController
                .jumpTo(_lowRightVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });
    _highLeftVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_highLeftVerticalController.hasClients &&
          _highLeftVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeHighScrollController = _highLeftVerticalController;
      }
      if (_activeHighScrollController == _highLeftVerticalController) {
        if (_highLeftVerticalController.hasClients &&
            _highRightVerticalController.hasClients) {
          if (_highLeftVerticalController.offset !=
              _highRightVerticalController.offset) {
            _isSyncing = true;
            _highRightVerticalController
                .jumpTo(_highLeftVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });
    _highRightVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_highRightVerticalController.hasClients &&
          _highRightVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeHighScrollController = _highRightVerticalController;
      }
      if (_activeHighScrollController == _highRightVerticalController) {
        if (_highLeftVerticalController.hasClients &&
            _highRightVerticalController.hasClients) {
          if (_highRightVerticalController.offset !=
              _highLeftVerticalController.offset) {
            _isSyncing = true;
            _highLeftVerticalController
                .jumpTo(_highRightVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });

    // 历史最低 Tab 同步滚动绑定
    _lowestLeftVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_lowestLeftVerticalController.hasClients &&
          _lowestLeftVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeLowestScrollController = _lowestLeftVerticalController;
      }
      if (_activeLowestScrollController == _lowestLeftVerticalController) {
        if (_lowestLeftVerticalController.hasClients &&
            _lowestRightVerticalController.hasClients) {
          if (_lowestLeftVerticalController.offset !=
              _lowestRightVerticalController.offset) {
            _isSyncing = true;
            _lowestRightVerticalController
                .jumpTo(_lowestLeftVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });
    _lowestRightVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_lowestRightVerticalController.hasClients &&
          _lowestRightVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeLowestScrollController = _lowestRightVerticalController;
      }
      if (_activeLowestScrollController == _lowestRightVerticalController) {
        if (_lowestLeftVerticalController.hasClients &&
            _lowestRightVerticalController.hasClients) {
          if (_lowestRightVerticalController.offset !=
              _lowestLeftVerticalController.offset) {
            _isSyncing = true;
            _lowestLeftVerticalController
                .jumpTo(_lowestRightVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });

    // 历史最高 Tab 同步滚动绑定
    _highestLeftVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_highestLeftVerticalController.hasClients &&
          _highestLeftVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeHighestScrollController = _highestLeftVerticalController;
      }
      if (_activeHighestScrollController == _highestLeftVerticalController) {
        if (_highestLeftVerticalController.hasClients &&
            _highestRightVerticalController.hasClients) {
          if (_highestLeftVerticalController.offset !=
              _highestRightVerticalController.offset) {
            _isSyncing = true;
            _highestRightVerticalController
                .jumpTo(_highestLeftVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });
    _highestRightVerticalController.addListener(() {
      if (_isSyncing) return;
      if (_highestRightVerticalController.hasClients &&
          _highestRightVerticalController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _activeHighestScrollController = _highestRightVerticalController;
      }
      if (_activeHighestScrollController == _highestRightVerticalController) {
        if (_highestLeftVerticalController.hasClients &&
            _highestRightVerticalController.hasClients) {
          if (_highestRightVerticalController.offset !=
              _highestLeftVerticalController.offset) {
            _isSyncing = true;
            _highestLeftVerticalController
                .jumpTo(_highestRightVerticalController.offset);
            _isSyncing = false;
          }
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FundProvider>(context, listen: false).fetchValuations();
    });
  }

  @override
  void dispose() {
    _lowHorizontalController.dispose();
    _lowLeftVerticalController.dispose();
    _lowRightVerticalController.dispose();
    _highHorizontalController.dispose();
    _highLeftVerticalController.dispose();
    _highRightVerticalController.dispose();
    _lowestHorizontalController.dispose();
    _lowestLeftVerticalController.dispose();
    _lowestRightVerticalController.dispose();
    _highestHorizontalController.dispose();
    _highestLeftVerticalController.dispose();
    _highestRightVerticalController.dispose();
    _localSearchController.dispose();
    super.dispose();
  }

  void _showContextMenu({
    required BuildContext context,
    required Offset globalPosition,
    required String assocCode,
    required String assocName,
    required AppConfig appConfig,
    required FundProvider fundProvider,
    required FundUIModel? assocFund,
  }) async {
    final bool alreadyInMyFunds = fundProvider.myFunds.containsKey(assocCode);
    final currentModel =
        alreadyInMyFunds ? fundProvider.myFunds[assocCode]! : null;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    final isPinned = currentModel?.isPinned == true;
    final isSpecial = currentModel?.isSpecial == true;

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
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 16,
                color: isPinned ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(isPinned ? '取消置顶' : '置顶联接基金'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'special',
          child: Row(
            children: [
              Icon(
                isSpecial ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 16,
                color: isSpecial ? Colors.orange : null,
              ),
              const SizedBox(width: 8),
              Text(isSpecial ? '取消特别关注' : '特别关注联接基金'),
            ],
          ),
        ),
        if (assocFund != null && assocFund.navs.isNotEmpty)
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
                alreadyInMyFunds ? '从自选删除联接' : '加入自选联接基金',
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
          appConfig.addFund(assocCode, assocName, '估值雷达');
        }
        appConfig.togglePinned(assocCode);
        fundProvider.loadMyFunds();
      } else if (value == 'special') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(assocCode, assocName, '估值雷达');
        }
        appConfig.toggleSpecial(assocCode);
        fundProvider.loadMyFunds();
      } else if (value == 'chart') {
        if (assocFund != null) {
          fluent.showDialog(
            context: context,
            builder: (context) => FundChartDialog(
              fundCode: assocFund.code,
              fundName: assocFund.name,
              navs: assocFund.navs,
              dates: assocFund.dates,
              todayEstimateNav: double.tryParse(assocFund.gsz),
              todayEstimatePct: double.tryParse(assocFund.gszzl),
              todayEstimateTime: assocFund.gztime,
            ),
          );
        }
      } else if (value == 'edit') {
        _editHoldingInfo(
            context, assocCode, assocName, appConfig, fundProvider);
      } else if (value == 'backtest') {
        if (!alreadyInMyFunds) {
          appConfig.addFund(assocCode, assocName, '估值雷达');
          fundProvider.loadMyFunds();
        }
        fundProvider.switchToBacktest(assocCode);
      } else if (value == 'toggle_add') {
        if (alreadyInMyFunds) {
          appConfig.removeFund(assocCode);
        } else {
          appConfig.addFund(assocCode, assocName, '估值雷达');
        }
        fundProvider.loadMyFunds();
      }
    });
  }

  void _editHoldingInfo(BuildContext context, String code, String name,
      AppConfig appConfig, FundProvider fundProvider) {
    if (!appConfig.fundsInfo.containsKey(code)) {
      appConfig.addFund(code, name, '估值雷达');
      fundProvider.loadMyFunds();
    }

    final assocModel = fundProvider.myFunds[code]!;

    fluent.showDialog(
      context: context,
      builder: (context) => HoldingDialog(
        fundCode: assocModel.code,
        fundName: assocModel.name,
        initialIsHeld: assocModel.isHeld,
        initialAmount: assocModel.amount,
        initialYieldRate: assocModel.yieldRate,
        onSave: (isHeld, amount, yieldRate) {
          appConfig.updateHoldInfo(assocModel.code, isHeld, amount, yieldRate);
          fundProvider.loadMyFunds();
          fundProvider.refreshAll();
        },
      ),
    );
  }

  Widget _buildTable(
    List<Map<String, dynamic>> items,
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
    if (items.isEmpty) {
      return const Center(
          child: Text('无此类估值数据', style: TextStyle(color: Colors.grey)));
    }

    final pinyinSearch = PinyinSearch();

    // 拷贝并排序
    final sortedItems = List<Map<String, dynamic>>.from(items);
    if (sortKey != null) {
      sortedItems.sort((a, b) {
        return _compareValuations(a, b, sortKey, sortAscending, fundProvider);
      });
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 720;
    // 小屏冻结模式下，指数名称列宽缩小以节省冻结区域空间
    final double indexNameColWidth =
        (isSmallScreen && appConfig.freezeColumns) ? 95.0 : 120.0;

    final List<_ColConfig> columns = [
      _ColConfig(title: '', width: 30),
      _ColConfig(title: '指数代码', width: 70, sortKey: 'code'),
      _ColConfig(
          title: '指数名称',
          width: indexNameColWidth,
          alignLeft: true,
          sortKey: 'name'),
      _ColConfig(title: 'PE', width: 50, sortKey: 'pe_percentile'),
      _ColConfig(title: 'PB', width: 50, sortKey: 'pb_percentile'),
      _ColConfig(title: '估值状态', width: 70, sortKey: 'tag'),
      _ColConfig(
          title: '关联场外基金', width: 140, alignLeft: true, sortKey: 'assoc_name'),
      _ColConfig(title: '买入信号', width: 100, sortKey: 'optimal'),
      _ColConfig(title: '卖出信号', width: 100, sortKey: 'sell_optimal'),
      _ColConfig(title: '今日收益/\n收益率', width: 95, sortKey: 'gszzl'),
      _ColConfig(title: '昨日', width: 60, sortKey: 'yestZdf'),
      ...appConfig.dropDays.map(
          (d) => _ColConfig(title: '近$d日\n涨跌', width: 55, sortKey: 'drop_$d')),
      ...appConfig.percentileMonths.map((m) =>
          _ColConfig(title: '近$m月\n百分位', width: 55, sortKey: 'percentile_$m')),
      _ColConfig(title: '趋势', width: 80),
      _ColConfig(title: '数据源', width: 70, sortKey: 'src'),
      _ColConfig(title: '操作', width: 100),
    ];

    final double totalWidth =
        columns.map((c) => c.width).reduce((a, b) => a + b);

    Widget buildHeaderCell(_ColConfig col) {
      final hasSort = col.sortKey != null;
      final isCurrentSort = sortKey == col.sortKey;

      Widget headerText = Text(
        col.title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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

      if (col.title == 'PE') {
        headerContent = fluent.Tooltip(
          message: '【看 PE (市盈率)】\n• 适用行业：消费(白酒/家电)、医药、科技/半导体、互联网及宽基指数\n• 判定逻辑：盈利相对稳定或有高成长性，以收益能力定价',
          child: headerContent,
        );
      } else if (col.title == 'PB') {
        headerContent = fluent.Tooltip(
          message: '【看 PB (市净率)】\n• 适用行业：金融(银行/证券/保险)、强周期(煤炭/钢铁/有色/化工)及地产/基建\n• 判定逻辑：重资产或强周期性，盈利波动大，以账面净资产定价',
          child: headerContent,
        );
      }

      return SizedBox(
        width: col.width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: headerContent,
        ),
      );
    }

    Widget buildRow(
        Map<String, dynamic> item, int orderIndex, List<_ColConfig> rowCols,
        {bool isLeftPart = false}) {
      final String indexCode = item['code'] ?? '';
      final String indexName = item['name'] ?? '';
      final String assocCode =
          pinyinSearch.findFundForIndex(indexCode, indexName);
      final bool hasAssoc = assocCode != indexCode;
      final bool alreadyInMyFunds = fundProvider.myFunds.containsKey(assocCode);
      final FundUIModel? currentAssocFund = alreadyInMyFunds
          ? fundProvider.myFunds[assocCode]
          : item['assocFund'] as FundUIModel?;

      final String assocName =
          hasAssoc ? pinyinSearch.getNameByCode(assocCode) : '';
      final double change =
          (currentAssocFund != null && currentAssocFund.isTodayValuation)
              ? (double.tryParse(currentAssocFund.gszzl) ?? 0.0)
              : 0.0;
      final Color changeColor =
          (currentAssocFund != null && currentAssocFund.isTodayValuation)
              ? (change > 0
                  ? ThemeColors.getRedText(isDark)
                  : (change < 0
                      ? ThemeColors.getGreenText(isDark)
                      : ThemeColors.getNormalText(isDark)))
              : ThemeColors.getNormalText(isDark);

      double todayProfit = 0.0;
      if (currentAssocFund != null &&
          currentAssocFund.isHeld &&
          currentAssocFund.amount > 0) {
        todayProfit = (currentAssocFund.amount * change) / 100.0;
      }

      final bool isPinned = currentAssocFund?.isPinned == true;
      final bool isBuySignal = currentAssocFund?.isBuySignal == true;
      final bool isSellSignal = currentAssocFund?.isSellSignal == true;
      final double currentDrop = currentAssocFund?.currentDrop ?? 0.0;
      final double currentRise = currentAssocFund?.currentRise ?? 0.0;

      // 优先触发了买入信号的行高亮显示（淡红色），其次触发了卖出信号的行高亮显示（淡绿色），再次置顶行高亮背景，普通行无背景
      final Color? rowBgColor = isBuySignal
          ? ThemeColors.getRedText(isDark)
              .withValues(alpha: isDark ? 0.20 : 0.12)
          : (isSellSignal
              ? ThemeColors.getGreenText(isDark)
                  .withValues(alpha: isDark ? 0.20 : 0.12)
              : (isPinned
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.yellow.withValues(alpha: 0.05))
                  : null));

      // 提取长按/右键回调，传递给 CopyableText 确保手势统一处理
      void longPressCallback(LongPressStartDetails details) {
        if (hasAssoc) {
          _showContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            assocCode: assocCode,
            assocName: assocName,
            appConfig: appConfig,
            fundProvider: fundProvider,
            assocFund: currentAssocFund,
          );
        }
      }

      void secondaryTapCallback(TapDownDetails details) {
        if (hasAssoc) {
          _showContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            assocCode: assocCode,
            assocName: assocName,
            appConfig: appConfig,
            fundProvider: fundProvider,
            assocFund: currentAssocFund,
          );
        }
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
                    isPinned ? '📌' : '$orderIndex',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  );
                  break;
                case '指数代码':
                  cellContent = CopyableText(
                    indexCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    onLongPressStart: longPressCallback,
                    onSecondaryTapDown: secondaryTapCallback,
                  );
                  break;
                case '指数名称':
                  cellContent = CopyableText(
                    indexName,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    onLongPressStart: longPressCallback,
                    onSecondaryTapDown: secondaryTapCallback,
                  );
                  break;
                case 'PE':
                  final peValStr = item['pe_percentile']?.toString() ?? '';
                  final peVal = double.tryParse(peValStr) ?? -1.0;
                  final peAbsStr = item['pe']?.toString() ?? '';
                  final peAbsVal = double.tryParse(peAbsStr);
                  final peAbsText = peAbsVal != null
                      ? peAbsVal.toThousand(precision: 1)
                      : (peAbsStr.isNotEmpty ? peAbsStr : '--');

                  Color? cellBg;
                  Color textColor = ThemeColors.getNormalText(isDark);
                  if (peVal >= 0) {
                    if (peVal <= 20.0) {
                      cellBg = ThemeColors.getLowPercentileBg(isDark);
                      textColor = ThemeColors.getLowPercentileText(isDark);
                    } else if (peVal >= 80.0) {
                      cellBg = ThemeColors.getHighPercentileBg(isDark);
                      textColor = ThemeColors.getHighPercentileText(isDark);
                    }
                  }
                  cellContent = Container(
                    color: cellBg,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          peVal < 0
                              ? '--'
                              : '${peVal.toThousand(precision: 1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: (peVal <= 20.0 || peVal >= 80.0)
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          peAbsText,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  );
                  break;
                case 'PB':
                  final pbValStr = item['pb_percentile']?.toString() ?? '';
                  final pbVal = double.tryParse(pbValStr) ?? -1.0;
                  final pbAbsStr = item['pb']?.toString() ?? '';
                  final pbAbsVal = double.tryParse(pbAbsStr);
                  final pbAbsText = pbAbsVal != null
                      ? pbAbsVal.toThousand(precision: 2)
                      : (pbAbsStr.isNotEmpty ? pbAbsStr : '--');

                  Color? cellBg;
                  Color textColor = ThemeColors.getNormalText(isDark);
                  if (pbVal >= 0) {
                    if (pbVal <= 20.0) {
                      cellBg = ThemeColors.getLowPercentileBg(isDark);
                      textColor = ThemeColors.getLowPercentileText(isDark);
                    } else if (pbVal >= 80.0) {
                      cellBg = ThemeColors.getHighPercentileBg(isDark);
                      textColor = ThemeColors.getHighPercentileText(isDark);
                    }
                  }
                  cellContent = Container(
                    color: cellBg,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          pbVal < 0
                              ? '--'
                              : '${pbVal.toThousand(precision: 1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: (pbVal <= 20.0 || pbVal >= 80.0)
                                ? FontWeight.bold
                                : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pbAbsText,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                  break;
                case '估值状态':
                  final tagStr = item['tag']?.toString() ?? '';
                  final Color tagColor = tagStr.contains('低')
                      ? ThemeColors.getGreenText(isDark)
                      : (tagStr.contains('高')
                          ? ThemeColors.getRedText(isDark)
                          : ThemeColors.getNormalText(isDark));
                  cellContent = Text(
                    tagStr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: tagColor),
                  );
                  break;
                case '关联场外基金':
                  if (hasAssoc) {
                    cellContent = Row(
                      children: [
                        Expanded(
                          child: CopyableText(
                            assocName,
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (currentAssocFund?.errorMsg != null) ...[
                          const SizedBox(width: 4),
                          fluent.Tooltip(
                            message: currentAssocFund!.errorMsg!,
                            useMousePosition: true,
                            child: Icon(Icons.warning_amber_rounded,
                                color: ThemeColors.getRedText(isDark),
                                size: 14),
                          ),
                        ],
                        if (currentAssocFund?.isHeld == true) ...[
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
                        ],
                      ],
                    );
                  } else {
                    cellContent = const Text(
                      '无关联',
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  }
                  break;
                case '今日收益/收益率':
                  if (hasAssoc && currentAssocFund != null) {
                    cellContent = MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () => _editHoldingInfo(context, assocCode,
                            assocName, appConfig, fundProvider),
                        child: Text(
                          currentAssocFund.isHeld && currentAssocFund.amount > 0
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
                  } else {
                    cellContent = const Text('--',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  break;
                case '昨日':
                  if (hasAssoc && currentAssocFund != null) {
                    final yestChange =
                        double.tryParse(currentAssocFund.yestZdf) ?? 0.0;
                    final yestColor = yestChange > 0
                        ? ThemeColors.getRedText(isDark)
                        : (yestChange < 0
                            ? ThemeColors.getGreenText(isDark)
                            : ThemeColors.getNormalText(isDark));
                    cellContent = Text(
                      '${yestChange > 0 ? '+' : ''}${currentAssocFund.yestZdf}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: yestColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  } else {
                    cellContent = const Text('--',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  break;
                case '买入信号':
                  if (!hasAssoc) {
                    cellContent = const Text(
                      '--',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  } else {
                    if (currentAssocFund?.optimalStrategy != null) {
                      final s = currentAssocFund!.optimalStrategy!;
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
                                border:
                                    Border.all(color: badgeBorder, width: 1),
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
                        final recentBuyIdx = currentAssocFund
                            .getRecentBuyTriggerIndex(maxDays: 3);
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
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
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
                        optimalStrategy: currentAssocFund?.optimalStrategy,
                      );
                    }
                  }
                  break;
                case '卖出信号':
                  if (!hasAssoc) {
                    cellContent = const Text(
                      '--',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  } else {
                    if (currentAssocFund?.optimalStrategy != null &&
                        currentAssocFund!.optimalStrategy!['sell_x'] != null) {
                      final s = currentAssocFund.optimalStrategy!;
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
                                border:
                                    Border.all(color: badgeBorder, width: 1),
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
                        optimalStrategy: currentAssocFund?.optimalStrategy,
                      );
                    }
                  }
                  break;
                case '趋势':
                  if (hasAssoc &&
                      currentAssocFund != null &&
                      currentAssocFund.navs.isNotEmpty) {
                    cellContent = MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () {
                          fluent.showDialog(
                            context: context,
                            builder: (context) => FundChartDialog(
                              fundCode: currentAssocFund.code,
                              fundName: currentAssocFund.name,
                              navs: currentAssocFund.navs,
                              dates: currentAssocFund.dates,
                              todayEstimateNav:
                                  double.tryParse(currentAssocFund.gsz),
                              todayEstimatePct:
                                  double.tryParse(currentAssocFund.gszzl),
                              todayEstimateTime: currentAssocFund.gztime,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4.0, horizontal: 2.0),
                            child: Sparkline(data: currentAssocFund.navs),
                          ),
                        ),
                      ),
                    );
                  } else {
                    cellContent = const Text('--',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  break;
                case '数据源':
                  if (hasAssoc && currentAssocFund != null) {
                    cellContent = Text(
                      currentAssocFund.source.isEmpty
                          ? '-'
                          : currentAssocFund.source,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    );
                  } else {
                    cellContent = const Text('--',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  break;
                case '操作':
                  if (hasAssoc && currentAssocFund != null) {
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
                                  appConfig.addFund(currentAssocFund.code,
                                      currentAssocFund.name, '估值雷达');
                                  fundProvider.loadMyFunds();
                                  fluent.displayInfoBar(
                                    context,
                                    builder: (context, close) {
                                      return fluent.InfoBar(
                                        title: const Text('自选添加成功'),
                                        content: Text(
                                            '${currentAssocFund.name} 已成功加入自选。'),
                                        severity:
                                            fluent.InfoBarSeverity.success,
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
                              appConfig.addFund(currentAssocFund.code,
                                  currentAssocFund.name, '估值雷达');
                              fundProvider.loadMyFunds();
                            }
                            fundProvider
                                .switchToBacktest(currentAssocFund.code);
                          },
                        ),
                      ],
                    );
                  } else {
                    cellContent = const Text('--',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  break;
                default:
                  if (cleanTitle.startsWith('近') &&
                      cleanTitle.endsWith('日涨跌')) {
                    final dayStr =
                        cleanTitle.replaceAll('近', '').replaceAll('日涨跌', '');
                    final int d = int.tryParse(dayStr) ?? 0;
                    final val = currentAssocFund?.drops[d] ?? 0.0;
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
                    final val = currentAssocFund?.pcts[m] ?? -1.0;

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
      final List<_ColConfig> leftColumns = columns
          .where((col) => col.title == '#' || col.title == '' || col.title == '指数名称')
          .toList();
      final List<_ColConfig> rightColumns = columns
          .where((col) => col.title != '#' && col.title != '' && col.title != '指数名称')
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
                      height: 55,
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
                          await fundProvider.fetchValuations();
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          controller: leftVerticalController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: sortedItems.length,
                          itemBuilder: (context, idx) {
                            final item = sortedItems[idx];
                            return buildRow(item, idx + 1, leftColumns,
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
                  controller: horizontalController,
                  child: SingleChildScrollView(
                    controller: horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rightTableWidth,
                      child: Column(
                        children: [
                          Container(
                            height: 55,
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
                            child: fluent.Scrollbar(
                              controller: rightVerticalController,
                              child: RefreshIndicator(
                                onRefresh: () async {
                                  await fundProvider.fetchValuations();
                                },
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  controller: rightVerticalController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: sortedItems.length,
                                  itemBuilder: (context, idx) {
                                    final item = sortedItems[idx];
                                    return buildRow(
                                        item, idx + 1, rightColumns);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
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
            controller: horizontalController,
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    Container(
                      height: 55,
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
                      child: fluent.Scrollbar(
                        controller: rightVerticalController,
                        child: RefreshIndicator(
                          onRefresh: () async {
                            await fundProvider.fetchValuations();
                          },
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            controller: rightVerticalController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: sortedItems.length,
                            itemBuilder: (context, idx) {
                              final item = sortedItems[idx];
                              return buildRow(item, idx + 1, columns);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildTabBar(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabButton(0, '历史低估', Icons.trending_down_rounded,
              ThemeColors.getGreenText(isDark), isDark),
          const SizedBox(width: 8),
          _buildTabButton(1, '历史最低', Icons.keyboard_double_arrow_down_rounded,
              ThemeColors.getGreenText(isDark), isDark),
          const SizedBox(width: 8),
          _buildTabButton(2, '历史高估', Icons.trending_up_rounded,
              ThemeColors.getRedText(isDark), isDark),
          const SizedBox(width: 8),
          _buildTabButton(3, '历史最高', Icons.keyboard_double_arrow_up_rounded,
              ThemeColors.getRedText(isDark), isDark),
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

    final pinyinSearch = PinyinSearch();
    final List<Map<String, dynamic>> filteredValuationList =
        fundProvider.valuationList.where((item) {
      if (_searchText.isEmpty) return true;
      final q = _searchText.toLowerCase();
      final String indexCode = (item['code'] ?? '').toString().toLowerCase();
      final String indexName = (item['name'] ?? '').toString().toLowerCase();

      // 获取关联场外基金信息进行搜索
      final String assocCode =
          pinyinSearch.findFundForIndex(indexCode, indexName);
      final bool hasAssoc = assocCode != indexCode;
      final String assocName =
          hasAssoc ? pinyinSearch.getNameByCode(assocCode).toLowerCase() : '';

      return indexCode.contains(q) ||
          indexName.contains(q) ||
          assocCode.toLowerCase().contains(q) ||
          assocName.contains(q);
    }).toList();

    // 如果开启"只看近日买入触发"，进行二次过滤
    if (_onlyShowRecentBuySignals) {
      filteredValuationList.retainWhere((item) {
        final String indexCode = item['code'] ?? '';
        final String indexName = item['name'] ?? '';
        final String assocCode =
            pinyinSearch.findFundForIndex(indexCode, indexName);
        final bool hasAssoc = assocCode != indexCode;
        if (hasAssoc) {
          final bool alreadyInMyFunds =
              fundProvider.myFunds.containsKey(assocCode);
          final FundUIModel? currentAssocFund = alreadyInMyFunds
              ? fundProvider.myFunds[assocCode]
              : item['assocFund'] as FundUIModel?;

          if (currentAssocFund != null) {
            return currentAssocFund.isBuySignal ||
                currentAssocFund.getRecentBuyTriggerIndex(maxDays: 3) != null;
          }
        }
        return false;
      });
    }

    // 如果开启"只看买入触发"，进行二次过滤
    if (_onlyShowBuySignals) {
      filteredValuationList.retainWhere((item) {
        final String indexCode = item['code'] ?? '';
        final String indexName = item['name'] ?? '';
        final String assocCode =
            pinyinSearch.findFundForIndex(indexCode, indexName);
        final bool hasAssoc = assocCode != indexCode;
        if (hasAssoc) {
          final bool alreadyInMyFunds =
              fundProvider.myFunds.containsKey(assocCode);
          final FundUIModel? currentAssocFund = alreadyInMyFunds
              ? fundProvider.myFunds[assocCode]
              : item['assocFund'] as FundUIModel?;

          if (currentAssocFund != null) {
            return currentAssocFund.isBuySignal;
          }
        }
        return false;
      });
    }

    // 如果开启"只看卖出触发"，进行二次过滤
    if (_onlyShowSellSignals) {
      filteredValuationList.retainWhere((item) {
        final String indexCode = item['code'] ?? '';
        final String indexName = item['name'] ?? '';
        final String assocCode =
            pinyinSearch.findFundForIndex(indexCode, indexName);
        final bool hasAssoc = assocCode != indexCode;
        if (hasAssoc) {
          final bool alreadyInMyFunds =
              fundProvider.myFunds.containsKey(assocCode);
          final FundUIModel? currentAssocFund = alreadyInMyFunds
              ? fundProvider.myFunds[assocCode]
              : item['assocFund'] as FundUIModel?;

          if (currentAssocFund != null) {
            return currentAssocFund.isSellSignal;
          }
        }
        return false;
      });
    }

    final List<Map<String, dynamic>> lowList = filteredValuationList
        .where((x) => x['tag'].toString().contains('低'))
        .toList();

    final List<Map<String, dynamic>> lowestList =
        filteredValuationList.where((x) {
      final peVal =
          double.tryParse(x['pe_percentile']?.toString() ?? '') ?? -1.0;
      final pbVal =
          double.tryParse(x['pb_percentile']?.toString() ?? '') ?? -1.0;
      return (peVal >= 0 && peVal <= 10.0) || (pbVal >= 0 && pbVal <= 10.0);
    }).toList();

    final List<Map<String, dynamic>> highList = filteredValuationList
        .where((x) => x['tag'].toString().contains('高'))
        .toList();

    final List<Map<String, dynamic>> highestList =
        filteredValuationList.where((x) {
      final peVal =
          double.tryParse(x['pe_percentile']?.toString() ?? '') ?? -1.0;
      final pbVal =
          double.tryParse(x['pb_percentile']?.toString() ?? '') ?? -1.0;
      return peVal >= 90.0 || pbVal >= 90.0;
    }).toList();

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
          text: Text(isSmallScreen ? '刷新估值榜' : '一键刷新估值榜',
              style: const TextStyle(fontSize: 12)),
          onPressed: () {
            fundProvider.valuationLoaded = false;
            fundProvider.fetchValuations();
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
          text: const Text('冻结列(指数名称)', style: TextStyle(fontSize: 12)),
          onPressed: () {
            appConfig.toggleFreezeColumns(!appConfig.freezeColumns);
          },
        ),
        fluent.MenuFlyoutItem(
          leading: const Icon(Icons.lightbulb_outline_rounded,
              size: 14, color: Colors.blue),
          text: const Text('PE/PB看盘指南', style: TextStyle(fontSize: 12)),
          onPressed: () {
            _showValuationGuideDialog(context, isDark);
          },
        ),
      ],
    );

    final Widget headerWidget = isSmallScreen
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: fluent.WrapCrossAlignment.center,
              children: [
                searchBox,
                moreBtn,
              ],
            ),
          );

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSmallScreen)
            MobileHeader(
              title: '估值雷达',
              searchBox: searchBox,
              moreBtn: moreBtn,
            ),
          if (!isSmallScreen)
            Padding(
              padding:
                  const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0),
              child: headerWidget,
            ),
          _buildTabBar(isDark),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10.0, bottom: 10.0),
              child: !fundProvider.valuationLoaded
                  ? const Center(child: fluent.ProgressRing())
                  : (_tabIndex == 0
                      ? _buildTable(
                          lowList,
                          isDark,
                          appConfig,
                          fundProvider,
                          _lowHorizontalController,
                          _lowLeftVerticalController,
                          _lowRightVerticalController,
                          _lowSortKey,
                          _lowSortAscending,
                          (key, ascending) {
                            setState(() {
                              _lowSortKey = key;
                              _lowSortAscending = ascending;
                            });
                          },
                          isFullHeight: true,
                        )
                      : _tabIndex == 1
                          ? _buildTable(
                              lowestList,
                              isDark,
                              appConfig,
                              fundProvider,
                              _lowestHorizontalController,
                              _lowestLeftVerticalController,
                              _lowestRightVerticalController,
                              _lowestSortKey,
                              _lowestSortAscending,
                              (key, ascending) {
                                setState(() {
                                  _lowestSortKey = key;
                                  _lowestSortAscending = ascending;
                                });
                              },
                              isFullHeight: true,
                            )
                          : _tabIndex == 2
                              ? _buildTable(
                                  highList,
                                  isDark,
                                  appConfig,
                                  fundProvider,
                                  _highHorizontalController,
                                  _highLeftVerticalController,
                                  _highRightVerticalController,
                                  _highSortKey,
                                  _highSortAscending,
                                  (key, ascending) {
                                    setState(() {
                                      _highSortKey = key;
                                      _highSortAscending = ascending;
                                    });
                                  },
                                  isFullHeight: true,
                                )
                              : _buildTable(
                                  highestList,
                                  isDark,
                                  appConfig,
                                  fundProvider,
                                  _highestHorizontalController,
                                  _highestLeftVerticalController,
                                  _highestRightVerticalController,
                                  _highestSortKey,
                                  _highestSortAscending,
                                  (key, ascending) {
                                    setState(() {
                                      _highestSortKey = key;
                                      _highestSortAscending = ascending;
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

  int _compareValuations(Map<String, dynamic> a, Map<String, dynamic> b,
      String key, bool ascending, FundProvider fundProvider) {
    int result = 0;

    // 获取关联场外基金模型
    final pinyinSearch = PinyinSearch();
    FundUIModel? getAssocFund(Map<String, dynamic> item) {
      final String indexCode = item['code'] ?? '';
      final String indexName = item['name'] ?? '';
      final String assocCode =
          pinyinSearch.findFundForIndex(indexCode, indexName);
      if (assocCode != indexCode) {
        if (fundProvider.myFunds.containsKey(assocCode)) {
          return fundProvider.myFunds[assocCode];
        }
        return item['assocFund'] as FundUIModel?;
      }
      return null;
    }

    final fundA = getAssocFund(a);
    final fundB = getAssocFund(b);

    switch (key) {
      case 'code':
        result = (a['code'] ?? '').compareTo(b['code'] ?? '');
        break;
      case 'name':
        result = (a['name'] ?? '').compareTo(b['name'] ?? '');
        break;
      case 'pe_percentile':
        final valA =
            double.tryParse(a['pe_percentile']?.toString() ?? '') ?? -1.0;
        final valB =
            double.tryParse(b['pe_percentile']?.toString() ?? '') ?? -1.0;
        result = valA.compareTo(valB);
        break;
      case 'pb_percentile':
        final valA =
            double.tryParse(a['pb_percentile']?.toString() ?? '') ?? -1.0;
        final valB =
            double.tryParse(b['pb_percentile']?.toString() ?? '') ?? -1.0;
        result = valA.compareTo(valB);
        break;
      case 'tag':
        result = (a['tag'] ?? '').compareTo(b['tag'] ?? '');
        break;
      case 'assoc_name':
        final nameA = fundA?.name ?? '';
        final nameB = fundB?.name ?? '';
        result = nameA.compareTo(nameB);
        break;
      case 'pinned':
        final valA = (fundA?.isPinned ?? false) ? 1 : 0;
        final valB = (fundB?.isPinned ?? false) ? 1 : 0;
        result = valA.compareTo(valB);
        break;
      case 'special':
        final valA = (fundA?.isSpecial ?? false) ? 1 : 0;
        final valB = (fundB?.isSpecial ?? false) ? 1 : 0;
        result = valA.compareTo(valB);
        break;
      case 'yestZdf':
        final valA = double.tryParse(fundA?.yestZdf ?? '') ?? 0.0;
        final valB = double.tryParse(fundB?.yestZdf ?? '') ?? 0.0;
        result = valA.compareTo(valB);
        break;
      case 'gszzl':
        final valA = double.tryParse(fundA?.gszzl ?? '') ?? 0.0;
        final valB = double.tryParse(fundB?.gszzl ?? '') ?? 0.0;
        result = valA.compareTo(valB);
        break;
      case 'optimal':
        final hasA = fundA?.optimalStrategy != null;
        final hasB = fundB?.optimalStrategy != null;
        if (hasA && !hasB) return -1;
        if (!hasA && hasB) return 1;
        if (!hasA && !hasB) return 0;
        final dropA = fundA!.optimalStrategy!['buy_drop'] ?? 0.0;
        final dropB = fundB!.optimalStrategy!['buy_drop'] ?? 0.0;
        result = dropA.compareTo(dropB);
        break;
      case 'src':
        String getSrc(String gztime) {
          if (gztime.contains('[') && gztime.contains(']')) {
            final start = gztime.indexOf('[') + 1;
            final end = gztime.indexOf(']');
            if (start < end) return gztime.substring(start, end);
          }
          return '';
        }
        final srcA = getSrc(fundA?.gztime ?? '');
        final srcB = getSrc(fundB?.gztime ?? '');
        result = srcA.compareTo(srcB);
        break;
      default:
        if (key.startsWith('drop_')) {
          final d = int.tryParse(key.substring(5)) ?? 0;
          final valA = fundA?.drops[d] ?? 0.0;
          final valB = fundB?.drops[d] ?? 0.0;
          result = valA.compareTo(valB);
        } else if (key.startsWith('percentile_')) {
          final m = int.tryParse(key.substring(11)) ?? 0;
          final valA = fundA?.pcts[m] ?? -1.0;
          final valB = fundB?.pcts[m] ?? -1.0;
          result = valA.compareTo(valB);
        }
        break;
    }
    return ascending ? result : -result;
  }
}

class _ColConfig {
  final String title;
  final double width;
  final bool alignLeft;
  final String? sortKey;

  _ColConfig({
    required this.title,
    required this.width,
    this.alignLeft = false,
    this.sortKey,
  });
}
