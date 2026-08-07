import 'dart:math' as math;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../widgets/scaled_checkbox.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/fund_provider.dart';
import '../../core/utils/theme_colors.dart';
import '../../core/utils/safe_compute.dart';
import '../../core/backtest_engine.dart';
import '../../core/ga_optimizer.dart';
import '../widgets/copyable_text.dart';
import '../../core/db_manager.dart';
import '../../core/config.dart';
import '../../core/data_gateway.dart';
import '../widgets/mobile_header.dart';

Map<String, dynamic> getDefaultStrategyFilters(String name, String sector) {
  double defaultRsi = 35.0;
  bool defaultMacd = true;
  double defaultPe = 40.0;
  double defaultPb = 40.0;

  final bool isLow = name.contains('债') ||
      name.contains('固收') ||
      name.contains('货币') ||
      name.contains('理财') ||
      name.contains('存单') ||
      sector.contains('债') ||
      sector.contains('货币') ||
      sector.contains('固收');
  final bool isHigh = name.contains('科技') ||
      name.contains('半导体') ||
      name.contains('芯片') ||
      name.contains('医药') ||
      name.contains('医疗') ||
      name.contains('白酒') ||
      name.contains('消费') ||
      name.contains('新能源') ||
      name.contains('科创') ||
      name.contains('创业') ||
      name.contains('军工') ||
      name.contains('光伏') ||
      name.contains('黄金') ||
      name.contains('白银') ||
      name.contains('纳斯达克') ||
      name.contains('标普') ||
      name.contains('恒生科技') ||
      name.contains('软件') ||
      name.contains('成长') ||
      name.contains('QDII') ||
      name.contains('证券') ||
      name.contains('券商') ||
      sector.contains('科技') ||
      sector.contains('医药') ||
      sector.contains('医疗') ||
      sector.contains('消费') ||
      sector.contains('新能源') ||
      sector.contains('军工') ||
      sector.contains('半导体');

  if (isLow) {
    defaultRsi = 30.0;
    defaultPe = 30.0;
    defaultPb = 30.0;
  } else if (isHigh) {
    defaultRsi = 40.0;
    defaultPe = 50.0;
    defaultPb = 50.0;
  }

  return {
    'rsi': defaultRsi,
    'macd': defaultMacd,
    'pe': defaultPe,
    'pb': defaultPb,
  };
}

enum OptMode {
  single,
  batch,
}

class BatchOptResult {
  final String code;
  final String name;
  final String sector;
  String status; // '等待中', '计算中', '成功', '无历史数据', '未发现交易', '计算出错'
  double? winRate;
  int? buyDays;
  double? buyDrop;
  double? targetProfit;
  double? avgProfit;
  int? totalTrades;
  String? dataDuration;
  int? dataDurationDays;
  int? sellX;
  double? sellWinRate;
  int? sellTrades;

  BatchOptResult({
    required this.code,
    required this.name,
    required this.sector,
    this.status = '等待中',
    this.winRate,
    this.buyDays,
    this.buyDrop,
    this.targetProfit,
    this.avgProfit,
    this.totalTrades,
    this.dataDuration,
    this.dataDurationDays,
    this.sellX,
    this.sellWinRate,
    this.sellTrades,
  });
}

class StrategyCenterTab extends StatefulWidget {
  const StrategyCenterTab({super.key});

  @override
  State<StrategyCenterTab> createState() => _StrategyCenterTabState();
}

class _StrategyCenterTabState extends State<StrategyCenterTab> {
  String? _selectedCode;
  bool _isOptimizing = false;
  bool _isRecalibrating = false;

  // 回测控制参数
  int _buyDays = 5;
  double _buyDrop = 2.0;
  double _targetProfit = 3.0;
  double _rsiFilterLimit = 35.0;
  bool _useMacdFilter = true;
  double _pePercentileLimit = 30.0;
  double _pbPercentileLimit = 30.0;
  double _slippagePct = 0.2;

  // 寻优/回测结果
  BacktestResult? _backtestResult;

  // 批量寻优相关状态
  OptMode _optMode = OptMode.single;
  final Set<String> _selectedTabs = {};
  bool _isBatchOptimizing = false;
  String _batchProgress = '';
  List<BatchOptResult> _batchResults = [];
  final ScrollController _batchHorizontalScrollController = ScrollController();
  final ScrollController _batchVerticalScrollController = ScrollController();
  String _sortColumn = '';
  bool _sortAscending = true;

  // 单只基金寻优结果
  BatchOptResult? _singleOptResult;
  final ScrollController _singleHorizontalScrollController = ScrollController();
  final TextEditingController _fundSearchController = TextEditingController();
  String? _lastSyncedCode;

  Future<void> _recalibrateThresholds(AppConfig appConfig) async {
    setState(() {
      _isRecalibrating = true;
    });

    // 让出主线程控制权，确保 Flutter 优先渲染界面并将按钮转换为加载状态
    await Future.delayed(Duration.zero);

    try {
      final result = await appConfig.recalibrateVolatilityThresholds();
      final int count = result['count'] as int;
      final double low = result['low'] as double;
      final double high = result['high'] as double;

      if (!mounted) return;

      fluent.showDialog(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('校准完成'),
          content: Text(
              '已成功扫描 $count 只基金的历史净值！\n最新低波动分界线：${low.toThousand(precision: 2)}\n最新高波动分界线：${high.toThousand(precision: 2)}\n\n新标准已自动写入本地并实时生效。'),
          actions: [
            fluent.FilledButton(
              child: const Text('确认'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      fluent.showDialog(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('校准失败'),
          content: Text('错误原因: $e'),
          actions: [
            fluent.FilledButton(
              child: const Text('确认'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRecalibrating = false;
        });
      }
    }
  }

  Map<String, dynamic>? _decodeSellParams(int? encodedVal) {
    if (encodedVal == null || encodedVal <= 0) return null;
    if (encodedVal < 100) {
      return {
        'sellX': encodedVal,
        'sellPct': encodedVal.toDouble(),
      };
    } else {
      return {
        'sellX': encodedVal ~/ 1000,
        'sellPct': (encodedVal % 1000).toDouble(),
      };
    }
  }

  List<double> _chartNavs = [];
  List<String> _chartDates = [];
  List<FlSpot> _cachedChartSpots = [];
  List<FlSpot> _cachedBuySpots = [];
  List<FlSpot> _cachedSellSpots = [];

  @override
  void dispose() {
    _isBatchOptimizing = false;
    _batchHorizontalScrollController.dispose();
    _batchVerticalScrollController.dispose();
    _singleHorizontalScrollController.dispose();
    _fundSearchController.dispose();
    super.dispose();
  }

  Widget _buildStrategyIntroCard(bool isDark, {bool embedded = false}) {
    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? Colors.white70 : Colors.black54;
    final accentColor = fluent.FluentTheme.of(context).accentColor;

    final cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!embedded) ...[
          Row(
            children: [
              Icon(fluent.FluentIcons.insights, color: accentColor, size: 24),
              const SizedBox(width: 10),
              Text(
                '智能参数寻优与回测策略说明',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '本系统专为基金产品设计，通过对历史净值波动规律进行数理建模，自动挖掘适合每只基金的个性化网格买卖参数，辅助科学决策。',
            style: TextStyle(fontSize: 12, color: descColor, height: 1.4),
          ),
          const SizedBox(height: 12),
          const fluent.Divider(),
          const SizedBox(height: 12),
        ],
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final isTwoColumn = width > 520;

              Widget buildFeatureItem({
                required IconData icon,
                required String title,
                required List<String> bulletPoints,
                required Color iconBgColor,
              }) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.white,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 7),
                      ...bulletPoints.map((point) => Padding(
                            padding: const EdgeInsets.only(bottom: 5.0),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.only(
                                      top: 5, right: 7),
                                  decoration: BoxDecoration(
                                    color: iconBgColor.withValues(
                                        alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    point,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: descColor,
                                        height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                );
              }

              final List<Widget> featureItems = [
                buildFeatureItem(
                  icon: fluent.FluentIcons.git_graph,
                  title: '🧬 遗传算法参数寻优 (GA)',
                  iconBgColor: Colors.blue,
                  bulletPoints: [
                    '智能演化：在几千组买入天数、下跌阈值和止盈目标的参数组合中进行遗传迭代。',
                    '个性定制：针对不同波动率的基金自动生成适配的网格，高波动高宽幅，低波动低门槛。',
                  ],
                ),
                buildFeatureItem(
                  icon: fluent.FluentIcons.shield_alert,
                  title: '🛡️ 趋势风控与均线过滤器',
                  iconBgColor: Colors.orange,
                  bulletPoints: [
                    '均线过滤：引入动态自适应均线（默认120日），处于下行空头趋势时自动减少买入，规避无底深渊。',
                    '移动止损：在达到止盈点后开启追踪止损，锁定高位利润，防止坐“过山车”。',
                    'RSI/MACD 双重过滤：结合 RSI 超卖区间与 MACD 金叉信号，过滤下跌途中的假低点。',
                  ],
                ),
                buildFeatureItem(
                  icon: fluent.FluentIcons.sign_out,
                  title: '🚪 卖出信号二次寻优',
                  iconBgColor: Colors.redAccent,
                  bulletPoints: [
                    '出场优化：寻找除了固定止盈外的最优卖出时间，在“X天内涨幅达P%”的维度智能平仓。',
                    '回撤控制：控制最长持仓周期，平衡资金占用时间与网格循环效率。',
                  ],
                ),
                buildFeatureItem(
                  icon: fluent.FluentIcons.lock,
                  title: '🔒 模拟盘风控体系',
                  iconBgColor: Colors.teal,
                  bulletPoints: [
                    '四重平仓保护：固定止损(-15%) + 目标止盈 + 到期平仓 + 卖出信号，与回测引擎逻辑完全对齐。',
                    '网格加仓：持仓基金继续下跌时自动追加买入摊低成本（最多3次），配合步进间距降噪过滤。',
                    '仓位管控：全局最大持仓25只 + 单日最多买入5笔 + 同日买卖互斥，防止集中建仓和无效交易。',
                  ],
                ),
                buildFeatureItem(
                  icon: fluent.FluentIcons.database_activity,
                  title: '💻 异步并发与本地策略库',
                  iconBgColor: Colors.purple,
                  bulletPoints: [
                    '后台计算：在后台独立 Isolate 线程中并发寻优，完全避免界面卡顿。',
                    '无缝同步：寻优成功后自动写入本地 SQLite 策略数据库，与主面板的日度信号监控无缝连接。',
                  ],
                ),
              ];

              // 等高行布局：同行两卡强制等宽等高，奇数末尾卡片横跨整行，保证排版整齐
              final List<Widget> rows = [];
              if (isTwoColumn) {
                for (int i = 0; i < featureItems.length; i += 2) {
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
                  if (i + 1 < featureItems.length) {
                    rows.add(IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: featureItems[i]),
                          const SizedBox(width: 16),
                          Expanded(child: featureItems[i + 1]),
                        ],
                      ),
                    ));
                  } else {
                    rows.add(featureItems[i]);
                  }
                }
              } else {
                for (int i = 0; i < featureItems.length; i++) {
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
                  rows.add(featureItems[i]);
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              );
            },
          ),
        ),
        if (!embedded) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(fluent.FluentIcons.info, color: accentColor, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 使用方法：在左侧面板选择单只或批量模式，点击按钮即可开始计算。计算完成后此区域将切换为详细回测图表及报表。',
                    style: TextStyle(
                        fontSize: 11,
                        color: accentColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (embedded) {
      return cardContent;
    }

    return fluent.Card(
      padding: const EdgeInsets.all(18.0),
      child: cardContent,
    );
  }

  void _initSingleOptResult() {
    if (_selectedCode == null) {
      _singleOptResult = null;
      return;
    }
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final fund = fundProvider.myFunds[_selectedCode];
    if (fund != null) {
      _singleOptResult = BatchOptResult(
        code: fund.code,
        name: fund.name,
        sector: fund.sector,
        status: '等待中',
      );
      _loadSingleDuration();
    } else {
      _singleOptResult = null;
    }
  }

  Future<void> _loadSingleDuration() async {
    if (_selectedCode == null || _singleOptResult == null) return;
    final String targetCode = _selectedCode!;
    final proxyCode = AppConfig.indexProxyMap[targetCode] ?? targetCode;
    var history = await FundHistoryDB().getHistory(proxyCode);
    if (history == null || history['navs'] == null) {
      final onlineHis = await FundDataGateway().fetchEtfHistory(proxyCode);
      if (onlineHis != null) {
        final List<double> navs = List<double>.from(onlineHis['navs'] ?? []);
        final List<String> dates = List<String>.from(onlineHis['dates'] ?? []);
        await FundHistoryDB()
            .saveHistory(proxyCode, onlineHis['jzrq'], navs, dates);
        history = await FundHistoryDB().getHistory(proxyCode);
      }
    }
    if (!mounted || _selectedCode != targetCode) return;
    if (history == null || history['navs'] == null) {
      setState(() {
        if (_singleOptResult?.code == targetCode) {
          _singleOptResult?.status = '无历史数据';
          _singleOptResult?.dataDuration = '--';
          _singleOptResult?.dataDurationDays = 0;
          _chartNavs = [];
        }
      });
      return;
    }
    final List<String> dates =
        List<String>.from(history['dates'] ?? []).reversed.toList();
    final List<double> navs =
        List<double>.from(history['navs'] ?? []).reversed.toList();
    String durationStr = '--';
    int durationDays = dates.length;
    if (dates.isNotEmpty) {
      final firstDate = DateTime.tryParse(dates.first);
      final lastDate = DateTime.tryParse(dates.last);
      if (firstDate != null && lastDate != null) {
        final years = lastDate.difference(firstDate).inDays / 365.0;
        durationStr = "${years.toThousand(precision: 1)}年 (${dates.length}天)";
      } else {
        durationStr = "${dates.length}天";
      }
    }
    final optStrategy = await FundHistoryDB().getOptimalStrategy(targetCode);
    if (!mounted || _selectedCode != targetCode) return;
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final fund = fundProvider.myFunds[targetCode];

    double defaultRsi = 35.0;
    bool defaultMacd = true;
    double defaultPe = 40.0;
    double defaultPb = 40.0;

    if (fund != null) {
      final defaults = getDefaultStrategyFilters(fund.name, fund.sector);
      defaultRsi = defaults['rsi'];
      defaultMacd = defaults['macd'];
      defaultPe = defaults['pe'];
      defaultPb = defaults['pb'];
    }

    setState(() {
      if (_singleOptResult?.code == targetCode) {
        _singleOptResult?.dataDuration = durationStr;
        _singleOptResult?.dataDurationDays = durationDays;
        _chartNavs = navs;
        _chartDates = dates;
        if (optStrategy != null) {
          _buyDays = (optStrategy['buy_days'] ?? 5).clamp(5, 60);
          _buyDrop = (optStrategy['buy_drop'] ?? 2.0).clamp(0.5, 25.0);
          _targetProfit =
              (optStrategy['target_profit'] ?? 3.0).clamp(0.5, 25.0);
          _rsiFilterLimit =
              ((optStrategy['rsi_filter_limit'] ?? defaultRsi) as num)
                  .toDouble()
                  .clamp(0.0, 80.0);
          _useMacdFilter = (optStrategy['macd_filter_enabled'] ?? 1) == 1;
          _pePercentileLimit =
              ((optStrategy['pe_percentile_limit'] ?? defaultPe) as num)
                  .toDouble()
                  .clamp(0.0, 95.0);
          _pbPercentileLimit =
              ((optStrategy['pb_percentile_limit'] ?? defaultPb) as num)
                  .toDouble()
                  .clamp(0.0, 95.0);
        } else {
          _buyDays = 5;
          _buyDrop = 2.0;
          _targetProfit = 3.0;
          _rsiFilterLimit = defaultRsi;
          _useMacdFilter = defaultMacd;
          _pePercentileLimit = defaultPe;
          _pbPercentileLimit = defaultPb;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundProvider = Provider.of<FundProvider>(context);
    final appConfig = Provider.of<AppConfig>(context);
    final List<FundUIModel> list = fundProvider.myFunds.values.toList();
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    // 检查是否有快捷跳转的回测基金代码
    if (fundProvider.selectedBacktestCode != null) {
      final code = fundProvider.selectedBacktestCode!;
      // 必须在自选列表里有该产品才选中；寻优进行中禁止切换，防止异步结果归属到错误基金
      if (!_isOptimizing &&
          !_isBatchOptimizing &&
          list.any((f) => f.code == code)) {
        _selectedCode = code;
        _optMode = OptMode.single; // 强制切换回单只模式进行回测
        _backtestResult = null; // 清空旧回测结果，避免展示上一只基金的图表与指标
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        fundProvider.clearSelectedBacktestCode();
      });
    }

    // 若当前选中的基金已被删除，重置选中状态
    if (_selectedCode != null && !list.any((f) => f.code == _selectedCode)) {
      _selectedCode = null;
      _singleOptResult = null;
      _backtestResult = null;
      _lastSyncedCode = null;
    }

    if (_selectedCode == null && list.isNotEmpty) {
      _selectedCode = list.first.code;
    }

    // 当 _selectedCode 变化时，同步搜索框的显示文本
    if (_selectedCode != null && _selectedCode != _lastSyncedCode) {
      final matchedFund = list.firstWhere(
        (f) => f.code == _selectedCode,
        orElse: () => list.first,
      );
      _fundSearchController.text = '${matchedFund.code} - ${matchedFund.name}';
      _lastSyncedCode = _selectedCode;
    }

    if (_selectedCode != null &&
        (_singleOptResult == null || _singleOptResult!.code != _selectedCode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _initSingleOptResult();
          });
        }
      });
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    final Widget controlPanel = fluent.Card(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎯 寻优模式选择',
                  style: TextStyle(
                      fontWeight: fluent.FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              RadioGroup<OptMode>(
                groupValue: _optMode,
                onChanged: (v) {
                  if (v != null && !_isOptimizing && !_isBatchOptimizing) {
                    setState(() => _optMode = v);
                  }
                },
                child: Row(
                  children: [
                    fluent.RadioButton<OptMode>(
                      value: OptMode.single,
                      content: const Text('单只基金'),
                      enabled: !_isOptimizing && !_isBatchOptimizing,
                    ),
                    const SizedBox(width: 20),
                    fluent.RadioButton<OptMode>(
                      value: OptMode.batch,
                      content: const Text('板块批量'),
                      enabled: !_isOptimizing && !_isBatchOptimizing,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const fluent.Divider(),
              const SizedBox(height: 15),

              // 根据模式展示不同左面板
              if (_optMode == OptMode.single) ...[
                const Text('📊 选择基金产品',
                    style: TextStyle(
                        fontWeight: fluent.FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('输入代码或名称关键字快速筛选',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600])),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: fluent.AutoSuggestBox<String>(
                    controller: _fundSearchController,
                    placeholder: '搜索基金代码 / 名称...',
                    items: list.map((fund) {
                      final label = '${fund.code} - ${fund.name}';
                      return fluent.AutoSuggestBoxItem<String>(
                        value: fund.code,
                        label: label,
                        onSelected: () {
                          if (_isOptimizing || _isBatchOptimizing) return;
                          setState(() {
                            _selectedCode = fund.code;
                            _lastSyncedCode = fund.code;
                            _fundSearchController.text = label;
                            _backtestResult = null;
                            _initSingleOptResult();
                          });
                        },
                        child: fluent.Tooltip(
                          message: label,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (text, reason) {
                      // 当用户清空搜索框时，不改变选中状态（保持当前选中的基金）
                    },
                    noResultsFoundBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('未找到匹配的基金', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                const Text('⚙️ 策略回测参数',
                    style: TextStyle(
                        fontWeight: fluent.FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 15),
                Text('回看最高净值天数: $_buyDays 天'),
                fluent.Slider(
                  value: _buyDays.toDouble().clamp(5.0, 60.0),
                  min: 5,
                  max: 60,
                  onChanged: _isOptimizing || _isBatchOptimizing
                      ? null
                      : (v) {
                          setState(() => _buyDays = v.toInt());
                        },
                ),
                const SizedBox(height: 15),
                Text('买入下跌触发阈值: ${_buyDrop.toThousand(precision: 1)}%'),
                fluent.Slider(
                  value: _buyDrop.clamp(0.5, 25.0),
                  min: 0.5,
                  max: 25.0,
                  onChanged: _isOptimizing || _isBatchOptimizing
                      ? null
                      : (v) {
                          setState(() => _buyDrop = v);
                        },
                ),
                const SizedBox(height: 15),
                Text('止盈卖出目标年化: ${_targetProfit.toThousand(precision: 1)}%'),
                fluent.Slider(
                  value: _targetProfit.clamp(0.5, 25.0),
                  min: 0.5,
                  max: 25.0,
                  onChanged: _isOptimizing || _isBatchOptimizing
                      ? null
                      : (v) {
                          setState(() => _targetProfit = v);
                        },
                ),
                const SizedBox(height: 15),
                Text('成交滑点比例: ${_slippagePct.toThousand(precision: 2)}%'),
                fluent.Slider(
                  value: _slippagePct.clamp(0.0, 2.0),
                  min: 0.0,
                  max: 2.0,
                  onChanged: _isOptimizing || _isBatchOptimizing
                      ? null
                      : (v) {
                          setState(() => _slippagePct = v);
                        },
                ),
                const SizedBox(height: 15),
                // === RSI 过滤 ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'RSI 过滤上限: ${_rsiFilterLimit > 0 ? _rsiFilterLimit.toThousand(precision: 0) : "已关闭"}',
                        style: const TextStyle(fontSize: 13)),
                    fluent.ToggleSwitch(
                      checked: _rsiFilterLimit > 0,
                      onChanged: _isOptimizing || _isBatchOptimizing
                          ? null
                          : (v) {
                              setState(() {
                                _rsiFilterLimit = v ? 35.0 : 0.0;
                              });
                            },
                    ),
                  ],
                ),
                if (_rsiFilterLimit > 0) ...[
                  const SizedBox(height: 5),
                  fluent.Slider(
                    value: _rsiFilterLimit.clamp(10.0, 80.0),
                    min: 10,
                    max: 80,
                    onChanged: _isOptimizing || _isBatchOptimizing
                        ? null
                        : (v) {
                            setState(() => _rsiFilterLimit = v);
                          },
                  ),
                ],
                const SizedBox(height: 15),
                // === MACD 过滤 ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('MACD 金叉过滤(仅金叉/红柱买入)',
                        style: TextStyle(fontSize: 13)),
                    fluent.ToggleSwitch(
                      checked: _useMacdFilter,
                      onChanged: _isOptimizing || _isBatchOptimizing
                          ? null
                          : (v) {
                              setState(() {
                                _useMacdFilter = v;
                              });
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                // === PE 百分位过滤 ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'PE 百分位上限: ${_pePercentileLimit > 0 ? "${_pePercentileLimit.toThousand(precision: 0)}%" : "已关闭"}',
                        style: const TextStyle(fontSize: 13)),
                    fluent.ToggleSwitch(
                      checked: _pePercentileLimit > 0,
                      onChanged: _isOptimizing || _isBatchOptimizing
                          ? null
                          : (v) {
                              setState(() {
                                _pePercentileLimit = v ? 30.0 : 0.0;
                              });
                            },
                    ),
                  ],
                ),
                if (_pePercentileLimit > 0) ...[
                  const SizedBox(height: 5),
                  fluent.Slider(
                    value: _pePercentileLimit.clamp(5.0, 95.0),
                    min: 5,
                    max: 95,
                    onChanged: _isOptimizing || _isBatchOptimizing
                        ? null
                        : (v) {
                            setState(() => _pePercentileLimit = v);
                          },
                  ),
                ],
                const SizedBox(height: 15),
                // === PB 百分位过滤 ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'PB 百分位上限: ${_pbPercentileLimit > 0 ? "${_pbPercentileLimit.toThousand(precision: 0)}%" : "已关闭"}',
                        style: const TextStyle(fontSize: 13)),
                    fluent.ToggleSwitch(
                      checked: _pbPercentileLimit > 0,
                      onChanged: _isOptimizing || _isBatchOptimizing
                          ? null
                          : (v) {
                              setState(() {
                                _pbPercentileLimit = v ? 30.0 : 0.0;
                              });
                            },
                    ),
                  ],
                ),
                if (_pbPercentileLimit > 0) ...[
                  const SizedBox(height: 5),
                  fluent.Slider(
                    value: _pbPercentileLimit.clamp(5.0, 95.0),
                    min: 5,
                    max: 95,
                    onChanged: _isOptimizing || _isBatchOptimizing
                        ? null
                        : (v) {
                            setState(() => _pbPercentileLimit = v);
                          },
                  ),
                ],
                const SizedBox(height: 30),
                // 控制按钮
                Row(
                  children: [
                    Expanded(
                      child: fluent.Button(
                        onPressed: _isOptimizing || _isBatchOptimizing
                            ? null
                            : () => _runSingleBacktest(),
                        child: const Text('运行单次回测'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: fluent.FilledButton(
                        onPressed: _isOptimizing || _isBatchOptimizing
                            ? null
                            : () => _runGeneticOptimization(),
                        child: _isOptimizing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: fluent.ProgressRing())
                            : const Text('遗传算法寻优'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Text('📂 选择寻优 Tab 来源',
                    style: TextStyle(
                        fontWeight: fluent.FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    fluent.HyperlinkButton(
                      onPressed: _isBatchOptimizing
                          ? null
                          : () {
                              setState(() {
                                _selectedTabs.addAll(const [
                                  'holding',
                                  'my_funds',
                                  'special',
                                  'valuation',
                                  'top_ranking',
                                  'bot_ranking'
                                ]);
                              });
                            },
                      child: const Text('全选', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    fluent.HyperlinkButton(
                      onPressed: _isBatchOptimizing
                          ? null
                          : () {
                              setState(() {
                                _selectedTabs.clear();
                              });
                            },
                      child: const Text('清空', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 12.0,
                      runSpacing: 8.0,
                      children: [
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('holding'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('holding');
                                    } else {
                                      _selectedTabs.remove('holding');
                                    }
                                  });
                                },
                          content: const Text('持有基金',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('my_funds'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('my_funds');
                                    } else {
                                      _selectedTabs.remove('my_funds');
                                    }
                                  });
                                },
                          content: const Text('我的自选基金',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('special'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('special');
                                    } else {
                                      _selectedTabs.remove('special');
                                    }
                                  });
                                },
                          content: const Text('特别关注基金',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('valuation'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('valuation');
                                    } else {
                                      _selectedTabs.remove('valuation');
                                    }
                                  });
                                },
                          content: const Text('估值雷达关联',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('top_ranking'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('top_ranking');
                                    } else {
                                      _selectedTabs.remove('top_ranking');
                                    }
                                  });
                                },
                          content: const Text('今日领涨板块',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ScaledCheckbox(
                          checked: _selectedTabs.contains('bot_ranking'),
                          onChanged: _isBatchOptimizing
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedTabs.add('bot_ranking');
                                    } else {
                                      _selectedTabs.remove('bot_ranking');
                                    }
                                  });
                                },
                          content: const Text('今日领跌板块',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: fluent.FilledButton(
                    onPressed: _isBatchOptimizing || _selectedTabs.isEmpty
                        ? null
                        : () => _runBatchGeneticOptimization(),
                    child: _isBatchOptimizing
                        ? const SizedBox(
                            width: 14, height: 14, child: fluent.ProgressRing())
                        : const Text('开始批量寻优'),
                  ),
                ),
                const SizedBox(height: 16),
                const fluent.Divider(),
                const SizedBox(height: 12),
                // 波动率等级划分标准设置与手动校准入口
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📊 波动率划分标准 (当前百分位)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '低波动 < ${appConfig.volatilityLowThreshold.toThousand(precision: 1)}  |  高波动 >= ${appConfig.volatilityHighThreshold.toThousand(precision: 1)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '更新时间: ${appConfig.volatilityUpdateTime != null ? appConfig.volatilityUpdateTime!.toString().split('.')[0] : '暂无 (请点击动态校准)'}',
                            style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    fluent.Button(
                      onPressed: _isRecalibrating
                          ? null
                          : () => _recalibrateThresholds(appConfig),
                      child: _isRecalibrating
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: fluent.ProgressRing(strokeWidth: 2))
                          : const Text('动态校准'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final Widget reportArea = _optMode == OptMode.single
        ? (_backtestResult == null
            ? _buildStrategyIntroCard(isDark)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 寻优与回测指标表格
                  if (_singleOptResult != null) _buildSingleReportTable(isDark),
                  _buildRiskMetricsCards(isDark),
                  const SizedBox(height: 16),
                  // 图表区
                  isSmallScreen
                      ? SizedBox(
                          height: 300,
                          child: fluent.Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: _buildChartContent(isDark),
                            ),
                          ),
                        )
                      : Expanded(
                          child: fluent.Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: _buildChartContent(isDark),
                            ),
                          ),
                        ),
                ],
              ))
        : _buildBatchReportArea(isDark, fundProvider);

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSmallScreen) const MobileHeader(title: '策略中心'),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('暂无自选基金，请先添加自选基金。',
                        style: TextStyle(color: Colors.grey)))
                : Padding(
                    padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: isSmallScreen ? 0.0 : 16.0,
                        bottom: 16.0),
                    child: isSmallScreen
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                controlPanel,
                                const SizedBox(height: 16),
                                reportArea,
                              ],
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 左侧控制面板
                              Expanded(
                                flex: 1,
                                child: controlPanel,
                              ),
                              const SizedBox(width: 16),
                              // 右侧回测/寻优报告区
                              Expanded(
                                flex: 2,
                                child: reportArea,
                              ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📈 历史回测买卖信号散点分布',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 25),
        Expanded(
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) =>
                      Colors.blueGrey.withValues(alpha: 0.85),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((touchedSpot) {
                      String label = '净值';
                      Color textColor = Colors.white;
                      if (touchedSpot.barIndex == 1) {
                        label = '买入点';
                        textColor = ThemeColors.getRedText(isDark);
                      } else if (touchedSpot.barIndex == 2) {
                        label = '卖出点';
                        textColor = ThemeColors.getGreenText(isDark);
                      }

                      final int idx = touchedSpot.x.toInt();
                      String dateStr = '';
                      if (touchedSpot.barIndex == 0 &&
                          idx >= 0 &&
                          idx < _chartDates.length) {
                        dateStr = '${_chartDates[idx]}\n';
                      }

                      return LineTooltipItem(
                        '$dateStr$label: ${touchedSpot.y.toThousand(precision: 4)}',
                        TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                // 基金净值线
                LineChartBarData(
                  spots: _getChartSpots(),
                  isCurved: false,
                  color: Colors.blue.withValues(alpha: 0.65),
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                ),
                // 买点信号
                if (_backtestResult != null)
                  LineChartBarData(
                    spots: _getBuySpots(),
                    show: true,
                    color: ThemeColors.getRedText(isDark),
                    barWidth: 0,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: ThemeColors.getRedText(isDark),
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      ),
                    ),
                  ),
                // 卖点信号
                if (_backtestResult != null)
                  LineChartBarData(
                    spots: _getSellSpots(),
                    show: true,
                    color: ThemeColors.getGreenText(isDark),
                    barWidth: 0,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: ThemeColors.getGreenText(isDark),
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildChartLegend(Colors.blue, '基金净值线'),
            const SizedBox(width: 15),
            _buildChartLegend(ThemeColors.getRedText(isDark), '买入信号'),
            const SizedBox(width: 15),
            _buildChartLegend(ThemeColors.getGreenText(isDark), '卖出信号'),
            const SizedBox(width: 20),
            const Expanded(
              child: Text(
                '💡 提示：图表中红点表示满足阈值买入，绿点表示上涨止盈/到期强制卖出。',
                style: TextStyle(color: Colors.grey, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBatchReportArea(bool isDark, FundProvider fundProvider) {
    if (!_isBatchOptimizing && _batchResults.isEmpty) {
      return _buildStrategyIntroCard(isDark);
    }

    final double progressPct;
    if (_batchResults.isEmpty) {
      progressPct = 0.0;
    } else {
      final completed = _batchResults
          .where((r) => r.status != '等待中' && r.status != '计算中')
          .length;
      progressPct = (completed / _batchResults.length) * 100.0;
    }

    // 定义每列的配置宽度与标题
    final List<_BatchColConfig> columns = [
      _BatchColConfig(title: '代码', width: 70),
      _BatchColConfig(title: '基金名称', width: 140, alignLeft: true),
      _BatchColConfig(title: '板块', width: 90, alignLeft: true),
      _BatchColConfig(title: '寻优状态', width: 85),
      _BatchColConfig(title: '买入天数', width: 65),
      _BatchColConfig(title: '买入下跌', width: 65),
      _BatchColConfig(title: '止盈年化', width: 65),
      _BatchColConfig(title: '最优胜率', width: 75),
      _BatchColConfig(title: '交易次数', width: 70),
      _BatchColConfig(title: '单均收益', width: 75),
      _BatchColConfig(title: '卖出参数', width: 90),
      _BatchColConfig(title: '卖出胜率', width: 75),
      _BatchColConfig(title: '数据时长', width: 100),
    ];

    final double totalTableWidth =
        columns.map((c) => c.width).reduce((a, b) => a + b);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    final Widget tableWidget = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: fluent.Scrollbar(
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
          controller: _batchVerticalScrollController,
          child: fluent.Scrollbar(
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            controller: _batchHorizontalScrollController,
            child: SingleChildScrollView(
            controller: _batchHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalTableWidth,
              child: Column(
                children: [
                  // 表头
                  Container(
                    height: 55,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: columns.map((col) {
                        final isCurrentSort = _sortColumn == col.title;
                        return GestureDetector(
                          onTap: _isBatchOptimizing
                              ? null
                              : () => _sortBatchResults(col.title),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: col.width,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.0),
                              child: Row(
                                mainAxisAlignment: col.alignLeft
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      col.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: _isBatchOptimizing
                                            ? Colors.grey
                                            : (isCurrentSort
                                                ? Colors.blue
                                                : null),
                                      ),
                                      textAlign: col.alignLeft
                                          ? TextAlign.left
                                          : TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentSort) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      _sortAscending
                                          ? fluent.FluentIcons.up
                                          : fluent.FluentIcons.down,
                                      size: 8,
                                      color: Colors.blue,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // 数据行
                  Expanded(
                    child: ListView.builder(
                        controller: _batchVerticalScrollController,
                        padding: const EdgeInsets.only(bottom: 14),
                        itemCount: _batchResults.length,
                        itemBuilder: (context, index) {
                          final result = _batchResults[index];
                          return _buildBatchRow(context, result, isDark);
                        },
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

    return Column(
      children: [
        // 进度卡片
        if (_isBatchOptimizing || progressPct == 100.0)
          fluent.Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isBatchOptimizing
                            ? '🧬 正在进行板块批量寻优...'
                            : '🎉 批量寻优已全部完成！',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '${progressPct.toThousand(precision: 1)}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: fluent.ProgressBar(
                      value: progressPct,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                      activeColor: Colors.blue,
                    ),
                  ),
                  if (_isBatchOptimizing && _batchProgress.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _batchProgress,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '💡 寻优数据区间说明：最优方案基于各只基金在本地缓存的全部历史净值数据（默认最多抓取最近 2000 个交易日，最长约 8.2 年）通过遗传算法计算得出。',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        // 表格卡片
        isSmallScreen
            ? SizedBox(height: 350, child: tableWidget)
            : Expanded(child: tableWidget),
      ],
    );
  }

  Widget _buildBatchRow(
      BuildContext context, BatchOptResult result, bool isDark) {
    Widget statusWidget = Text(result.status,
        style: const TextStyle(fontSize: 12, color: Colors.grey));

    if (result.status == '计算中') {
      statusWidget = const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: fluent.ProgressRing(strokeWidth: 1.5),
          ),
          SizedBox(width: 6),
          Text('计算中',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold)),
        ],
      );
    } else if (result.status == '成功') {
      statusWidget = Text('成功',
          style: TextStyle(
              fontSize: 12,
              color: ThemeColors.getGreenText(isDark),
              fontWeight: FontWeight.bold));
    } else if (result.status == '无历史数据') {
      statusWidget = Text('无数据',
          style:
              TextStyle(fontSize: 12, color: ThemeColors.getRedText(isDark)));
    } else if (result.status == '未发现交易') {
      statusWidget = const Text('未触发交易',
          style: TextStyle(fontSize: 12, color: Colors.orange));
    } else if (result.status == '计算出错') {
      statusWidget = Text('出错',
          style:
              TextStyle(fontSize: 12, color: ThemeColors.getRedText(isDark)));
    }

    final rowColor = result.status == '计算中'
        ? (isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.blue.withValues(alpha: 0.03))
        : null;

    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // 代码
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: CopyableText(result.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
          // 基金名称
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: CopyableText(result.name,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          // 板块
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(result.sector,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          // 寻优状态
          SizedBox(
            width: 85,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Center(child: statusWidget),
            ),
          ),
          // 买入天数
          SizedBox(
            width: 65,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(result.buyDays != null ? '${result.buyDays}天' : '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          // 买入下跌
          SizedBox(
            width: 65,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(result.buyDrop != null ? '${result.buyDrop}%' : '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          // 止盈年化
          SizedBox(
            width: 65,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                  result.targetProfit != null
                      ? '${result.targetProfit}%'
                      : '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          // 最优胜率
          SizedBox(
            width: 75,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                result.winRate != null
                    ? '${result.winRate!.toThousand(precision: 1)}%'
                    : '--',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: result.winRate != null ? FontWeight.bold : null,
                  color: result.winRate != null
                      ? ThemeColors.getRedText(isDark)
                      : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          // 交易次数
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                  result.totalTrades != null ? '${result.totalTrades}笔' : '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          // 单均收益
          SizedBox(
            width: 75,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                  result.avgProfit != null
                      ? '${result.avgProfit!.toThousand(precision: 2)}%'
                      : '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          // 卖出参数
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Builder(
                builder: (context) {
                  final decoded = _decodeSellParams(result.sellX);
                  return Text(
                    decoded != null
                        ? '卖:${decoded['sellX']}天>${decoded['sellPct']}%'
                        : '--',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
          ),
          // 卖出胜率
          SizedBox(
            width: 75,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                result.sellWinRate != null
                    ? '${result.sellWinRate!.toThousand(precision: 1)}%'
                    : '--',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      result.sellWinRate != null ? FontWeight.bold : null,
                  color: result.sellWinRate != null
                      ? ThemeColors.getRedText(isDark)
                      : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          // 数据时长
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(result.dataDuration ?? '--',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runBatchGeneticOptimization() async {
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    final List<FundUIModel> targets;
    final Map<String, FundUIModel> uniqueTargets = {};

    if (_selectedTabs.contains('holding')) {
      for (final f in fundProvider.myFunds.values.where((f) => f.isHeld)) {
        uniqueTargets[f.code] = f;
      }
    }
    if (_selectedTabs.contains('my_funds')) {
      for (final f in fundProvider.myFunds.values) {
        uniqueTargets[f.code] = f;
      }
    }
    if (_selectedTabs.contains('special')) {
      for (final f in fundProvider.myFunds.values.where((f) => f.isSpecial)) {
        uniqueTargets[f.code] = f;
      }
    }
    if (_selectedTabs.contains('valuation')) {
      final valFunds = fundProvider.valuationList
          .map((item) => item['assocFund'] as FundUIModel?)
          .whereType<FundUIModel>();
      for (final f in valFunds) {
        uniqueTargets[f.code] = f;
      }
    }
    if (_selectedTabs.contains('top_ranking')) {
      for (final f in fundProvider.topFunds) {
        uniqueTargets[f.code] = f;
      }
    }
    if (_selectedTabs.contains('bot_ranking')) {
      for (final f in fundProvider.botFunds) {
        uniqueTargets[f.code] = f;
      }
    }

    targets = uniqueTargets.values.toList();

    if (targets.isEmpty) {
      fluent.displayInfoBar(
        context,
        builder: (context, close) {
          return fluent.InfoBar(
            title: const Text('无可寻优基金'),
            content: const Text('当前选择的 Tab 来源下没有任何有效的基金产品。'),
            severity: fluent.InfoBarSeverity.warning,
            onClose: close,
          );
        },
      );
      return;
    }

    setState(() {
      _isBatchOptimizing = true;
      _batchProgress = '准备中...';
      _batchResults = targets
          .map((f) => BatchOptResult(
                code: f.code,
                name: f.name,
                sector: f.sector,
                status: '等待中',
              ))
          .toList();
    });

    const int maxConcurrency = 4;
    int index = 0;
    final List<Map<String, dynamic>> strategiesToSave = [];

    Future<void> worker() async {
      while (index < targets.length && _isBatchOptimizing) {
        final currentIndex = index++;
        final fund = targets[currentIndex];
        final resultItem = _batchResults.firstWhere((r) => r.code == fund.code);

        if (!mounted) return;
        setState(() {
          resultItem.status = '计算中';
          _batchProgress =
              '正在寻优 (${currentIndex + 1}/${targets.length}): ${fund.code} - ${fund.name}';
        });

        final proxyCode = AppConfig.indexProxyMap[fund.code] ?? fund.code;
        var history = await FundHistoryDB().getHistory(proxyCode);
        if (history == null || history['navs'] == null) {
          final onlineHis = await FundDataGateway().fetchEtfHistory(proxyCode);
          if (onlineHis != null) {
            final List<double> navs =
                List<double>.from(onlineHis['navs'] ?? []);
            final List<String> dates =
                List<String>.from(onlineHis['dates'] ?? []);
            await FundHistoryDB()
                .saveHistory(proxyCode, onlineHis['jzrq'], navs, dates);
            history = await FundHistoryDB().getHistory(proxyCode);
          }
        }
        if (!mounted) return;
        if (!_isBatchOptimizing) break;

        if (history == null || history['navs'] == null) {
          setState(() {
            resultItem.status = '数据不足(<30天)';
            resultItem.dataDuration = '--';
            resultItem.dataDurationDays = 0;
          });
          continue;
        }

        final List<double> navs =
            List<double>.from(history['navs'] ?? []).reversed.toList();
        final List<String> dates =
            List<String>.from(history['dates'] ?? []).reversed.toList();

        String durationStr = '--';
        int durationDays = dates.length;
        if (dates.isNotEmpty) {
          final firstDate = DateTime.tryParse(dates.first);
          final lastDate = DateTime.tryParse(dates.last);
          if (firstDate != null && lastDate != null) {
            final years = lastDate.difference(firstDate).inDays / 365.0;
            durationStr =
                "${years.toThousand(precision: 1)}年 (${dates.length}天)";
          } else {
            durationStr = "${dates.length}天";
          }
        }
        try {
          final optStrategy =
              await FundHistoryDB().getOptimalStrategy(fund.code);
          int? sX;
          double? sPct;
          if (optStrategy != null && optStrategy['sell_x'] != null) {
            final int encodedVal = optStrategy['sell_x'];
            if (encodedVal >= 100) {
              sX = encodedVal ~/ 1000;
              sPct = (encodedVal % 1000).toDouble();
            } else {
              sX = encodedVal;
              sPct = encodedVal.toDouble();
            }
          }

          final defaults = getDefaultStrategyFilters(fund.name, fund.sector);
          final double defaultRsi = defaults['rsi'];
          final bool defaultMacd = defaults['macd'];
          final double defaultPe = defaults['pe'];
          final double defaultPb = defaults['pb'];

          final double oldRsi = optStrategy?['rsi_filter_limit'] ?? defaultRsi;
          final bool oldMacd = optStrategy?['macd_filter_enabled'] != null
              ? (optStrategy!['macd_filter_enabled'] == 1)
              : defaultMacd;

          final optResult =
              await safeCompute(_runStrategyOptimizationInIsolate, {
            'navs': navs,
            'dates': dates,
            'useMaFilter': true,
            'trailingDropPct': 2.0,
            'sellX': sX,
            'sellPct': sPct,
            'lowThreshold': appConfig.volatilityLowThreshold,
            'highThreshold': appConfig.volatilityHighThreshold,
            'rsiFilterLimit': oldRsi,
            'useMacdFilter': oldMacd,
          });

          if (!mounted) return;
          if (!_isBatchOptimizing) break;

          if (optResult != null) {
            final opt = optResult['opt'];
            final sellX = optResult['sell_x'] as int?;
            final sellWinRate = optResult['sell_win_rate'] as double?;
            final sellTrades = optResult['sell_trades'] as int?;

            setState(() {
              resultItem.status = '成功';
              resultItem.winRate = opt['win_rate'];
              resultItem.buyDays = opt['buy_days'];
              resultItem.buyDrop = opt['buy_drop'];
              resultItem.targetProfit = opt['target_profit'];
              resultItem.avgProfit = opt['avg_profit'];
              resultItem.totalTrades = opt['total_trades'];
              resultItem.dataDuration = durationStr;
              resultItem.dataDurationDays = durationDays;
              resultItem.sellX = sellX;
              resultItem.sellWinRate = sellWinRate;
              resultItem.sellTrades = sellTrades;
            });

            final oldPe = optStrategy?['pe_percentile_limit'] ?? defaultPe;
            final oldPb = optStrategy?['pb_percentile_limit'] ?? defaultPb;

            strategiesToSave.add({
              'fund_code': fund.code,
              'fund_name': fund.name,
              'buy_days': opt['buy_days'],
              'buy_drop': opt['buy_drop'],
              'target_profit': opt['target_profit'],
              'hold_min': opt['hold_min'],
              'hold_max': opt['hold_max'],
              'win_rate': opt['win_rate'],
              'total_trades': opt['total_trades'],
              'avg_profit': opt['avg_profit'],
              'sell_x': sellX,
              'sell_win_rate': sellWinRate,
              'sell_trades': sellTrades,
              'ma_period': opt['ma_period'],
              'ma_envelope_pct': opt['ma_envelope_pct'],
              'rsi_filter_limit': oldRsi,
              'macd_filter_enabled': oldMacd ? 1 : 0,
              'pe_percentile_limit': oldPe,
              'pb_percentile_limit': oldPb,
            });
          } else {
            setState(() {
              resultItem.status = '无有效策略';
              resultItem.dataDuration = durationStr;
              resultItem.dataDurationDays = durationDays;
            });
          }
        } catch (e, st) {
          debugPrint('寻优出错 (${fund.code}): $e\n$st');
          if (!mounted) return;
          setState(() {
            resultItem.status = '计算出错';
            resultItem.dataDuration = durationStr;
            resultItem.dataDurationDays = durationDays;
          });
        }
      }
    }

    final List<Future<void>> workers = [];
    for (int w = 0; w < math.min(maxConcurrency, targets.length); w++) {
      workers.add(worker());
    }
    await Future.wait(workers);

    if (strategiesToSave.isNotEmpty && _isBatchOptimizing) {
      await FundHistoryDB().saveOptimalStrategies(strategiesToSave);
      await fundProvider.updateAllOptimalStrategies();
    }

    if (!mounted) return;

    setState(() {
      _isBatchOptimizing = false;
      _batchProgress = '批量寻优计算完成';
    });

    fundProvider.loadMyFunds();

    fluent.displayInfoBar(
      context,
      builder: (context, close) {
        return fluent.InfoBar(
          title: const Text('批量寻优计算完成'),
          content: Text('已完成对选中板块下 ${targets.length} 只基金的参数寻优，最优参数均已写入本地数据库中。'),
          severity: fluent.InfoBarSeverity.success,
          onClose: close,
        );
      },
    );
  }

  void _sortBatchResults(String columnTitle) {
    setState(() {
      if (_sortColumn == columnTitle) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnTitle;
        _sortAscending = false;
      }

      _batchResults.sort((a, b) {
        dynamic valA;
        dynamic valB;

        switch (columnTitle) {
          case '代码':
            valA = a.code;
            valB = b.code;
            break;
          case '基金名称':
            valA = a.name;
            valB = b.name;
            break;
          case '板块':
            valA = a.sector;
            valB = b.sector;
            break;
          case '寻优状态':
            valA = a.status;
            valB = b.status;
            break;
          case '买入天数':
            valA = a.buyDays;
            valB = b.buyDays;
            break;
          case '买入下跌':
            valA = a.buyDrop;
            valB = b.buyDrop;
            break;
          case '止盈年化':
            valA = a.targetProfit;
            valB = b.targetProfit;
            break;
          case '最优胜率':
            valA = a.winRate;
            valB = b.winRate;
            break;
          case '交易次数':
            valA = a.totalTrades;
            valB = b.totalTrades;
            break;
          case '单均收益':
            valA = a.avgProfit;
            valB = b.avgProfit;
            break;
          case '卖出参数':
            valA = a.sellX;
            valB = b.sellX;
            break;
          case '卖出胜率':
            valA = a.sellWinRate;
            valB = b.sellWinRate;
            break;
          case '数据时长':
            valA = a.dataDurationDays;
            valB = b.dataDurationDays;
            break;
          default:
            return 0;
        }

        if (valA == null && valB == null) return 0;
        if (valA == null) return 1;
        if (valB == null) return -1;

        int cmp;
        if (valA is String && valB is String) {
          cmp = valA.compareTo(valB);
        } else if (valA is num && valB is num) {
          cmp = valA.compareTo(valB);
        } else {
          cmp = valA.toString().compareTo(valB.toString());
        }

        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  Widget _buildSingleReportTable(bool isDark) {
    // 定义每列的配置宽度与标题，和批量寻优完全一样
    final List<_BatchColConfig> columns = [
      _BatchColConfig(title: '代码', width: 70),
      _BatchColConfig(title: '基金名称', width: 140, alignLeft: true),
      _BatchColConfig(title: '板块', width: 90, alignLeft: true),
      _BatchColConfig(title: '寻优状态', width: 85),
      _BatchColConfig(title: '买入天数', width: 65),
      _BatchColConfig(title: '买入下跌', width: 65),
      _BatchColConfig(title: '止盈年化', width: 65),
      _BatchColConfig(title: '最优胜率', width: 75),
      _BatchColConfig(title: '交易次数', width: 70),
      _BatchColConfig(title: '单均收益', width: 75),
      _BatchColConfig(title: '卖出参数', width: 90),
      _BatchColConfig(title: '卖出胜率', width: 75),
      _BatchColConfig(title: '数据时长', width: 100),
    ];

    final double totalTableWidth =
        columns.map((c) => c.width).reduce((a, b) => a + b);

    return fluent.Card(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: fluent.Scrollbar(
            controller: _singleHorizontalScrollController,
            child: SingleChildScrollView(
              controller: _singleHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalTableWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 表头
                    Container(
                      height: 55,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      padding: EdgeInsets.zero,
                      child: Row(
                        children: columns.map((col) {
                          return SizedBox(
                            width: col.width,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.0),
                              child: Text(
                                col.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                textAlign: col.alignLeft
                                    ? TextAlign.left
                                    : TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    // 数据行 (直接复用 _buildBatchRow)
                    _buildBatchRow(context, _singleOptResult!, isDark),
                    // 底部预留滚动条空间以防遮挡
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartLegend(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 4, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  // 辅助转换 spots (已使用缓存加速交互重绘)
  List<FlSpot> _getChartSpots() => _cachedChartSpots;
  List<FlSpot> _getBuySpots() => _cachedBuySpots;
  List<FlSpot> _getSellSpots() => _cachedSellSpots;

  void _updateSpotsCache() {
    _cachedChartSpots = [];
    for (int idx = 0; idx < _chartNavs.length; idx++) {
      _cachedChartSpots.add(FlSpot(idx.toDouble(), _chartNavs[idx]));
    }

    _cachedBuySpots = [];
    _cachedSellSpots = [];
    if (_backtestResult != null) {
      for (final t in _backtestResult!.trades) {
        final int buyIdx = t['buy_idx'] as int;
        final double buyNav = t['buy_nav'] as double;
        if (buyIdx < _chartNavs.length) {
          _cachedBuySpots.add(FlSpot(buyIdx.toDouble(), buyNav));
        }

        final int sellIdx = t['sell_idx'] as int;
        final double sellNav = t['sell_nav'] as double;
        if (sellIdx < _chartNavs.length) {
          _cachedSellSpots.add(FlSpot(sellIdx.toDouble(), sellNav));
        }
      }
    }
  }

  // 1. 运行单次回测
  Future<void> _runSingleBacktest() async {
    if (_selectedCode == null) return;
    final String targetCode = _selectedCode!;
    setState(() {
      _singleOptResult?.status = '计算中';
    });
    final proxyCode = AppConfig.indexProxyMap[targetCode] ?? targetCode;
    var history = await FundHistoryDB().getHistory(proxyCode);
    if (history == null || history['navs'] == null) {
      final onlineHis = await FundDataGateway().fetchEtfHistory(proxyCode);
      if (onlineHis != null) {
        final List<double> navs = List<double>.from(onlineHis['navs'] ?? []);
        final List<String> dates = List<String>.from(onlineHis['dates'] ?? []);
        await FundHistoryDB()
            .saveHistory(proxyCode, onlineHis['jzrq'], navs, dates);
        history = await FundHistoryDB().getHistory(proxyCode);
      }
    }
    if (!mounted || _selectedCode != targetCode) return;
    if (history == null || history['navs'] == null) {
      setState(() {
        _singleOptResult?.status = '无历史数据';
      });
      fluent.displayInfoBar(
        context,
        builder: (context, close) {
          return fluent.InfoBar(
            title: const Text('数据缺失'),
            content: const Text('本地数据库尚未缓存该产品的历史净值。请先在“自选看板”刷新数据获取历史。'),
            severity: fluent.InfoBarSeverity.error,
            onClose: close,
          );
        },
      );
      return;
    }

    final List<double> navs =
        List<double>.from(history['navs'] ?? []).reversed.toList();
    final List<String> dates =
        List<String>.from(history['dates'] ?? []).reversed.toList();

    final optStrategy = await FundHistoryDB().getOptimalStrategy(targetCode);
    int? sX;
    double? sPct;
    int maPeriod = 120; // 默认兼容老策略
    double maEnvelopePct = 0.0;
    int holdMax = 90;
    if (optStrategy != null) {
      if (optStrategy['sell_x'] != null) {
        final int encodedVal = optStrategy['sell_x'];
        if (encodedVal >= 100) {
          sX = encodedVal ~/ 1000;
          sPct = (encodedVal % 1000).toDouble();
        } else {
          sX = encodedVal;
          sPct = encodedVal.toDouble();
        }
      }
      if (optStrategy.containsKey('ma_period')) {
        maPeriod = optStrategy['ma_period'] ?? 0;
        maEnvelopePct = optStrategy['ma_envelope_pct'] ?? 0.0;
      }
      // 读取策略库中的最长持仓周期，保证回测与寻优评估口径一致
      holdMax = (optStrategy['hold_max'] as int?) ?? 90;
    }
    if (!mounted || _selectedCode != targetCode) return;

    // 在后台执行回测与卖出信号寻优，避免阻塞 UI 线程
    final computeResult = await safeCompute(_runSingleBacktestInIsolate, {
      'navs': navs,
      'dates': dates,
      'buyDays': _buyDays,
      'buyDrop': _buyDrop,
      'targetProfit': _targetProfit,
      'maPeriod': maPeriod,
      'maEnvelopePct': maEnvelopePct,
      'holdMax': holdMax,
      'sellX': sX,
      'sellPct': sPct,
      'rsiFilterLimit': _rsiFilterLimit,
      'useMacdFilter': _useMacdFilter,
      'slippagePct': _slippagePct,
      'gridSpacingPct': (_buyDrop * 0.3).clamp(1.0, 5.0),
    });
    final BacktestResult res = computeResult['result'] as BacktestResult;
    final Map<String, dynamic>? sellOpt =
        computeResult['sellOpt'] as Map<String, dynamic>?;

    if (!mounted || _selectedCode != targetCode) return;

    // 计算时长字符串
    String durationStr = '--';
    int durationDays = dates.length;
    if (dates.isNotEmpty) {
      final firstDate = DateTime.tryParse(dates.first);
      final lastDate = DateTime.tryParse(dates.last);
      if (firstDate != null && lastDate != null) {
        final years = lastDate.difference(firstDate).inDays / 365.0;
        durationStr = "${years.toThousand(precision: 1)}年 (${dates.length}天)";
      } else {
        durationStr = "${dates.length}天";
      }
    }

    setState(() {
      _backtestResult = res;
      _chartNavs = navs;
      _chartDates = dates;
      _updateSpotsCache(); // 更新折线图数据点缓存
      final fundProvider = Provider.of<FundProvider>(context, listen: false);
      final fundName = fundProvider.myFunds[targetCode]?.name ?? '';
      final sector = fundProvider.myFunds[targetCode]?.sector ?? '';
      _singleOptResult = BatchOptResult(
        code: targetCode,
        name: fundName,
        sector: sector,
        status: res.totalTrades > 0 ? '成功' : '未发现交易',
        winRate: res.winRate,
        buyDays: _buyDays,
        buyDrop: _buyDrop,
        targetProfit: _targetProfit,
        avgProfit: res.avgProfit,
        totalTrades: res.totalTrades,
        dataDuration: durationStr,
        dataDurationDays: durationDays,
        sellX: sellOpt?['sell_x'],
        sellWinRate: sellOpt?['sell_win_rate'],
        sellTrades: sellOpt?['sell_trades'],
      );
    });
  }

  // 2. 遗传算法参数寻优 (运行于后台 isolate)
  Future<void> _runGeneticOptimization() async {
    if (_selectedCode == null) return;
    final String targetCode = _selectedCode!;
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final proxyCode = AppConfig.indexProxyMap[targetCode] ?? targetCode;
    var history = await FundHistoryDB().getHistory(proxyCode);
    if (history == null || history['navs'] == null) {
      final onlineHis = await FundDataGateway().fetchEtfHistory(proxyCode);
      if (onlineHis != null) {
        final List<double> navs = List<double>.from(onlineHis['navs'] ?? []);
        final List<String> dates = List<String>.from(onlineHis['dates'] ?? []);
        await FundHistoryDB()
            .saveHistory(proxyCode, onlineHis['jzrq'], navs, dates);
        history = await FundHistoryDB().getHistory(proxyCode);
      }
    }
    if (!mounted) return;
    if (history == null || history['navs'] == null) return;

    setState(() {
      _isOptimizing = true;
      _singleOptResult?.status = '计算中';
    });

    final List<double> navs =
        List<double>.from(history['navs'] ?? []).reversed.toList();
    final List<String> dates =
        List<String>.from(history['dates'] ?? []).reversed.toList();

    try {
      final optStrategy = await FundHistoryDB().getOptimalStrategy(targetCode);
      int? sX;
      double? sPct;
      if (optStrategy != null && optStrategy['sell_x'] != null) {
        final int encodedVal = optStrategy['sell_x'];
        if (encodedVal >= 100) {
          sX = encodedVal ~/ 1000;
          sPct = (encodedVal % 1000).toDouble();
        } else {
          sX = encodedVal;
          sPct = encodedVal.toDouble();
        }
      }

      // 在 Dart 中，通过 compute 可以直接在新后台 Isolate 里并发运算，防止界面卡顿
      // 核心优化：将买入和卖出寻优统一合入后台 Isolate 计算，保证主线程零负荷
      final optResult = await safeCompute(_runStrategyOptimizationInIsolate, {
        'navs': navs,
        'dates': dates,
        'useMaFilter': true,
        'trailingDropPct': 2.0,
        'sellX': sX,
        'sellPct': sPct,
        'lowThreshold': appConfig.volatilityLowThreshold,
        'highThreshold': appConfig.volatilityHighThreshold,
        'rsiFilterLimit': _rsiFilterLimit,
        'useMacdFilter': _useMacdFilter,
      });

      // 异步完成后校验：若组件已销毁或基金已切换，丢弃本次结果防止写入错误基金
      if (!mounted || _selectedCode != targetCode) return;

      if (optResult != null) {
        final opt = optResult['opt'];
        final sellX = optResult['sell_x'] as int?;
        final sellWinRate = optResult['sell_win_rate'] as double?;
        final sellTrades = optResult['sell_trades'] as int?;

        setState(() {
          _buyDays = (opt['buy_days'] as int).clamp(5, 60);
          _buyDrop = (opt['buy_drop'] as double).clamp(0.5, 25.0);
          _targetProfit = (opt['target_profit'] as double).clamp(0.5, 25.0);
        });

        // 保存至本地 SQLite 数据库
        final fundProvider = Provider.of<FundProvider>(context, listen: false);
        final fundName = fundProvider.myFunds[targetCode]?.name ?? '';
        await FundHistoryDB().saveOptimalStrategy(
          fundCode: targetCode,
          fundName: fundName,
          buyDays: opt['buy_days'],
          buyDrop: opt['buy_drop'],
          targetProfit: opt['target_profit'],
          holdMin: opt['hold_min'],
          holdMax: opt['hold_max'],
          winRate: opt['win_rate'],
          totalTrades: opt['total_trades'],
          avgProfit: opt['avg_profit'],
          sellX: sellX,
          sellWinRate: sellWinRate,
          sellTrades: sellTrades,
          maPeriod: opt['ma_period'],
          maEnvelopePct: opt['ma_envelope_pct'],
          rsiFilterLimit: _rsiFilterLimit,
          macdFilterEnabled: _useMacdFilter ? 1 : 0,
          pePercentileLimit: _pePercentileLimit,
          pbPercentileLimit: _pbPercentileLimit,
        );

        if (!mounted) return;

        await fundProvider.updateAllOptimalStrategies();
        fundProvider.loadMyFunds();

        // 顺便展示回测结果，此方法会自动更新 _singleOptResult 状态为成功并填入指标
        await _runSingleBacktest();

        if (!mounted) return;
        fluent.displayInfoBar(
          context,
          builder: (context, close) {
            return fluent.InfoBar(
              title: const Text('寻优计算完成'),
              content: const Text('已为该基金计算出胜率最高的网格参数，且已自动写入本地 SQLite 策略库中。'),
              severity: fluent.InfoBarSeverity.success,
              onClose: close,
            );
          },
        );
      } else {
        setState(() {
          _singleOptResult?.status = '无有效策略';
        });
        fluent.displayInfoBar(
          context,
          builder: (context, close) {
            return fluent.InfoBar(
              title: const Text('未能触发任何交易'),
              content: const Text('遗传算法在历史数据区间内未发现满足下跌回撤及止盈目标的交易。'),
              severity: fluent.InfoBarSeverity.warning,
              onClose: close,
            );
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _singleOptResult?.status = '计算出错';
      });
    } finally {
      // 无论成功、失败还是中途返回，都确保解除 UI 锁定
      if (mounted) {
        setState(() {
          _isOptimizing = false;
        });
      }
    }
  }

  Widget _buildRiskMetricsCards(bool isDark) {
    if (_backtestResult == null) return const SizedBox.shrink();

    final res = _backtestResult!;

    Widget buildCard(String title, String value, String desc, IconData icon,
        Color baseColor) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.02),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: baseColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 640 ? 2 : 4;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 风险调整后收益与波动评估',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final double itemWidth =
                  (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                      crossAxisCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: buildCard(
                      '年化波动率',
                      '${(res.annualizedVolatility * 100).toThousand(precision: 2)}%',
                      '资金收益率的标准偏差',
                      fluent.FluentIcons.diagnostic,
                      Colors.blue,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: buildCard(
                      '夏普比率',
                      res.sharpeRatio.toThousand(precision: 2),
                      '承受每单位总风险的回报',
                      fluent.FluentIcons.financial,
                      Colors.orange,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: buildCard(
                      '索提诺比率',
                      res.sortinoRatio.toThousand(precision: 2),
                      '承受每单位下行风险的回报',
                      fluent.FluentIcons.market,
                      Colors.redAccent,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: buildCard(
                      '最大套牢期',
                      '${res.maxDrawdownDuration} 天',
                      '净值创出新高最长间隔',
                      fluent.FluentIcons.timer,
                      Colors.purple,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// 供 compute 调用的独立顶层函数 (必须是顶层函数以在 Isolate 里解耦运行)
// 单次回测与卖出信号寻优的后台计算，避免阻塞 UI 线程
Map<String, dynamic> _runSingleBacktestInIsolate(Map<String, dynamic> params) {
  final List<double> navs =
      (params['navs'] as List<dynamic>?)?.cast<double>() ?? [];
  final List<String> dates =
      (params['dates'] as List<dynamic>?)?.cast<String>() ?? [];

  final result = BacktestEngine.runBacktest(
    allNavs: navs,
    allDates: dates,
    buyDays: params['buyDays'] as int,
    buyDropPct: params['buyDrop'] as double,
    targetProfitPct: params['targetProfit'] as double,
    holdMax: params['holdMax'] as int? ?? 90,
    useMaFilter: true,
    maPeriod: params['maPeriod'] as int? ?? 0,
    maEnvelopePct: params['maEnvelopePct'] as double? ?? 0.0,
    trailingDropPct: 2.0,
    sellX: params['sellX'] as int?,
    sellPct: params['sellPct'] as double?,
    rsiFilterLimit: params['rsiFilterLimit'] as double? ?? 0.0,
    useMacdFilter: params['useMacdFilter'] as bool? ?? false,
    slippagePct: params['slippagePct'] as double? ?? 0.0,
    gridSpacingPct: params['gridSpacingPct'] as double? ?? 0.0,
  );
  final sellOpt = SellSignalOptimizer.optimize(allNavs: navs, allDates: dates);
  return {'result': result, 'sellOpt': sellOpt};
}

// 供 compute 调用的独立顶层函数 (必须是顶层函数以在 Isolate 里解耦运行)
// 核心优化：合并买入和卖出寻优，在后台 Isolate 一起算完再回传
Map<String, dynamic>? _runStrategyOptimizationInIsolate(
    Map<String, dynamic> params) {
  final List<double> navs =
      (params['navs'] as List<dynamic>?)?.cast<double>() ?? [];
  final List<String> dates =
      (params['dates'] as List<dynamic>?)?.cast<String>() ?? [];
  final bool useMaFilter = params['useMaFilter'] ?? false;
  final double? trailingDropPct = params['trailingDropPct'];
  final int? sellX = params['sellX'];
  final double? sellPct = params['sellPct'];
  final double lowThreshold = params['lowThreshold'] ?? 15.0;
  final double highThreshold = params['highThreshold'] ?? 48.0;
  final double rsiFilterLimit = params['rsiFilterLimit'] ?? 35.0;
  final bool useMacdFilter = params['useMacdFilter'] ?? true;

  final opt = GAOptimizer.optimize(
    allNavs: navs,
    allDates: dates,
    useMaFilter: useMaFilter,
    trailingDropPct: trailingDropPct,
    sellX: sellX,
    sellPct: sellPct,
    lowThreshold: lowThreshold,
    highThreshold: highThreshold,
    rsiFilterLimit: rsiFilterLimit,
    useMacdFilter: useMacdFilter,
  );
  if (opt == null) return null;

  final sellOpt = SellSignalOptimizer.optimize(allNavs: navs, allDates: dates);
  return {
    'opt': opt,
    'sell_x': sellOpt?['sell_x'],
    'sell_win_rate': sellOpt?['sell_win_rate'],
    'sell_trades': sellOpt?['sell_trades'],
  };
}

class _BatchColConfig {
  final String title;
  final double width;
  final bool alignLeft;

  _BatchColConfig({
    required this.title,
    required this.width,
    this.alignLeft = false,
  });
}
