import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../core/utils/theme_colors.dart';

/// 基金走势图详情弹窗
class FundChartDialog extends StatefulWidget {
  final String fundCode;
  final String fundName;
  final List<double> navs;
  final List<String> dates;
  final double? todayEstimateNav;
  final double? todayEstimatePct;
  final String? todayEstimateTime;

  const FundChartDialog({
    super.key,
    required this.fundCode,
    required this.fundName,
    required this.navs,
    required this.dates,
    this.todayEstimateNav,
    this.todayEstimatePct,
    this.todayEstimateTime,
  });

  @override
  State<FundChartDialog> createState() => _FundChartDialogState();
}

class _FundChartDialogState extends State<FundChartDialog> {
  // 周期选项
  String _selectedPeriod = '近1年';
  int _visiblePoints = 252;

  // 量化指标选项
  String _selectedIndicator = '🌡️ 估值百分位温度带';
  String _percentileWindow = '成立以来'; // 近1年, 近3年, 近5年, 成立以来

  // 悬停索引
  int? _hoveredIndex;
  Offset? _hoverPosition;

  // 拖动平移状态
  double _scrollOffset = 0.0; // 累计拖动距离 (数据点个数)
  double _lastPanX = 0.0;

  // 完整正序数据
  List<double> _allNavs = [];
  List<String> _allDates = [];
  bool _hasEstimatePoint = false;

  // 计算好的全量指标
  List<double> _ma5 = [];
  List<double> _ma10 = [];
  List<double> _ma20 = [];
  List<double> _valPct = [];
  List<double> _macdDiff = [];
  List<double> _macdDea = [];
  List<double> _macdBar = [];
  List<double> _kdjK = [];
  List<double> _kdjD = [];
  List<double> _kdjJ = [];
  List<double> _rsi6 = [];
  List<double> _rsi12 = [];

  @override
  void initState() {
    super.initState();
    _prepareData();
  }

  void _prepareData() {
    if (widget.navs.isEmpty) return;

    // 1. 统一转换为正序（最旧在最前，最新在最后）
    _allNavs = widget.navs.reversed.toList();
    _allDates = widget.dates.reversed.toList();

    // 2. 检查并追加今日估值模拟点
    _checkAndAddEstimatePoint();

    // 3. 预先在全量序列上计算指标
    _calculateIndicators();

    // 4. 设置默认截取点数
    _updatePeriodLimit();
  }

  void _checkAndAddEstimatePoint() {
    _hasEstimatePoint = false;
    if (widget.todayEstimateNav == null || widget.todayEstimateNav! <= 0) {
      return;
    }
    if (widget.todayEstimateTime == null ||
        widget.todayEstimateTime!.isEmpty ||
        widget.todayEstimateTime == '暂无数据') return;

    String estTime = widget.todayEstimateTime!;
    String estDate = '';

    // 匹配 YYYY-MM-DD
    final dateReg = RegExp(r'\d{4}-\d{2}-\d{2}');
    final match = dateReg.firstMatch(estTime);
    if (match != null) {
      estDate = match.group(0)!;
    } else {
      // 匹配 MM-DD，并补上年
      final dateRegShort = RegExp(r'\d{2}-\d{2}');
      final matchShort = dateRegShort.firstMatch(estTime);
      if (matchShort != null && _allDates.isNotEmpty) {
        final lastYear = _allDates.last.substring(0, 4);
        estDate = '$lastYear-${matchShort.group(0)!}';
      }
    }

    if (estDate.isEmpty) return;

    if (_allDates.isNotEmpty) {
      final String lastDate = _allDates.last;
      if (lastDate != estDate) {
        _allNavs.add(widget.todayEstimateNav!);
        _allDates.add(estDate);
        _hasEstimatePoint = true;
      }
    }
  }

  void _updatePeriodLimit() {
    final int len = _allNavs.length;
    switch (_selectedPeriod) {
      case '近1月':
        _visiblePoints = math.min(21, len);
        break;
      case '近3月':
        _visiblePoints = math.min(63, len);
        break;
      case '近6月':
        _visiblePoints = math.min(126, len);
        break;
      case '近1年':
        _visiblePoints = math.min(252, len);
        break;
      case '近3年':
        _visiblePoints = math.min(756, len);
        break;
      case '近5年':
        _visiblePoints = math.min(1260, len);
        break;
      case '今年以来':
        _visiblePoints = _getYTDDays();
        break;
      case '全部':
      default:
        _visiblePoints = len;
        break;
    }
    _scrollOffset = 0.0; // 切换区间重置滚动
  }

  int _getYTDDays() {
    final int currentYear = DateTime.now().year;
    int count = 0;
    // _allDates 从旧到新，从后往前查找今年的数据
    for (int i = _allDates.length - 1; i >= 0; i--) {
      try {
        final dt = DateTime.parse(_allDates[i]);
        if (dt.year == currentYear) {
          count++;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return count > 0 ? count : math.min(252, _allNavs.length);
  }

  void _calculateIndicators() {
    // 均线
    _ma5 = _calcMA(_allNavs, 5);
    _ma10 = _calcMA(_allNavs, 10);
    _ma20 = _calcMA(_allNavs, 20);

    // 百分位温度带
    _recalculatePercentiles();

    // MACD
    final macd = _calcMACD(_allNavs);
    _macdDiff = macd['diff']!;
    _macdDea = macd['dea']!;
    _macdBar = macd['bar']!;

    // KDJ
    final kdj = _calcKDJ(_allNavs);
    _kdjK = kdj['k']!;
    _kdjD = kdj['d']!;
    _kdjJ = kdj['j']!;

    // RSI
    _rsi6 = _calcRSI(_allNavs, 6);
    _rsi12 = _calcRSI(_allNavs, 12);
  }

  void _recalculatePercentiles() {
    int limit = 0;
    switch (_percentileWindow) {
      case '近1年':
        limit = 252;
        break;
      case '近3年':
        limit = 756;
        break;
      case '近5年':
        limit = 1260;
        break;
      case '成立以来':
      default:
        limit = 0;
        break;
    }
    _valPct = _calcPercentiles(_allNavs, limit);
  }

  // ---------------- 指数/量化指标计算具体算法 ----------------

  List<double> _calcMA(List<double> data, int period) {
    List<double> result = [];
    for (int i = 0; i < data.length; i++) {
      int start = math.max(0, i - period + 1);
      double sum = 0.0;
      for (int j = start; j <= i; j++) {
        sum += data[j];
      }
      result.add(sum / (i - start + 1));
    }
    return result;
  }

  List<double> _calcPercentiles(List<double> data, int limit) {
    List<double> result = [];
    for (int i = 0; i < data.length; i++) {
      int start = limit == 0 ? 0 : math.max(0, i - limit + 1);
      List<double> window = data.sublist(start, i + 1);
      double val = data[i];
      int less = 0;
      int equal = 0;
      for (double x in window) {
        if (x < val) {
          less++;
        } else if (x == val) {
          equal++;
        }
      }
      double pct = (less + 0.5 * equal) / window.length * 100.0;
      result.add(pct);
    }
    return result;
  }

  Map<String, List<double>> _calcMACD(List<double> data) {
    List<double> ema12 = _calcEMA(data, 12);
    List<double> ema26 = _calcEMA(data, 26);
    List<double> diff = [];
    for (int i = 0; i < data.length; i++) {
      diff.add(ema12[i] - ema26[i]);
    }
    List<double> dea = _calcEMA(diff, 9);
    List<double> bar = [];
    for (int i = 0; i < data.length; i++) {
      bar.add(2.0 * (diff[i] - dea[i]));
    }
    return {'diff': diff, 'dea': dea, 'bar': bar};
  }

  List<double> _calcEMA(List<double> data, int period) {
    List<double> ema = [];
    double k = 2.0 / (period + 1.0);
    for (int i = 0; i < data.length; i++) {
      if (i == 0) {
        ema.add(data[i]);
      } else {
        ema.add(data[i] * k + ema[i - 1] * (1.0 - k));
      }
    }
    return ema;
  }

  Map<String, List<double>> _calcKDJ(List<double> data) {
    List<double> kList = [];
    List<double> dList = [];
    List<double> jList = [];
    double k = 50.0;
    double d = 50.0;
    for (int i = 0; i < data.length; i++) {
      int start = math.max(0, i - 8);
      List<double> window = data.sublist(start, i + 1);
      double high = window.reduce((a, b) => a > b ? a : b);
      double low = window.reduce((a, b) => a < b ? a : b);
      double rsv =
          (high == low) ? 50.0 : (data[i] - low) / (high - low) * 100.0;
      k = (2.0 / 3.0) * k + (1.0 / 3.0) * rsv;
      d = (2.0 / 3.0) * d + (1.0 / 3.0) * k;
      double j = 3.0 * k - 2.0 * d;
      kList.add(k);
      dList.add(d);
      jList.add(j);
    }
    return {'k': kList, 'd': dList, 'j': jList};
  }

  List<double> _calcRSI(List<double> data, int period) {
    if (data.length < 2) return List.filled(data.length, 50.0);
    List<double> deltas = [0.0];
    for (int i = 1; i < data.length; i++) {
      deltas.add(data[i] - data[i - 1]);
    }
    List<double> rsi = [];
    double upEma = 0.0;
    double downEma = 0.0;
    double alpha = 1.0 / period;
    for (int i = 0; i < data.length; i++) {
      double up = deltas[i] > 0 ? deltas[i] : 0.0;
      double down = deltas[i] < 0 ? -deltas[i] : 0.0;
      if (i == 0) {
        upEma = up;
        downEma = down;
      } else {
        upEma = alpha * up + (1.0 - alpha) * upEma;
        downEma = alpha * down + (1.0 - alpha) * downEma;
      }
      if ((upEma + downEma) != 0) {
        rsi.add(upEma / (upEma + downEma) * 100.0);
      } else {
        rsi.add(50.0);
      }
    }
    return rsi;
  }

  // ---------------- 渲染数据截取与统计计算 ----------------

  @override
  Widget build(BuildContext context) {
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    if (_allNavs.isEmpty) {
      return fluent.ContentDialog(
        title: const Text('提示'),
        content: const Text('该基金暂无历史净值数据，无法展示走势图。'),
        actions: [
          fluent.Button(
            child: const Text('确定'),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      );
    }

    // 计算实际切片的区间起点和终点
    final int len = _allNavs.length;
    // 加上拖动偏移
    int offset = _scrollOffset.round();
    int endIdx = len - 1 - offset;
    int startIdx = endIdx - _visiblePoints + 1;

    // 夹逼校正，防止超出范围
    if (startIdx < 0) {
      startIdx = 0;
      endIdx = startIdx + _visiblePoints - 1;
      if (endIdx >= len) {
        endIdx = len - 1;
      }
    }
    if (endIdx >= len) {
      endIdx = len - 1;
      startIdx = endIdx - _visiblePoints + 1;
      if (startIdx < 0) {
        startIdx = 0;
      }
    }

    final int slicedLength = endIdx - startIdx + 1;

    // 截取区间内的数据
    final List<double> slicedNavs = _allNavs.sublist(startIdx, endIdx + 1);
    final List<String> slicedDates = _allDates.sublist(startIdx, endIdx + 1);

    // 主图百分比归一化：以区间第一个点的净值为基数
    final double baseNav = slicedNavs.first;
    final List<double> slicedNavsPct =
        slicedNavs.map((n) => (n - baseNav) / baseNav * 100.0).toList();
    final List<double> slicedMA5Pct = _ma5
        .sublist(startIdx, endIdx + 1)
        .map((n) => (n - baseNav) / baseNav * 100.0)
        .toList();
    final List<double> slicedMA10Pct = _ma10
        .sublist(startIdx, endIdx + 1)
        .map((n) => (n - baseNav) / baseNav * 100.0)
        .toList();
    final List<double> slicedMA20Pct = _ma20
        .sublist(startIdx, endIdx + 1)
        .map((n) => (n - baseNav) / baseNav * 100.0)
        .toList();

    // 副图截取
    final List<double> slicedValPct = _valPct.sublist(startIdx, endIdx + 1);
    final List<double> slicedMacdDiff = _macdDiff.sublist(startIdx, endIdx + 1);
    final List<double> slicedMacdDea = _macdDea.sublist(startIdx, endIdx + 1);
    final List<double> slicedMacdBar = _macdBar.sublist(startIdx, endIdx + 1);
    final List<double> slicedKdjK = _kdjK.sublist(startIdx, endIdx + 1);
    final List<double> slicedKdjD = _kdjD.sublist(startIdx, endIdx + 1);
    final List<double> slicedKdjJ = _kdjJ.sublist(startIdx, endIdx + 1);
    final List<double> slicedRsi6 = _rsi6.sublist(startIdx, endIdx + 1);
    final List<double> slicedRsi12 = _rsi12.sublist(startIdx, endIdx + 1);

    // 区间统计数据
    final double latestNav = slicedNavs.last;
    final double firstNav = slicedNavs.first;
    final double periodProfitPct = (latestNav - firstNav) / firstNav * 100.0;
    final double maxNav = slicedNavs.reduce((a, b) => a > b ? a : b);
    final double minNav = slicedNavs.reduce((a, b) => a < b ? a : b);

    // 计算最大回撤 (根据真实净值)
    double maxDrawdown = 0.0;
    double peak = slicedNavs.first;
    for (double val in slicedNavs) {
      if (val > peak) {
        peak = val;
      }
      final double dd = (val - peak) / peak * 100.0;
      if (dd < maxDrawdown) {
        maxDrawdown = dd;
      }
    }

    final Color statsColor = periodProfitPct >= 0
        ? ThemeColors.getRedText(isDark)
        : ThemeColors.getGreenText(isDark);

    // 悬停明细数据
    String? tooltipText;
    int? highlightIdx;
    if (_hoveredIndex != null &&
        _hoveredIndex! >= 0 &&
        _hoveredIndex! < slicedLength) {
      highlightIdx = _hoveredIndex!;
      final date = slicedDates[highlightIdx];
      final nav = slicedNavs[highlightIdx];

      final bool isEstimatePoint = _hasEstimatePoint &&
          (endIdx == len - 1) &&
          (highlightIdx == slicedLength - 1);
      final String dateStr = isEstimatePoint ? '$date (估值)' : date;

      final double? ma5 = isEstimatePoint ? null : slicedMA5Pct[highlightIdx];
      final double? ma10 = isEstimatePoint ? null : slicedMA10Pct[highlightIdx];
      final double? ma20 = isEstimatePoint ? null : slicedMA20Pct[highlightIdx];

      final dMax = maxNav;
      final dMin = minNav;
      final distHigh = (nav - dMax) / dMax * 100.0;
      final distLow = (nav - dMin) / dMin * 100.0;

      // 以当前选定区间的第一天为基准计算涨跌幅
      double periodChange = 0.0;
      if (slicedNavs.isNotEmpty) {
        periodChange = (nav - slicedNavs[0]) / slicedNavs[0] * 100.0;
      }

      tooltipText = '日期: $dateStr\n'
          '区间涨跌: ${periodChange.toThousand(precision: 2, showSign: true)}%\n';

      if (isEstimatePoint && widget.todayEstimatePct != null) {
        tooltipText +=
            '今日估算: ${widget.todayEstimatePct!.toThousand(precision: 2, showSign: true)}%\n';
      }

      tooltipText += '距最高: ${distHigh.toThousand(precision: 2)}%\n'
          '距最低: ${distLow.toThousand(precision: 2, showSign: true)}%\n'
          'MA5: ${ma5 != null ? '${ma5.toThousand(precision: 2, showSign: true)}%' : '-'}\n'
          'MA10: ${ma10 != null ? '${ma10.toThousand(precision: 2, showSign: true)}%' : '-'}\n'
          'MA20: ${ma20 != null ? '${ma20.toThousand(precision: 2, showSign: true)}%' : '-'}';

      // 叠加副图指标数据
      if (_selectedIndicator == '🌡️ 估值百分位温度带') {
        final vp = slicedValPct[highlightIdx];
        String status = '适中';
        if (vp < 10) {
          status = '极低估';
        } else if (vp < 30) {
          status = '低估';
        } else if (vp > 90) {
          status = '极高估';
        } else if (vp > 70) {
          status = '高估';
        }
        tooltipText +=
            '\n---\n指标: 历史百分位\n百分位: ${vp.toThousand(precision: 2)}%\n状态: $status';
      } else if (_selectedIndicator == '📊 MACD 强弱趋势') {
        final diff = slicedMacdDiff[highlightIdx];
        final dea = slicedMacdDea[highlightIdx];
        final bar = slicedMacdBar[highlightIdx];
        tooltipText +=
            '\n---\n指标: MACD\nDIFF: ${diff.toThousand(precision: 4)}\nDEA: ${dea.toThousand(precision: 4)}\nMACD: ${bar.toThousand(precision: 4)}';
      } else if (_selectedIndicator == '📈 KDJ 超买超卖') {
        final k = slicedKdjK[highlightIdx];
        final d = slicedKdjD[highlightIdx];
        final j = slicedKdjJ[highlightIdx];
        tooltipText +=
            '\n---\n指标: KDJ (9,3,3)\nK值: ${k.toThousand(precision: 2)}\nD值: ${d.toThousand(precision: 2)}\nJ值: ${j.toThousand(precision: 2)}';
      } else if (_selectedIndicator == '📉 RSI 强弱强弱') {
        final rsi6 = slicedRsi6[highlightIdx];
        final rsi12 = slicedRsi12[highlightIdx];
        tooltipText +=
            '\n---\n指标: RSI (6,12)\nRSI6: ${rsi6.toThousand(precision: 2)}\nRSI12: ${rsi12.toThousand(precision: 2)}';
      }
    }

    final textTheme = isDark ? Colors.white : Colors.black87;
    final controlBg =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFEFEFEF);
    final comboStyle = TextStyle(color: textTheme, fontSize: 12);

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 700;

    return fluent.ContentDialog(
      constraints: BoxConstraints(
        maxWidth: isSmallScreen ? screenWidth : 960,
        maxHeight:
            isSmallScreen ? MediaQuery.of(context).size.height * 0.85 : 680,
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '${widget.fundName} (${widget.fundCode})',
              style: TextStyle(
                fontWeight: fluent.FontWeight.bold,
                fontSize: isSmallScreen ? 14 : 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.chrome_close, size: 14),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. 顶部统计数据与周期控制栏
          if (isSmallScreen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 统计小横幅
                Text(
                  '统计周期: ${slicedDates.first} 至 ${slicedDates.last} ($slicedLength个交易日)',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '区间收益率: ${periodProfitPct.toThousand(precision: 2, showSign: true)}% | '
                  '最大回撤: ${maxDrawdown.toThousand(precision: 2)}%',
                  style: TextStyle(
                      color: statsColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // 周期选择按钮组
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    '近1月',
                    '近3月',
                    '近6月',
                    '近1年',
                    '近3年',
                    '近5年',
                    '今年以来',
                    '全部'
                  ].map((period) {
                    final isSel = _selectedPeriod == period;
                    return fluent.Button(
                      style: fluent.ButtonStyle(
                        backgroundColor: fluent.WidgetStateProperty.all(
                            isSel ? Colors.blue : controlBg),
                        padding: fluent.WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                      ),
                      child: Text(
                        period,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSel
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedPeriod = period;
                          _updatePeriodLimit();
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            )
          else
            Row(
              children: [
                // 统计小横幅
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '统计周期: ${slicedDates.first} 至 ${slicedDates.last} ($slicedLength个交易日)',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '区间收益率: ${periodProfitPct.toThousand(precision: 2, showSign: true)}% | '
                        '最大回撤: ${maxDrawdown.toThousand(precision: 2)}%',
                        style: TextStyle(
                            color: statsColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                // 周期选择按钮组
                Wrap(
                  spacing: 4,
                  children: [
                    '近1月',
                    '近3月',
                    '近6月',
                    '近1年',
                    '近3年',
                    '近5年',
                    '今年以来',
                    '全部'
                  ].map((period) {
                    final isSel = _selectedPeriod == period;
                    return fluent.Button(
                      style: fluent.ButtonStyle(
                        backgroundColor: fluent.WidgetStateProperty.all(
                            isSel ? Colors.blue : controlBg),
                        padding: fluent.WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                      ),
                      child: Text(
                        period,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSel
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedPeriod = period;
                          _updatePeriodLimit();
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          const SizedBox(height: 8),

          // B. 交互式走势图画板（主图与副图使用一个统一的鼠标监视器）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;
                final double height = constraints.maxHeight;

                // 主图与副图共享 X 轴范围与坐标宽度对齐
                const double plotLeft = 55.0;
                final double plotRight = width - 15.0;
                final double plotWidth = plotRight - plotLeft;

                // 主图区域高度占 55%，副图占 35%，间隙占 10%
                final double topHeight = height * 0.55;
                final double bottomHeight = height * 0.35;
                final double gap = height * 0.10;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 拖拽平移
                  onPanStart: (details) {
                    _lastPanX = details.localPosition.dx;
                  },
                  onPanUpdate: (details) {
                    final double deltaX = details.localPosition.dx - _lastPanX;
                    _lastPanX = details.localPosition.dx;
                    // 一个像素对应多少个点
                    final double pixelsPerPoint =
                        plotWidth / (slicedLength - 1);
                    if (pixelsPerPoint > 0) {
                      setState(() {
                        _scrollOffset += (deltaX / pixelsPerPoint);
                        // 夹逼
                        final maxOffset = len - _visiblePoints;
                        if (_scrollOffset < 0) _scrollOffset = 0;
                        if (_scrollOffset > maxOffset) {
                          _scrollOffset = maxOffset.toDouble();
                        }
                      });
                    }
                  },
                  child: MouseRegion(
                    onHover: (details) {
                      final double x = details.localPosition.dx;
                      if (x >= plotLeft && x <= plotRight) {
                        final double fraction = (x - plotLeft) / plotWidth;
                        int idx = (fraction * (slicedLength - 1)).round();
                        if (idx >= 0 && idx < slicedLength) {
                          setState(() {
                            _hoveredIndex = idx;
                            _hoverPosition = details.localPosition;
                          });
                        }
                      } else {
                        setState(() {
                          _hoveredIndex = null;
                          _hoverPosition = null;
                        });
                      }
                    },
                    onExit: (_) {
                      setState(() {
                        _hoveredIndex = null;
                        _hoverPosition = null;
                      });
                    },
                    child: Stack(
                      children: [
                        // C. 绘制折线图
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 主走势折线图 (归一化收益率 % + MA5/10/20)
                            SizedBox(
                              height: topHeight,
                              child: CustomPaint(
                                painter: _MainChartPainter(
                                  navsPct: slicedNavsPct,
                                  ma5Pct: slicedMA5Pct,
                                  ma10Pct: slicedMA10Pct,
                                  ma20Pct: slicedMA20Pct,
                                  dates: slicedDates,
                                  isDark: isDark,
                                  plotLeft: plotLeft,
                                  plotRight: plotRight,
                                  highlightIdx: highlightIdx,
                                  showEstimateDottedLine:
                                      _hasEstimatePoint && (endIdx == len - 1),
                                ),
                              ),
                            ),
                            SizedBox(height: gap),
                            // 副指标图
                            SizedBox(
                              height: bottomHeight,
                              child: CustomPaint(
                                painter: _IndicatorChartPainter(
                                  indicatorType: _selectedIndicator,
                                  valPct: slicedValPct,
                                  macdDiff: slicedMacdDiff,
                                  macdDea: slicedMacdDea,
                                  macdBar: slicedMacdBar,
                                  kdjK: slicedKdjK,
                                  kdjD: slicedKdjD,
                                  kdjJ: slicedKdjJ,
                                  rsi6: slicedRsi6,
                                  rsi12: slicedRsi12,
                                  isDark: isDark,
                                  plotLeft: plotLeft,
                                  plotRight: plotRight,
                                  highlightIdx: highlightIdx,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // D. 手势连通虚线绘制 (十字光标)
                        if (highlightIdx != null)
                          CustomPaint(
                            size: Size(width, height),
                            painter: _CrosshairPainter(
                              highlightIdx: highlightIdx,
                              slicedLength: slicedLength,
                              plotLeft: plotLeft,
                              plotRight: plotRight,
                              topHeight: topHeight,
                              bottomHeight: bottomHeight,
                              gap: gap,
                              isDark: isDark,
                              navsPct: slicedNavsPct,
                              ma5Pct: slicedMA5Pct,
                              ma10Pct: slicedMA10Pct,
                              ma20Pct: slicedMA20Pct,
                            ),
                          ),

                        // E. 浮动 Tooltip 信息面板（仿磨砂毛玻璃）
                        if (tooltipText != null && _hoverPosition != null)
                          Positioned(
                            left: _hoverPosition!.dx + 15 + 165 > width
                                ? _hoverPosition!.dx - 15 - 165
                                : _hoverPosition!.dx + 15,
                            top: math.max(
                                10.0,
                                math.min(
                                    topHeight - 100, _hoverPosition!.dy - 50)),
                            child: IgnorePointer(
                              child: Container(
                                width: 165,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xE01E272E)
                                      : const Color(0xE0FFFFFF),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                          alpha: isDark ? 0.4 : 0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white12
                                        : Colors.black12,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  tooltipText,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    height: 1.4,
                                    fontFamily: 'Segoe UI',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // F. 底部量化指标选择控制栏
          if (isSmallScreen)
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        '指标: ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      fluent.ComboBox<String>(
                        value: _selectedIndicator,
                        items: [
                          '🌡️ 估值百分位温度带',
                          '📊 MACD 强弱趋势',
                          '📈 KDJ 超买超卖',
                          '📉 RSI 强弱强弱'
                        ].map((ind) {
                          return fluent.ComboBoxItem<String>(
                            value: ind,
                            child: Text(ind, style: comboStyle),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedIndicator = val;
                            });
                          }
                        },
                      ),
                      if (_selectedIndicator == '🌡️ 估值百分位温度带') ...[
                        const Text(
                          '区间: ',
                          style: TextStyle(fontSize: 12),
                        ),
                        fluent.ComboBox<String>(
                          value: _percentileWindow,
                          items: ['近1年', '近3年', '近5年', '成立以来'].map((win) {
                            return fluent.ComboBoxItem<String>(
                              value: win,
                              child: Text(win, style: comboStyle),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _percentileWindow = val;
                                _recalculatePercentiles();
                              });
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                fluent.Button(
                  child: const Text('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            )
          else
            Row(
              children: [
                const Text(
                  '量化分析指标子图: ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(width: 8),
                fluent.ComboBox<String>(
                  value: _selectedIndicator,
                  items: [
                    '🌡️ 估值百分位温度带',
                    '📊 MACD 强弱趋势',
                    '📈 KDJ 超买超卖',
                    '📉 RSI 强弱强弱'
                  ].map((ind) {
                    return fluent.ComboBoxItem<String>(
                      value: ind,
                      child: Text(ind, style: comboStyle),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedIndicator = val;
                      });
                    }
                  },
                ),
                if (_selectedIndicator == '🌡️ 估值百分位温度带') ...[
                  const SizedBox(width: 16),
                  const Text(
                    '计算区间: ',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  fluent.ComboBox<String>(
                    value: _percentileWindow,
                    items: ['近1年', '近3年', '近5年', '成立以来'].map((win) {
                      return fluent.ComboBoxItem<String>(
                        value: win,
                        child: Text(win, style: comboStyle),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _percentileWindow = val;
                          _recalculatePercentiles();
                        });
                      }
                    },
                  ),
                ],
                const Spacer(),
                fluent.Button(
                  child: const Text('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
        ],
      ),
    );
  }
}

// ----------------- Custom Painter 绘制器实现 -----------------

class _MainChartPainter extends CustomPainter {
  final List<double> navsPct;
  final List<double> ma5Pct;
  final List<double> ma10Pct;
  final List<double> ma20Pct;
  final List<String> dates;
  final bool isDark;
  final double plotLeft;
  final double plotRight;
  final int? highlightIdx;
  final bool showEstimateDottedLine;

  _MainChartPainter({
    required this.navsPct,
    required this.ma5Pct,
    required this.ma10Pct,
    required this.ma20Pct,
    required this.dates,
    required this.isDark,
    required this.plotLeft,
    required this.plotRight,
    required this.showEstimateDottedLine,
    this.highlightIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (navsPct.isEmpty) return;

    final double height = size.height;
    final double plotWidth = plotRight - plotLeft;

    // 1. 计算极值
    double maxVal = navsPct.reduce((a, b) => a > b ? a : b);
    double minVal = navsPct.reduce((a, b) => a < b ? a : b);
    for (final ma in [ma5Pct, ma10Pct, ma20Pct]) {
      if (ma.isNotEmpty) {
        final localMax = ma.reduce((a, b) => a > b ? a : b);
        final localMin = ma.reduce((a, b) => a < b ? a : b);
        if (localMax > maxVal) maxVal = localMax;
        if (localMin < minVal) minVal = localMin;
      }
    }

    final double range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;
    final double yMargin = range * 0.1;
    final double plotMax = maxVal + yMargin;
    final double plotMin = minVal - yMargin;
    final double plotRange = plotMax - plotMin;

    // 映射 Y 坐标函数
    double mapY(double val) {
      return height - ((val - plotMin) / plotRange * height);
    }

    // 2. 绘制背景网格与 Y 轴刻度
    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: isDark ? Colors.white38 : Colors.black38,
      fontSize: 9,
      fontFamily: 'Segoe UI',
    );

    const int yDivisions = 4;
    for (int i = 0; i <= yDivisions; i++) {
      final double val = plotMin + (plotRange * i / yDivisions);
      final double y = mapY(val);
      // 画横向网格线
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);

      // 绘制 Y 轴文本标签
      final String label = '${val.toThousand(precision: 1, showSign: true)}%';
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(plotLeft - textPainter.width - 5, y - textPainter.height / 2),
      );
    }

    // 绘制 X 轴时间标签（取 4 个等距点，避开 Y 轴区域）
    final int points = navsPct.length;
    final int xDivisions = math.min(4, points - 1);
    if (xDivisions > 0) {
      for (int i = 0; i <= xDivisions; i++) {
        final int idx = (i * (points - 1) / xDivisions).round();
        final double x = plotLeft + idx * (plotWidth / (points - 1));
        final date = dates[idx];

        final textPainter = TextPainter(
          text: TextSpan(text: date, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        // 第一个标签向右偏移，避免与 Y 轴标签重叠
        final double labelX = (i == 0)
            ? plotLeft + 5
            : (i == xDivisions)
                ? x - textPainter.width - 5
                : x - textPainter.width / 2;

        textPainter.paint(
          canvas,
          Offset(labelX, height - textPainter.height),
        );
      }
    }

    // 3. 绘制区间阴影渐变（填充区）
    final areaPath = Path()..moveTo(plotLeft, mapY(0.0));
    final double xStep = plotWidth / (points - 1);
    for (int i = 0; i < points; i++) {
      areaPath.lineTo(plotLeft + i * xStep, mapY(navsPct[i]));
    }
    areaPath.lineTo(plotLeft + (points - 1) * xStep, mapY(0.0));
    areaPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.blue.withValues(alpha: isDark ? 0.25 : 0.15),
          Colors.blue.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTRB(plotLeft, mapY(plotMax), plotLeft, mapY(plotMin)));
    canvas.drawPath(areaPath, fillPaint);

    // 4. 绘制折线
    void drawLine(List<double> values, Color color, double strokeWidth,
        {bool isMA = false}) {
      if (values.length < 2) return;
      final int end =
          (showEstimateDottedLine && isMA) ? values.length - 1 : values.length;
      if (end < 2) return;
      final path = Path()..moveTo(plotLeft, mapY(values.first));
      for (int i = 1; i < end; i++) {
        path.lineTo(plotLeft + i * xStep, mapY(values[i]));
      }
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;
      canvas.drawPath(path, linePaint);
    }

    // 画 MA 均线
    drawLine(ma5Pct, const Color(0xFF2ED573), 1.0, isMA: true);
    drawLine(ma10Pct, const Color(0xFFFFA502), 1.0, isMA: true);
    drawLine(ma20Pct, const Color(0xFF9B59B6), 1.0, isMA: true);

    // 画净值走势（最亮眼，并处理最新一段为虚线段）
    if (showEstimateDottedLine) {
      // 1. 实线画到倒数第二个点
      final path = Path()..moveTo(plotLeft, mapY(navsPct.first));
      for (int i = 1; i < points - 1; i++) {
        path.lineTo(plotLeft + i * xStep, mapY(navsPct[i]));
      }
      final linePaint = Paint()
        ..color = const fluent.Color(0xFF0097E6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true;
      canvas.drawPath(path, linePaint);

      // 2. 虚线从倒数第二个点画到最后一个点（估值模拟点）
      final double x1 = plotLeft + (points - 2) * xStep;
      final double y1 = mapY(navsPct[points - 2]);
      final double x2 = plotLeft + (points - 1) * xStep;
      final double y2 = mapY(navsPct[points - 1]);

      final dashPaint = Paint()
        ..color = const fluent.Color(0xFF0097E6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true;

      double dx = x2 - x1;
      double dy = y2 - y1;
      double distance = math.sqrt(dx * dx + dy * dy);
      const double dashLength = 4.0;
      const double spaceLength = 3.0;
      int dashCount = (distance / (dashLength + spaceLength)).floor();
      for (int i = 0; i < dashCount; i++) {
        double startPercent = (i * (dashLength + spaceLength)) / distance;
        double endPercent =
            (i * (dashLength + spaceLength) + dashLength) / distance;
        if (endPercent > 1.0) endPercent = 1.0;
        canvas.drawLine(
          Offset(x1 + dx * startPercent, y1 + dy * startPercent),
          Offset(x1 + dx * endPercent, y1 + dy * endPercent),
          dashPaint,
        );
      }
    } else {
      drawLine(navsPct, const fluent.Color(0xFF0097E6), 2.0);
    }

    // 5. 悬停点高亮
    if (highlightIdx != null && highlightIdx! >= 0 && highlightIdx! < points) {
      final double hX = plotLeft + highlightIdx! * xStep;

      // 净值高亮圆圈
      canvas.drawCircle(Offset(hX, mapY(navsPct[highlightIdx!])), 4.5,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(hX, mapY(navsPct[highlightIdx!])), 3.0,
          Paint()..color = const Color(0xFF0097E6));

      // 均线高亮（小圆点） - 如果高亮的是今日估算点，则不绘制均线的高亮小圆点
      final bool isEstimateHovered =
          showEstimateDottedLine && (highlightIdx == points - 1);
      if (!isEstimateHovered) {
        final List<List<double>> mas = [ma5Pct, ma10Pct, ma20Pct];
        final List<Color> colors = [
          const Color(0xFF2ED573),
          const Color(0xFFFFA502),
          const Color(0xFF9B59B6)
        ];
        for (int i = 0; i < mas.length; i++) {
          if (mas[i].isNotEmpty) {
            canvas.drawCircle(Offset(hX, mapY(mas[i][highlightIdx!])), 2.0,
                Paint()..color = colors[i]);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MainChartPainter oldDelegate) {
    return oldDelegate.highlightIdx != highlightIdx ||
        oldDelegate.navsPct != navsPct ||
        oldDelegate.isDark != isDark ||
        oldDelegate.showEstimateDottedLine != showEstimateDottedLine;
  }
}

class _IndicatorChartPainter extends CustomPainter {
  final String indicatorType;
  final List<double> valPct;
  final List<double> macdDiff;
  final List<double> macdDea;
  final List<double> macdBar;
  final List<double> kdjK;
  final List<double> kdjD;
  final List<double> kdjJ;
  final List<double> rsi6;
  final List<double> rsi12;
  final bool isDark;
  final double plotLeft;
  final double plotRight;
  final int? highlightIdx;

  _IndicatorChartPainter({
    required this.indicatorType,
    required this.valPct,
    required this.macdDiff,
    required this.macdDea,
    required this.macdBar,
    required this.kdjK,
    required this.kdjD,
    required this.kdjJ,
    required this.rsi6,
    required this.rsi12,
    required this.isDark,
    required this.plotLeft,
    required this.plotRight,
    this.highlightIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double height = size.height;
    final double plotWidth = plotRight - plotLeft;
    final int points = valPct.length;
    if (points == 0) return;
    final double xStep = plotWidth / (points - 1);

    double plotMin = 0.0;
    double plotMax = 100.0;

    // 动态确定 Y 轴极值
    if (indicatorType == '🌡️ 估值百分位温度带') {
      plotMin = 0.0;
      plotMax = 100.0;
    } else if (indicatorType == '📈 KDJ 超买超卖' ||
        indicatorType == '📉 RSI 强弱强弱') {
      plotMin = 0.0;
      plotMax = 100.0;
    } else if (indicatorType == '📊 MACD 强弱趋势') {
      double maxVal = 0.001;
      double minVal = -0.001;
      for (final list in [macdDiff, macdDea, macdBar]) {
        if (list.isNotEmpty) {
          final lMax = list.reduce((a, b) => a > b ? a : b);
          final lMin = list.reduce((a, b) => a < b ? a : b);
          if (lMax > maxVal) maxVal = lMax;
          if (lMin < minVal) minVal = lMin;
        }
      }
      final double rng = maxVal - minVal;
      plotMax = maxVal + rng * 0.1;
      plotMin = minVal - rng * 0.1;
    }

    final double plotRange = plotMax - plotMin == 0 ? 1.0 : plotMax - plotMin;
    double mapY(double val) {
      return height - ((val - plotMin) / plotRange * height);
    }

    // 1. 绘制网格背景线
    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: isDark ? Colors.white38 : Colors.black38,
      fontSize: 9,
      fontFamily: 'Segoe UI',
    );

    // 百分比类指标绘制 20%, 50%, 80% 警戒虚线
    if (indicatorType != '📊 MACD 强弱趋势') {
      final List<double> lines = [20.0, 50.0, 80.0];
      for (double val in lines) {
        final double y = mapY(val);
        // 绘制虚线
        final dashPaint = Paint()
          ..color =
              isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)
          ..strokeWidth = 1.0;
        double curX = plotLeft;
        while (curX < plotRight) {
          canvas.drawLine(Offset(curX, y), Offset(curX + 4, y), dashPaint);
          curX += 8;
        }

        // 标数值
        final textPainter = TextPainter(
          text: TextSpan(text: '${val.toInt()}%', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(plotLeft - textPainter.width - 5, y - textPainter.height / 2),
        );
      }
    } else {
      // MACD 画 0 轴线和 4 等分刻度
      const int div = 4;
      for (int i = 0; i <= div; i++) {
        final double val = plotMin + (plotRange * i / div);
        final double y = mapY(val);
        canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);

        final textPainter = TextPainter(
          text: TextSpan(text: val.toThousand(precision: 4), style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(plotLeft - textPainter.width - 5, y - textPainter.height / 2),
        );
      }
    }

    // 2. 绘制指标折线
    void drawLine(List<double> values, Color color, double strokeWidth) {
      if (values.length < 2) return;
      final path = Path()..moveTo(plotLeft, mapY(values.first));
      for (int i = 1; i < values.length; i++) {
        path.lineTo(plotLeft + i * xStep, mapY(values[i]));
      }
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;
      canvas.drawPath(path, linePaint);
    }

    if (indicatorType == '🌡️ 估值百分位温度带') {
      drawLine(valPct, const Color(0xFFFFA502), 1.5);
      // 额外高亮百分位温度带填充色
      final fillPath = Path()..moveTo(plotLeft, mapY(50.0));
      for (int i = 0; i < points; i++) {
        fillPath.lineTo(plotLeft + i * xStep, mapY(valPct[i]));
      }
      fillPath.lineTo(plotLeft + (points - 1) * xStep, mapY(50.0));
      fillPath.close();
      final fillPaint = Paint()
        ..color =
            const Color(0xFFFFA502).withValues(alpha: isDark ? 0.05 : 0.03);
      canvas.drawPath(fillPath, fillPaint);

      // 高亮圆点
      if (highlightIdx != null) {
        canvas.drawCircle(
            Offset(
                plotLeft + highlightIdx! * xStep, mapY(valPct[highlightIdx!])),
            3.5,
            Paint()..color = Colors.white);
        canvas.drawCircle(
            Offset(
                plotLeft + highlightIdx! * xStep, mapY(valPct[highlightIdx!])),
            2.0,
            Paint()..color = const Color(0xFFFFA502));
      }
    } else if (indicatorType == '📈 KDJ 超买超卖') {
      drawLine(kdjK, const Color(0xFF9B59B6), 1.2);
      drawLine(kdjD, const Color(0xFFF1C40F), 1.2);
      drawLine(kdjJ, const Color(0xFFE74C3C), 1.2);

      if (highlightIdx != null) {
        final double hX = plotLeft + highlightIdx! * xStep;
        canvas.drawCircle(Offset(hX, mapY(kdjK[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFF9B59B6));
        canvas.drawCircle(Offset(hX, mapY(kdjD[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFFF1C40F));
        canvas.drawCircle(Offset(hX, mapY(kdjJ[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFFE74C3C));
      }
    } else if (indicatorType == '📉 RSI 强弱强弱') {
      drawLine(rsi6, const Color(0xFFFD79A8), 1.2);
      drawLine(rsi12, const Color(0xFF00B894), 1.2);

      if (highlightIdx != null) {
        final double hX = plotLeft + highlightIdx! * xStep;
        canvas.drawCircle(Offset(hX, mapY(rsi6[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFFFD79A8));
        canvas.drawCircle(Offset(hX, mapY(rsi12[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFF00B894));
      }
    } else if (indicatorType == '📊 MACD 强弱趋势') {
      // 绘制 MACD Bar (正数红，负数绿)
      final double zeroY = mapY(0.0);
      final barPaintPositive = Paint()
        ..color = const Color(0xFFE74C3C)
        ..strokeWidth = 2.0;
      final barPaintNegative = Paint()
        ..color = const Color(0xFF2ECC71)
        ..strokeWidth = 2.0;

      for (int i = 0; i < points; i++) {
        final double x = plotLeft + i * xStep;
        final double y = mapY(macdBar[i]);
        canvas.drawLine(
          Offset(x, zeroY),
          Offset(x, y),
          macdBar[i] >= 0 ? barPaintPositive : barPaintNegative,
        );
      }

      // 绘制 DIFF & DEA 折线
      drawLine(macdDiff, const Color(0xFF00BCFF), 1.2);
      drawLine(macdDea, const Color(0xFFE67E22), 1.2);

      if (highlightIdx != null) {
        final double hX = plotLeft + highlightIdx! * xStep;
        canvas.drawCircle(Offset(hX, mapY(macdDiff[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFF00BCFF));
        canvas.drawCircle(Offset(hX, mapY(macdDea[highlightIdx!])), 2.0,
            Paint()..color = const Color(0xFFE67E22));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IndicatorChartPainter oldDelegate) {
    return oldDelegate.highlightIdx != highlightIdx ||
        oldDelegate.indicatorType != indicatorType ||
        oldDelegate.valPct != valPct ||
        oldDelegate.isDark != isDark;
  }
}

class _CrosshairPainter extends CustomPainter {
  final int highlightIdx;
  final int slicedLength;
  final double plotLeft;
  final double plotRight;
  final double topHeight;
  final double bottomHeight;
  final double gap;
  final bool isDark;
  // 主图数据，用于计算悬停点的 Y 像素坐标
  final List<double> navsPct;
  final List<double> ma5Pct;
  final List<double> ma10Pct;
  final List<double> ma20Pct;

  _CrosshairPainter({
    required this.highlightIdx,
    required this.slicedLength,
    required this.plotLeft,
    required this.plotRight,
    required this.topHeight,
    required this.bottomHeight,
    required this.gap,
    required this.isDark,
    required this.navsPct,
    required this.ma5Pct,
    required this.ma10Pct,
    required this.ma20Pct,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double plotWidth = plotRight - plotLeft;
    final double x = plotLeft + highlightIdx * (plotWidth / (slicedLength - 1));

    final linePaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black26
      ..strokeWidth = 1.0;

    // 绘制穿过主图和副图的十字连通垂直虚线
    double curY = 0.0;
    final double totalHeight = topHeight + gap + bottomHeight;
    while (curY < totalHeight) {
      canvas.drawLine(Offset(x, curY), Offset(x, curY + 4), linePaint);
      curY += 8;
    }

    // 绘制主图水平虚线（对应悬停净值点的 Y 坐标）
    if (navsPct.isNotEmpty &&
        highlightIdx >= 0 &&
        highlightIdx < navsPct.length) {
      // 复用 _MainChartPainter 的极值计算逻辑
      double maxVal = navsPct.reduce((a, b) => a > b ? a : b);
      double minVal = navsPct.reduce((a, b) => a < b ? a : b);
      for (final ma in [ma5Pct, ma10Pct, ma20Pct]) {
        if (ma.isNotEmpty) {
          final localMax = ma.reduce((a, b) => a > b ? a : b);
          final localMin = ma.reduce((a, b) => a < b ? a : b);
          if (localMax > maxVal) maxVal = localMax;
          if (localMin < minVal) minVal = localMin;
        }
      }
      final double range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;
      final double yMargin = range * 0.1;
      final double plotMax = maxVal + yMargin;
      final double plotMin = minVal - yMargin;
      final double plotRange = plotMax - plotMin;

      final double val = navsPct[highlightIdx];
      final double highlightY =
          topHeight - ((val - plotMin) / plotRange * topHeight);

      double curX = plotLeft;
      while (curX < plotRight) {
        canvas.drawLine(
            Offset(curX, highlightY), Offset(curX + 4, highlightY), linePaint);
        curX += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.highlightIdx != highlightIdx ||
        oldDelegate.slicedLength != slicedLength ||
        oldDelegate.isDark != isDark;
  }
}
