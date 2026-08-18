import 'dart:async';
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
        AlwaysScrollableScrollPhysics,
        BouncingScrollPhysics;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/fund_provider.dart';
import '../../core/config.dart';
import '../../core/utils/theme_colors.dart';
import '../widgets/holding_dialog.dart';
import '../widgets/sparkline.dart';
import '../widgets/fund_chart_dialog.dart';
import '../widgets/scaled_checkbox.dart';
import '../widgets/expandable_search_box.dart';
import '../widgets/mobile_header.dart';
import '../widgets/copyable_text.dart';
import '../widgets/unoptimized_badge.dart';

class SpecialAttentionTab extends StatefulWidget {
  const SpecialAttentionTab({super.key});

  @override
  State<SpecialAttentionTab> createState() => _SpecialAttentionTabState();
}

class _SpecialAttentionTabState extends State<SpecialAttentionTab> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _leftVerticalScrollController = ScrollController();
  final ScrollController _rightVerticalScrollController = ScrollController();
  final TextEditingController _localSearchController = TextEditingController();
  String _searchText = '';
  bool _onlyShowBuySignals = false;
  bool _onlyShowSellSignals = false;
  bool _onlyShowRecentBuySignals = false;
  String? _sortKey;
  bool _sortAscending = false;
  final Set<String> _selectedCodes = {};
  bool _isMultiSelectMode = false;

  bool _isSyncing = false; // 防止 ScrollController 互相触发无限递归
  double _horizontalOffset = 0.0;
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<void>? _searchFocusSub;

  void _onHorizontalScroll() {
    if (_horizontalScrollController.hasClients) {
      if ((_horizontalScrollController.offset > 0 && _horizontalOffset == 0) ||
          (_horizontalScrollController.offset == 0 && _horizontalOffset > 0)) {
        setState(() {
          _horizontalOffset = _horizontalScrollController.offset;
        });
      }
    }
  }

  void _onLeftVerticalScroll() {
    if (_isSyncing) return;
    if (_leftVerticalScrollController.hasClients &&
        _rightVerticalScrollController.hasClients) {
      if (_leftVerticalScrollController.offset == 0 &&
          _rightVerticalScrollController.offset == 0) {
        return;
      }
      if (_leftVerticalScrollController.offset !=
          _rightVerticalScrollController.offset) {
        _isSyncing = true;
        _rightVerticalScrollController
            .jumpTo(_leftVerticalScrollController.offset);
        _isSyncing = false;
      }
    }
  }

  void _onRightVerticalScroll() {
    if (_isSyncing) return;
    if (_leftVerticalScrollController.hasClients &&
        _rightVerticalScrollController.hasClients) {
      if (_leftVerticalScrollController.offset == 0 &&
          _rightVerticalScrollController.offset == 0) {
        return;
      }
      if (_rightVerticalScrollController.offset !=
          _leftVerticalScrollController.offset) {
        _isSyncing = true;
        _leftVerticalScrollController
            .jumpTo(_rightVerticalScrollController.offset);
        _isSyncing = false;
      }
    }
  }

  // 批量取消关注选中的基金
  void _confirmRemoveSpecialSelected(
      BuildContext context, AppConfig appConfig, FundProvider fundProvider) {
    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: const Text('批量取消关注确认'),
          content: Text('确定要将这 ${_selectedCodes.length} 只基金取消特别关注吗？'),
          actions: [
            fluent.Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            fluent.FilledButton(
              style: fluent.ButtonStyle(
                backgroundColor:
                    fluent.WidgetStateProperty.all(Colors.orangeAccent),
                foregroundColor: fluent.WidgetStateProperty.all(Colors.white),
              ),
              child: const Text('确定'),
              onPressed: () {
                for (var code in _selectedCodes) {
                  appConfig.toggleSpecial(code);
                }
                _selectedCodes.clear();
                fundProvider.loadMyFunds();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    _searchFocusSub = fundProvider.searchFocusStream.listen((_) {
      if (mounted && fundProvider.currentTabIndex == 1) {
        _searchFocusNode.requestFocus();
      }
    });

    _horizontalScrollController.addListener(_onHorizontalScroll);
    _leftVerticalScrollController.addListener(_onLeftVerticalScroll);
    _rightVerticalScrollController.addListener(_onRightVerticalScroll);
  }

  @override
  void dispose() {
    _searchFocusSub?.cancel();
    _searchFocusNode.dispose();
    _horizontalScrollController.removeListener(_onHorizontalScroll);
    _horizontalScrollController.dispose();
    _leftVerticalScrollController.removeListener(_onLeftVerticalScroll);
    _rightVerticalScrollController.removeListener(_onRightVerticalScroll);
    _leftVerticalScrollController.dispose();
    _rightVerticalScrollController.dispose();
    _localSearchController.dispose();
    super.dispose();
  }

  // 弹出编辑持有信息的对话框
  void _editHoldingInfo(
      BuildContext context, FundUIModel model, AppConfig appConfig) {
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
          // 重新更新 provider 的内存缓存
          final fundProvider =
              Provider.of<FundProvider>(context, listen: false);
          fundProvider.loadMyFunds();
          // 更新持仓后，静默触发一次刷新以重新计算今日盈亏
          fundProvider.refreshAll();
        },
      ),
    );
  }

  // 弹出修改板块分类的对话框
  void _editFundSector(
      BuildContext context, FundUIModel model, AppConfig appConfig) {
    final TextEditingController controller =
        TextEditingController(text: model.sector);
    final fundProvider = Provider.of<FundProvider>(context, listen: false);

    // 获取当前自选列表中所有的有效板块分类，用于快速选择
    final Set<String> existingSectors = fundProvider.myFunds.values
        .map((f) => f.sector)
        .where((s) => s.isNotEmpty && s != '其它')
        .toSet();

    fluent.showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return fluent.ContentDialog(
              title: Text('修改板块分类 - ${model.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('板块分类名称：'),
                  const SizedBox(height: 8),
                  fluent.TextBox(
                    controller: controller,
                    placeholder: '请输入板块分类名称',
                    autofocus: true,
                  ),
                  if (existingSectors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('已有分类（点击快速选择）：',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: existingSectors.map((sector) {
                        return fluent.Button(
                          style: fluent.ButtonStyle(
                            padding: fluent.WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                          child: Text(sector,
                              style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() {
                              controller.text = sector;
                            });
                          },
                        );
                      }).toList(),
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
                  child: const Text('确定'),
                  onPressed: () {
                    final newSector = controller.text.trim();
                    if (newSector.isNotEmpty) {
                      appConfig.updateFundSector(model.code, newSector);
                      fundProvider.loadMyFunds();
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    FundUIModel model,
    AppConfig appConfig,
    FundProvider fundProvider,
  ) async {
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
                model.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 16,
                color: model.isPinned ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(model.isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'special',
          child: Row(
            children: [
              Icon(
                model.isSpecial
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 16,
                color: model.isSpecial ? Colors.orange : null,
              ),
              const SizedBox(width: 8),
              Text(model.isSpecial ? '取消特别关注' : '特别关注'),
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
        const PopupMenuItem<String>(
          value: 'sector',
          child: Row(
            children: [
              Icon(Icons.category_rounded, size: 16, color: Colors.teal),
              SizedBox(width: 8),
              Text('修改板块分类'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: ThemeColors.getRedText(
                    Theme.of(context).brightness == Brightness.dark),
              ),
              const SizedBox(width: 8),
              Text(
                '从自选删除',
                style: TextStyle(
                    color: ThemeColors.getRedText(
                        Theme.of(context).brightness == Brightness.dark)),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'pin') {
        appConfig.togglePinned(model.code);
        fundProvider.loadMyFunds();
      } else if (value == 'special') {
        appConfig.toggleSpecial(model.code);
        fundProvider.loadMyFunds();
      } else if (value == 'chart') {
        fluent.showDialog(
          context: context,
          builder: (context) => FundChartDialog(
            fundCode: model.code,
            fundName: model.name,
            navs: model.navs,
            dates: model.dates,
            todayEstimateNav: double.tryParse(model.gsz),
            todayEstimatePct: double.tryParse(model.gszzl),
            todayEstimateTime: model.gztime,
          ),
        );
      } else if (value == 'edit') {
        _editHoldingInfo(context, model, appConfig);
      } else if (value == 'backtest') {
        fundProvider.switchToBacktest(model.code);
      } else if (value == 'sector') {
        _editFundSector(context, model, appConfig);
      } else if (value == 'delete') {
        appConfig.removeFund(model.code);
        fundProvider.loadMyFunds();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundProvider = Provider.of<FundProvider>(context);
    final appConfig = Provider.of<AppConfig>(context);

    // 过滤出特别关注的基金
    final List<FundUIModel> list =
        fundProvider.myFunds.values.where((model) => model.isSpecial).toList();

    // 模糊搜索过滤当前列表
    final filteredList = list.where((model) {
      if (_searchText.isEmpty) return true;
      final q = _searchText.toLowerCase();
      return model.code.toLowerCase().contains(q) ||
          model.name.toLowerCase().contains(q) ||
          model.sector.toLowerCase().contains(q);
    }).toList();

    // 排序逻辑
    if (_sortKey != null) {
      filteredList.sort((a, b) {
        return FundSorter.compare(a, b, _sortKey!, _sortAscending);
      });
    } else {
      // 按照置顶和拼音/代码排序：置顶的在最上方
      filteredList.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return a.code.compareTo(b.code);
      });
    }

    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    // 计算触发买入信号的特别关注基金
    final List<FundUIModel> buySignalFunds =
        filteredList.where((model) => model.isBuySignal).toList();

    // 计算触发卖出信号的特别关注基金
    final List<FundUIModel> sellSignalFunds =
        filteredList.where((model) => model.isSellSignal).toList();

    // 计算近日买入触发的特别关注基金
    final List<FundUIModel> recentBuySignalFunds = filteredList
        .where((model) =>
            model.isBuySignal ||
            model.getRecentBuyTriggerIndex(maxDays: 3) != null)
        .toList();

    final displayList = _onlyShowRecentBuySignals
        ? recentBuySignalFunds
        : (_onlyShowBuySignals
            ? buySignalFunds
            : (_onlyShowSellSignals ? sellSignalFunds : filteredList));

    // 定义每列的配置宽度与标题 (和自选保持一致)
    final List<ColConfig> columns = [
      if (_isMultiSelectMode) ColConfig(title: '选', width: 25),
      ColConfig(title: '', width: 25),
      ColConfig(title: '基金名称', width: 160, alignLeft: true, sortKey: 'name'),
      ColConfig(title: '代码', width: 60, sortKey: 'code'),
      ColConfig(title: '板块分类', width: 70, alignLeft: true, sortKey: 'sector'),
      ColConfig(title: '买入信号', width: 100, sortKey: 'optimal'),
      ColConfig(title: '卖出信号', width: 100, sortKey: 'sell_optimal'),
      ColConfig(title: '今日收益/\n收益率', width: 95, sortKey: 'gszzl'),
      ColConfig(title: '昨日', width: 60, sortKey: 'yestZdf'),
      // 动态生成的天数涨跌列
      ...appConfig.dropDays.map(
          (d) => ColConfig(title: '近$d日\n涨跌', width: 55, sortKey: 'drop_$d')),
      ...appConfig.percentileMonths.map((m) =>
          ColConfig(title: '近$m月\n百分位', width: 55, sortKey: 'percentile_$m')),
      ColConfig(title: '趋势', width: 80),
      ColConfig(title: '数据源', width: 70, sortKey: 'src'),
      ColConfig(title: '估值时间', width: 130, sortKey: 'gztime'),
      ColConfig(title: '操作', width: 85),
    ];

    final double totalTableWidth =
        columns.map((c) => c.width).reduce((a, b) => a + b);

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 720;

    final Widget searchBox = ExpandableSearchBox(
      controller: _localSearchController,
      focusNode: _searchFocusNode,
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
          text: Text(isSmallScreen ? '刷新估值' : '一键刷新估值',
              style: const TextStyle(fontSize: 12)),
          onPressed: fundProvider.isRefreshing
              ? null
              : () => fundProvider.refreshAll(isForce: true),
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
        fluent.MenuFlyoutItem(
          leading: Icon(
            _isMultiSelectMode
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: _isMultiSelectMode ? Colors.blue : Colors.grey,
          ),
          text: const Text('多选操作', style: TextStyle(fontSize: 12)),
          onPressed: () {
            setState(() {
              _isMultiSelectMode = !_isMultiSelectMode;
              if (!_isMultiSelectMode) {
                _selectedCodes.clear();
              }
            });
          },
        ),
      ],
    );

    final Widget removeSelectedBtn = _selectedCodes.isEmpty
        ? const fluent.Button(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline_rounded, size: 14),
                SizedBox(width: 4),
                Text('批量取消关注 (0)', style: TextStyle(fontSize: 12)),
              ],
            ),
          )
        : fluent.Button(
            style: fluent.ButtonStyle(
              backgroundColor:
                  fluent.WidgetStateProperty.all(Colors.orangeAccent),
              foregroundColor: fluent.WidgetStateProperty.all(Colors.white),
            ),
            onPressed: () =>
                _confirmRemoveSpecialSelected(context, appConfig, fundProvider),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_outline_rounded,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  isSmallScreen
                      ? '取消关注 (${_selectedCodes.length})'
                      : '批量取消关注 (${_selectedCodes.length})',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          );

    final Widget headerWidget = isSmallScreen
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              mainAxisAlignment: fluent.MainAxisAlignment.end,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: fluent.WrapCrossAlignment.center,
                  children: [
                    searchBox,
                    moreBtn,
                    if (_isMultiSelectMode) removeSelectedBtn,
                  ],
                ),
              ],
            ),
          );

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fundProvider.isRefreshing)
            const SizedBox(
              width: double.infinity,
              height: 4.5,
              child: fluent.ProgressBar(),
            ),
          if (isSmallScreen)
            MobileHeader(
              title: '特别关注',
              searchBox: searchBox,
              moreBtn: moreBtn,
              extraBtn: _isMultiSelectMode ? removeSelectedBtn : null,
            ),
          Expanded(
            child: list.isEmpty
                ? Padding(
                    padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: isSmallScreen ? 0.0 : 12.0),
                    child: Column(
                      children: [
                        headerWidget,
                        const Expanded(
                          child: Center(
                            child: Text(
                              '暂无特别关注基金。在“自选看板”点击星星图标即可将基金加入核心监控区。',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.only(
                        left: 12.0,
                        right: 12.0,
                        top: isSmallScreen ? 4.0 : 6.0,
                        bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerWidget,
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color:
                                      isDark ? Colors.white10 : Colors.black12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: () {
                                Widget buildHeaderCell(ColConfig col) {
                                  if (col.title == '选') {
                                    final bool allSelected = displayList
                                            .isNotEmpty &&
                                        displayList.every((f) =>
                                            _selectedCodes.contains(f.code));
                                    final bool anySelected = displayList.any(
                                        (f) => _selectedCodes.contains(f.code));
                                    return SizedBox(
                                      width: col.width,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 2.0),
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: ScaledCheckbox(
                                            checked: allSelected
                                                ? true
                                                : (anySelected ? null : false),
                                            onChanged: (val) {
                                              setState(() {
                                                if (allSelected) {
                                                  for (var f in displayList) {
                                                    _selectedCodes.remove(f.code);
                                                  }
                                                } else {
                                                  for (var f in displayList) {
                                                    _selectedCodes.add(f.code);
                                                  }
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final hasSort = col.sortKey != null;
                                  final isCurrentSort = _sortKey == col.sortKey;

                                  Widget headerText = Text(
                                    col.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                        height: 1.1),
                                    textAlign: col.alignLeft
                                        ? TextAlign.left
                                        : TextAlign.center,
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
                                          setState(() {
                                            if (_sortKey == col.sortKey) {
                                              if (!_sortAscending) {
                                                _sortAscending = true;
                                              } else {
                                                _sortKey = null;
                                              }
                                            } else {
                                              _sortKey = col.sortKey;
                                              _sortAscending = false;
                                            }
                                          });
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
                                                  ? (_sortAscending
                                                      ? Icons
                                                          .arrow_upward_rounded
                                                      : Icons
                                                          .arrow_downward_rounded)
                                                  : Icons.unfold_more_rounded,
                                              size: 12,
                                              color: isCurrentSort
                                                  ? Colors.blue
                                                  : (isDark
                                                      ? Colors.white38
                                                      : Colors.black26),
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2.0),
                                      child: headerContent,
                                    ),
                                  );
                                }

                                if (appConfig.freezeColumns) {
                                  final List<ColConfig> leftColumns = columns
                                      .where((col) =>
                                          col.title == '选' ||
                                          col.title == '#' ||
                                          col.title == '' ||
                                          col.title == '基金名称')
                                      .toList();
                                  final List<ColConfig> rightColumns = columns
                                      .where((col) =>
                                          col.title != '选' &&
                                          col.title != '#' &&
                                          col.title != '' &&
                                          col.title != '基金名称')
                                      .toList();
                                  final double leftTableWidth =
                                      leftColumns.isEmpty
                                          ? 0.0
                                          : leftColumns
                                              .map((c) => c.width)
                                              .reduce((a, b) => a + b);
                                  final double rightTableWidth =
                                      rightColumns.isEmpty
                                          ? 0.0
                                          : rightColumns
                                              .map((c) => c.width)
                                              .reduce((a, b) => a + b);

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Stack(
                                        children: [
                                          SizedBox(
                                            width: leftTableWidth + 1,
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? Colors.white
                                                            .withValues(
                                                                alpha: 0.06)
                                                        : Colors.black
                                                            .withValues(
                                                                alpha: 0.04),
                                                    border: Border(
                                                      bottom: BorderSide(
                                                          color: isDark
                                                              ? Colors.white10
                                                              : Colors.black12),
                                                      right: BorderSide(
                                                          color: isDark
                                                              ? Colors.white24
                                                              : Colors.black26,
                                                          width: 1),
                                                    ),
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  child: Row(
                                                    children: leftColumns
                                                        .map((col) =>
                                                            buildHeaderCell(
                                                                col))
                                                        .toList(),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RefreshIndicator(
                                                    onRefresh: () async {
                                                      await appConfig
                                                          .syncWithSupabase();
                                                      await fundProvider
                                                          .refreshAll(
                                                              isForce: true);
                                                    },
                                                    child: ListView.builder(
                                                      padding: EdgeInsets.zero,
                                                      itemExtent: 55.0,
                                                      controller:
                                                          _leftVerticalScrollController,
                                                      itemCount:
                                                          displayList.length,
                                                      itemBuilder:
                                                          (context, index) {
                                                        final model =
                                                            displayList[index];
                                                        return _buildRow(
                                                            context,
                                                            model,
                                                            index + 1,
                                                            leftColumns,
                                                            isDark,
                                                            appConfig,
                                                            fundProvider,
                                                            isLeftPart: true);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_horizontalOffset > 0)
                                            Positioned(
                                              top: 0,
                                              bottom: 0,
                                              right: 0,
                                              child: IgnorePointer(
                                                child: Container(
                                                  width: 6,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.black.withValues(
                                                            alpha: isDark
                                                                ? 0.35
                                                                : 0.15),
                                                        Colors.black.withValues(
                                                            alpha: 0.0),
                                                      ],
                                                      begin:
                                                          Alignment.centerLeft,
                                                      end:
                                                          Alignment.centerRight,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Expanded(
                                        child: fluent.Scrollbar(
                                          thumbVisibility: true,
                                          notificationPredicate: (n) =>
                                              n.metrics.axis == Axis.vertical,
                                          controller:
                                              _rightVerticalScrollController,
                                          child: fluent.Scrollbar(
                                            thumbVisibility: true,
                                            notificationPredicate: (n) =>
                                                n.metrics.axis == Axis.horizontal,
                                            controller:
                                                _horizontalScrollController,
                                            child: SingleChildScrollView(
                                              controller:
                                                  _horizontalScrollController,
                                              scrollDirection: Axis.horizontal,
                                              child: SizedBox(
                                                width: rightTableWidth,
                                                child: Column(
                                                  children: [
                                                    Container(
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: isDark
                                                            ? Colors.white
                                                                .withValues(
                                                                    alpha: 0.06)
                                                            : Colors.black
                                                                .withValues(
                                                                    alpha: 0.04),
                                                        border: Border(
                                                          bottom: BorderSide(
                                                              color: isDark
                                                                  ? Colors.white10
                                                                  : Colors
                                                                      .black12),
                                                        ),
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                      child: Row(
                                                        children: rightColumns
                                                            .map((col) =>
                                                                buildHeaderCell(
                                                                    col))
                                                            .toList(),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: RefreshIndicator(
                                                        onRefresh: () async {
                                                          await appConfig
                                                              .syncWithSupabase();
                                                          await fundProvider
                                                              .refreshAll(
                                                                  isForce:
                                                                      true);
                                                        },
                                                        child: ListView.builder(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          itemExtent: 55.0,
                                                          controller:
                                                              _rightVerticalScrollController,
                                                          physics:
                                                              const AlwaysScrollableScrollPhysics(
                                                                  parent:
                                                                      BouncingScrollPhysics()),
                                                          itemCount: displayList
                                                              .length,
                                                          itemBuilder:
                                                              (context, index) {
                                                            final model =
                                                                displayList[
                                                                    index];
                                                            return _buildRow(
                                                                context,
                                                                model,
                                                                index + 1,
                                                                rightColumns,
                                                                isDark,
                                                                appConfig,
                                                                fundProvider);
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
                                  );
                                } else {
                                  return fluent.Scrollbar(
                                    thumbVisibility: true,
                                    notificationPredicate: (n) =>
                                        n.metrics.axis == Axis.vertical,
                                    controller: _rightVerticalScrollController,
                                    child: fluent.Scrollbar(
                                      thumbVisibility: true,
                                      notificationPredicate: (n) =>
                                          n.metrics.axis == Axis.horizontal,
                                      controller: _horizontalScrollController,
                                      child: SingleChildScrollView(
                                        controller: _horizontalScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: totalTableWidth,
                                          child: Column(
                                            children: [
                                              Container(
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.white.withValues(
                                                          alpha: 0.06)
                                                      : Colors.black.withValues(
                                                          alpha: 0.04),
                                                  border: Border(
                                                    bottom: BorderSide(
                                                        color: isDark
                                                            ? Colors.white10
                                                            : Colors.black12),
                                                  ),
                                                ),
                                                padding: EdgeInsets.zero,
                                                child: Row(
                                                  children: columns
                                                      .map((col) =>
                                                          buildHeaderCell(col))
                                                      .toList(),
                                                ),
                                              ),
                                              Expanded(
                                                child: RefreshIndicator(
                                                  onRefresh: () async {
                                                    await appConfig
                                                        .syncWithSupabase();
                                                    await fundProvider
                                                        .refreshAll(
                                                            isForce: true);
                                                  },
                                                  child: ListView.builder(
                                                    padding: EdgeInsets.zero,
                                                    itemExtent: 55.0,
                                                    controller:
                                                        _rightVerticalScrollController,
                                                    physics:
                                                        const AlwaysScrollableScrollPhysics(
                                                            parent:
                                                                BouncingScrollPhysics()),
                                                    itemCount:
                                                        displayList.length,
                                                    itemBuilder:
                                                        (context, index) {
                                                      final model =
                                                          displayList[index];
                                                      return _buildRow(
                                                          context,
                                                          model,
                                                          index + 1,
                                                          columns,
                                                          isDark,
                                                          appConfig,
                                                          fundProvider);
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    FundUIModel model,
    int orderIndex,
    List<ColConfig> columns,
    bool isDark,
    AppConfig appConfig,
    FundProvider fundProvider, {
    bool isLeftPart = false,
  }) {
    final bool isBuySignal = model.isBuySignal;
    final bool isSellSignal = model.isSellSignal;
    final double currentDrop = model.currentDrop;
    final double currentRise = model.currentRise;

    // 优先触发了买入信号的行高亮显示（淡红色），其次触发了卖出信号的行高亮显示（淡绿色），再次置顶行高亮背景，普通行无背景
    final Color? rowBgColor = isBuySignal
        ? ThemeColors.getRedText(isDark).withValues(alpha: isDark ? 0.20 : 0.12)
        : (isSellSignal
            ? ThemeColors.getGreenText(isDark)
                .withValues(alpha: isDark ? 0.20 : 0.12)
            : (model.isPinned
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.yellow.withValues(alpha: 0.05))
                : null));

    final double change =
        model.isTodayValuation ? (double.tryParse(model.gszzl) ?? 0.0) : 0.0;
    final Color changeColor = model.isTodayValuation
        ? (change > 0
            ? ThemeColors.getRedText(isDark)
            : (change < 0
                ? ThemeColors.getGreenText(isDark)
                : ThemeColors.getNormalText(isDark)))
        : ThemeColors.getNormalText(isDark);

    // 计算今日实际盈亏
    double todayProfit = 0.0;
    if (model.isHeld && model.amount > 0) {
      todayProfit = (model.amount * change) / 100.0;
    }

    // 提取长按/右键回调，传递给 CopyableText 确保手势统一处理
    void longPressCallback(LongPressStartDetails details) {
      _showContextMenu(
          context, details.globalPosition, model, appConfig, fundProvider);
    }

    void secondaryTapCallback(TapDownDetails details) {
      _showContextMenu(
          context, details.globalPosition, model, appConfig, fundProvider);
    }

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: secondaryTapCallback,
        onLongPressStart: longPressCallback,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          color: rowBgColor,
          border: Border(
            bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
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
          children: columns.map((col) {
            Widget cellContent = const SizedBox.shrink();
            final cleanTitle = col.title.replaceAll('\n', '');

            switch (cleanTitle) {
              case '选':
                final bool isChecked = _selectedCodes.contains(model.code);
                cellContent = Align(
                  alignment: Alignment.center,
                  child: ScaledCheckbox(
                    checked: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedCodes.add(model.code);
                        } else {
                          _selectedCodes.remove(model.code);
                        }
                      });
                    },
                  ),
                );
                break;
              case '#':
              case '':
                cellContent = Text(
                  model.isPinned ? '📌' : orderIndex.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                );
                break;
              case '代码':
                cellContent = CopyableText(
                  model.code,
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
                        model.name,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        onLongPressStart: longPressCallback,
                        onSecondaryTapDown: secondaryTapCallback,
                      ),
                    ),
                    if (model.errorMsg != null) ...[
                      const SizedBox(width: 4),
                      fluent.Tooltip(
                        message: model.errorMsg!,
                        useMousePosition: true,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: ThemeColors.getRedText(isDark),
                          size: 14,
                        ),
                      ),
                    ],
                    if (model.isHeld) ...[
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
                cellContent = fluent.Tooltip(
                  message: '双击编辑板块分类',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () =>
                          _editFundSector(context, model, appConfig),
                      child: Text(
                        model.sector,
                        textAlign: TextAlign.left,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                );
                break;
              case '买入信号':
                if (model.optimalStrategy != null) {
                  final s = model.optimalStrategy!;
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
                        model.getRecentBuyTriggerIndex(maxDays: 3);
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
                                color: isDark ? Colors.white60 : Colors.black54,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                border:
                                    Border.all(color: badgeBorder, width: 0.8),
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
                    optimalStrategy: model.optimalStrategy,
                  );
                }
                break;
              case '卖出信号':
                if (model.optimalStrategy != null &&
                    model.optimalStrategy!['sell_x'] != null) {
                  final s = model.optimalStrategy!;
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
                    optimalStrategy: model.optimalStrategy,
                  );
                }
                break;
              case '昨日':
                final yestChange = double.tryParse(model.yestZdf) ?? 0.0;
                final yestColor = yestChange > 0
                    ? ThemeColors.getRedText(isDark)
                    : (yestChange < 0
                        ? ThemeColors.getGreenText(isDark)
                        : ThemeColors.getNormalText(isDark));
                cellContent = Text(
                  '${yestChange > 0 ? '+' : ''}${model.yestZdf}%',
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
                cellContent = fluent.Tooltip(
                  message: '双击编辑持仓信息',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () =>
                          _editHoldingInfo(context, model, appConfig),
                      child: Text(
                        model.isHeld && model.amount > 0
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
                  ),
                );
                break;
              case '趋势':
                cellContent = fluent.Tooltip(
                  message: '双击查看趋势图',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () {
                        fluent.showDialog(
                          context: context,
                          builder: (context) => FundChartDialog(
                            fundCode: model.code,
                            fundName: model.name,
                            navs: model.navs,
                            dates: model.dates,
                            todayEstimateNav: double.tryParse(model.gsz),
                            todayEstimatePct: double.tryParse(model.gszzl),
                            todayEstimateTime: model.gztime,
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4.0, horizontal: 2.0),
                          child: Sparkline(data: model.navs),
                        ),
                      ),
                    ),
                  ),
                );
                break;
              case '数据源':
                cellContent = Text(
                  model.source.isEmpty ? '-' : model.source,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                );
                break;
              case '估值时间':
                String timeStr = model.gztime;
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
                    // 🤖 一键跳转策略中心回测
                    fluent.Tooltip(
                      message: '跳转策略回测',
                      child: fluent.IconButton(
                        icon: const Icon(Icons.psychology_rounded,
                            size: 16, color: Colors.purpleAccent),
                        onPressed: () {
                          fundProvider.switchToBacktest(model.code);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 更多操作
                    Builder(builder: (buttonContext) {
                      return fluent.Tooltip(
                        message: '更多操作',
                        child: fluent.IconButton(
                          icon: const Icon(Icons.more_vert_rounded,
                              size: 16, color: Colors.grey),
                          onPressed: () {
                            final RenderBox? renderBox =
                                buttonContext.findRenderObject() as RenderBox?;
                            if (renderBox != null) {
                              final offset =
                                  renderBox.localToGlobal(Offset.zero);
                              final menuOffset = Offset(
                                offset.dx + renderBox.size.width / 2,
                                offset.dy + renderBox.size.height / 2,
                              );
                              _showContextMenu(context, menuOffset, model,
                                  appConfig, fundProvider);
                            }
                          },
                        ),
                      );
                    }),
                  ],
                );
                break;
              default:
                // 动态天数跌幅列判定
                if (cleanTitle.startsWith('近') && cleanTitle.endsWith('日涨跌')) {
                  final dayStr =
                      cleanTitle.replaceAll('近', '').replaceAll('日涨跌', '');
                  final int d = int.tryParse(dayStr) ?? 0;
                  final val = model.drops[d] ?? 0.0;
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
                }
                // 动态月份百分位列判定
                else if (cleanTitle.startsWith('近') &&
                    cleanTitle.endsWith('月百分位')) {
                  final monthStr =
                      cleanTitle.replaceAll('近', '').replaceAll('月百分位', '');
                  final int m = int.tryParse(monthStr) ?? 0;
                  final val = model.pcts[m] ?? -1.0;

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
    ),
    );
  }
}
