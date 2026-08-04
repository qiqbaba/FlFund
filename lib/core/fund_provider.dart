import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'config.dart';
import 'db_manager.dart';
import 'data_gateway.dart';
import 'utils/pinyin_search.dart';
import 'utils/safe_compute.dart';
import 'backtest_engine.dart';
import 'simulation_provider.dart';

class TrendDirection {
  static const sideways = 'sideways';
  static const rising = 'rising';
  static const falling = 'falling';
}

class FundUIModel {
  final String code;
  final String name;
  final String sector;
  bool isHeld;
  bool isSpecial;
  bool isPinned;
  double amount;
  double yieldRate;

  // 估值抓取结果
  String dwjz = '0.00';
  String gsz = '0.00';
  String gszzl = '0.00';
  String jzrq = '';
  String gztime = '暂无数据';
  String yestZdf = '0.00';

  // 抓取或计算异常信息
  String? errorMsg;

  // 计算结果
  Map<int, double> drops = {};
  Map<int, double> pcts = {};
  Map<String, dynamic>? optimalStrategy;

  // 估值百分位（由天天/蛋卷估值雷达数据融合回填）
  double? pePercentile;
  double? pbPercentile;

  // 全量历史百分位（用于周期榜单，反映完整周期位置）
  double? allHistoryPct;

  // === 周期榜单增强指标（2026-07改进） ===

  /// 趋势方向：基于短期/长期均线比较
  String trendDirection = TrendDirection.sideways;

  /// Z-score：当前净值偏离历史均值的标准差倍数（自适应波动率）
  double? zScore;

  /// 去趋势百分位：消除长期上涨偏倚后的百分位
  double? detrendedPct;

  /// 近1年（12个月）百分位
  double? year1Pct;

  /// 近3年（36个月）百分位
  double? year3Pct;

  // 历史数据缓存，用于趋势图
  List<double> navs = [];
  List<String> dates = [];

  // 缓存 120 日均线指标用于实时买入过滤
  double? closedMa120;
  double? sumOf119;

  // 缓存买入信号计算结果，防止因递归调用 `isBuySignalAt` 导致的指数级时间复杂度卡死问题
  final Map<int, bool> _buySignalCache = {};
  int? _lastCacheSignatureHash;

  FundUIModel({
    required this.code,
    required this.name,
    required this.sector,
    this.isHeld = false,
    this.isSpecial = false,
    this.isPinned = false,
    this.amount = 0.0,
    this.yieldRate = 0.0,
  });

  bool get isTodayValuation {
    if (gztime == '暂无数据' || gztime.isEmpty) return false;
    // 使用缓存的今日日期字符串，避免在表格高频渲染时每次都 new DateTime
    return gztime.contains(_cachedToday);
  }

  // 提取数据源的 getter
  String get source {
    if (gztime.contains('[') && gztime.contains(']')) {
      final start = gztime.indexOf('[') + 1;
      final end = gztime.indexOf(']');
      if (start < end) return gztime.substring(start, end);
    }
    return '';
  }

  // 计算日历史净值序列（由新到旧）中，指定位置往前的收益率标准差（波动率）
  double _calculateVolatility(int startIndex, int days, List<double> navList) {
    int effectiveDays = days;
    if (navList.length <= startIndex + effectiveDays + 1) {
      effectiveDays = navList.length - startIndex - 2;
    }
    if (effectiveDays < 3) return 0.01;

    final List<double> returns = [];
    double sum = 0.0;
    for (int i = startIndex; i < startIndex + effectiveDays; i++) {
      final double nextNav = navList[i + 1];
      if (nextNav > 0.0) {
        final double r = (navList[i] - nextNav) / nextNav;
        returns.add(r);
        sum += r;
      }
    }
    if (returns.isEmpty) return 0.01;
    final double mean = sum / returns.length;
    double variance = 0.0;
    for (final r in returns) {
      variance += (r - mean) * (r - mean);
    }
    return math.sqrt(variance / returns.length);
  }

  // 判断历史某天是否触发买入警报（核心指标校验，无网格限制）
  bool _isBasicBuySignalAt(int index) {
    if (optimalStrategy == null) return false;
    final navList = fullNavs;
    if (navList.length <= index) return false;

    // 1. 指数估值百分位过滤（由于历史百分位静态存储受限，仅在当天判断）
    if (index == 0) {
      final double peLimit =
          (optimalStrategy!['pe_percentile_limit'] as num?)?.toDouble() ?? 30.0;
      if (peLimit > 0.0 && pePercentile != null && pePercentile! > peLimit) {
        return false;
      }
      final double pbLimit =
          (optimalStrategy!['pb_percentile_limit'] as num?)?.toDouble() ?? 30.0;
      if (pbLimit > 0.0 && pbPercentile != null && pbPercentile! > pbLimit) {
        return false;
      }
    }

    // 2. 技术指标过滤（RSI/MACD）
    // 优化：直接从 navList 按索引范围读取，避免创建 sublist + reversed.toList() 临时列表
    final double rsiLimit =
        (optimalStrategy!['rsi_filter_limit'] as num?)?.toDouble() ?? 35.0;
    if (rsiLimit > 0.0) {
      // 从 index 到末尾，按时间从旧到新（navList 是从新到旧，所以需要反转读取）
      final int len = navList.length - index;
      if (len >= 14) {
        final rsiSeries =
            BacktestEngine.calculateRSIFromRange(navList, index, len);
        if (rsiSeries.isNotEmpty && rsiSeries.last >= rsiLimit) {
          return false;
        }
      }
    }
    final int macdEnabled = optimalStrategy!['macd_filter_enabled'] ?? 1;
    if (macdEnabled == 1) {
      final int len = navList.length - index;
      if (len >= 26) {
        final macdSeries =
            BacktestEngine.calculateMACDFromRange(navList, index, len);
        if (macdSeries.isNotEmpty && !macdSeries.last) {
          return false;
        }
      }
    }

    // 3. 价格下跌率过滤 (buy_drop)
    final double buyDrop = optimalStrategy!['buy_drop'] ?? 0.0;
    final double drop = getDropAt(index);
    if (drop == 0.0 || drop > -buyDrop) {
      return false;
    }

    // 4. 均线过滤
    int maPeriod = 120;
    double maEnvelopePct = 0.0;
    if (optimalStrategy!.containsKey('ma_period')) {
      maPeriod = optimalStrategy!['ma_period'] ?? 0;
      maEnvelopePct = optimalStrategy!['ma_envelope_pct'] ?? 0.0;
    }

    if (maPeriod <= 0) {
      return true; // 不启用均线过滤，直接触发
    }

    final double currentVal = navList[index];
    double targetMa;

    // 1. 动态自适应均线周期计算
    int adaptiveMaPeriod = maPeriod;
    if (navList.length > index + 40) {
      final double volShort = _calculateVolatility(index, 10, navList);
      final double volLong = _calculateVolatility(index, 60, navList);
      if (volLong > 0.0) {
        double ratio = volShort / volLong;
        ratio = ratio.clamp(0.5, 2.0);
        adaptiveMaPeriod = (maPeriod / ratio).round();
        final int minP = math.max(5, (maPeriod / 3).round());
        final int maxP = (maPeriod * 2).round();
        adaptiveMaPeriod = adaptiveMaPeriod.clamp(minP, maxP);
      }
    }

    // 2. 计算均线
    if (adaptiveMaPeriod == 120 && index == 0 && isTodayValuation) {
      // 120日均线当天计算复用原有的增量 sumOf119 缓存加速逻辑
      if (sumOf119 != null) {
        targetMa = (currentVal + sumOf119!) / 120.0;
      } else {
        targetMa = currentVal;
      }
    } else if (adaptiveMaPeriod == 120 && index == 0 && !isTodayValuation) {
      targetMa = closedMa120 ?? currentVal;
    } else {
      // 动态周期或非当天，使用历史列表动态求均值
      double sum = 0.0;
      int count = 0;
      for (int i = index;
          i < index + adaptiveMaPeriod && i < navList.length;
          i++) {
        sum += navList[i];
        count++;
      }
      targetMa = count > 0 ? sum / count : currentVal;
    }

    // 3. 引入偏离度宽限的双向比较判断（结合上限过滤，防止高位接飞刀）
    final double lowerLimit = targetMa * (1.0 - maEnvelopePct / 100.0);
    final double upperEnvelope = math.max(2.0, maEnvelopePct);
    final double upperLimit = targetMa * (1.0 + upperEnvelope / 100.0);
    return currentVal >= lowerLimit && currentVal <= upperLimit;
  }

  // 判断历史某天是否触发买入警报（包含网格加仓步进过滤）
  bool isBuySignalAt(int index) {
    final int currentSignatureHash = Object.hash(
      optimalStrategy?['buy_days'],
      optimalStrategy?['buy_drop'],
      optimalStrategy?['sell_x'],
      optimalStrategy?['ma_period'],
      optimalStrategy?['ma_envelope_pct'],
      optimalStrategy?['rsi_filter_limit'],
      optimalStrategy?['macd_filter_enabled'],
      optimalStrategy?['pe_percentile_limit'],
      optimalStrategy?['pb_percentile_limit'],
      pePercentile,
      pbPercentile,
      sumOf119,
      closedMa120,
      gztime,
      _cachedToday,
      fullNavs.length,
      fullNavs.isEmpty ? 0.0 : fullNavs.first,
    );
    if (_lastCacheSignatureHash != currentSignatureHash) {
      _buySignalCache.clear();
      _lastCacheSignatureHash = currentSignatureHash;
    }

    if (_buySignalCache.containsKey(index)) {
      return _buySignalCache[index]!;
    }

    final bool result = _isBuySignalAtInternal(index);
    _buySignalCache[index] = result;
    return result;
  }

  bool _isBuySignalAtInternal(int index) {
    if (!_isBasicBuySignalAt(index)) return false;

    // 引入网格步进加仓逻辑
    final double buyDrop = optimalStrategy!['buy_drop'] ?? 0.0;
    final double gridSpacingPct = (buyDrop * 0.3).clamp(1.0, 5.0);

    if (gridSpacingPct > 0.0) {
      final navList = fullNavs;
      int? prevBuyIdx;
      // 往更早的历史搜索最近一次触发"基础买入"的索引，最长回溯60个交易日
      final int searchLimit = math.min(index + 60, navList.length);
      for (int k = index + 1; k < searchLimit; k++) {
        if (isBuySignalAt(k)) {
          prevBuyIdx = k;
          break;
        }
      }

      if (prevBuyIdx != null) {
        // 校验在此期间是否已经平仓（触发卖出信号）
        bool hasSold = false;
        if (optimalStrategy!['sell_x'] != null) {
          final int encodedVal = optimalStrategy!['sell_x'];
          int sellX;
          double sellPct;
          if (encodedVal >= 100) {
            sellX = encodedVal ~/ 1000;
            sellPct = (encodedVal % 1000).toDouble();
          } else {
            sellX = encodedVal;
            sellPct = 5.0;
          }

          // 检查从 index 到 prevBuyIdx 之间（不含 prevBuyIdx 本身）是否有某天触发了卖出条件
          for (int j = index; j < prevBuyIdx; j++) {
            final int effectiveSellX = math.min(prevBuyIdx - j, sellX);
            if (effectiveSellX > 0) {
              final double currentNav = navList[j];
              final double baseNav = navList[j + effectiveSellX];
              if (baseNav > 0.0) {
                final double rise = (currentNav - baseNav) / baseNav * 100.0;
                if (rise >= sellPct) {
                  hasSold = true;
                  break;
                }
              }
            }
          }
        }

        if (!hasSold) {
          // 在没有平仓的情况下，当前价格必须相对于上一次买入价格下跌超过指定的网格比例，才允许发出新买入信号
          final double prevBuyNav = navList[prevBuyIdx];
          final double dropFromLast =
              (navList[index] - prevBuyNav) / prevBuyNav * 100.0;
          if (dropFromLast > -gridSpacingPct) {
            return false; // 跌幅不够，降噪过滤
          }
        }
      }
    }

    return true;
  }

  // 判断是否触发买入警报
  bool get isBuySignal => isBuySignalAt(0);

  // 计算历史特定索引处的回撤
  double getDropAt(int index) {
    if (optimalStrategy != null) {
      final int buyDays = optimalStrategy!['buy_days'] ?? 0;
      final navList = fullNavs;
      if (navList.length > index + buyDays && buyDays > 0) {
        double peak = 0.0;
        for (int i = index + 1; i <= index + buyDays; i++) {
          if (navList[i] > peak) {
            peak = navList[i];
          }
        }
        if (peak > 0.0) {
          return ((navList[index] - peak) / peak) * 100.0;
        }
      }
    }
    return 0.0;
  }

  double get currentDrop => getDropAt(0);

  // 寻找系统最近一次的最佳买入时点索引
  int? get lastSystemBuyIndex {
    final navList = fullNavs;
    final int searchRange = math.min(60, navList.length);
    for (int i = 0; i < searchRange; i++) {
      if (isBuySignalAt(i)) {
        return i;
      }
    }
    return null;
  }

  // 查找在最近 N 个交易日内是否有触发买入信号（不含今天），且在此期间（包含今天）未触发卖出信号
  int? getRecentBuyTriggerIndex({int maxDays = 3}) {
    final navList = fullNavs;
    if (navList.length <= 1) return null;

    int? recentBuyIdx;
    final int limit = math.min(maxDays + 1, navList.length);
    for (int i = 1; i < limit; i++) {
      if (isBuySignalAt(i)) {
        recentBuyIdx = i;
        break;
      }
    }

    if (recentBuyIdx == null) return null;

    // 检查从今天 (0) 到该买点之间 (不含买点本身)，是否触发过卖出信号
    bool hasSold = false;
    for (int j = 0; j < recentBuyIdx; j++) {
      if (isSellSignalAt(j)) {
        hasSold = true;
        break;
      }
    }

    if (hasSold) return null;
    return recentBuyIdx;
  }

  // 判断历史特定索引处是否触发卖出警报
  bool isSellSignalAt(int index) {
    if (optimalStrategy != null && optimalStrategy!['sell_x'] != null) {
      final int encodedVal = optimalStrategy!['sell_x'];
      int sellX;
      double sellPct;
      if (encodedVal >= 100) {
        sellX = encodedVal ~/ 1000;
        sellPct = (encodedVal % 1000).toDouble();
      } else {
        // 兼容旧格式：encodedVal 直接表示天数，涨幅阈值默认 5.0%
        sellX = encodedVal;
        sellPct = 5.0;
      }

      // 寻找在该 index 之后的最近一个买点（即从该天往更早的历史搜索最近一次触发买入的索引，最长回溯 60 个交易日）
      int? buyIdx;
      final navList = fullNavs;
      final int searchLimit = math.min(index + 60, navList.length);
      for (int i = index; i < searchLimit; i++) {
        if (isBuySignalAt(i)) {
          buyIdx = i;
          break;
        }
      }

      // 如果找到了系统买入点，限制卖出的对比基准最远只能回溯到该买入点
      int effectiveSellX = sellX;
      if (buyIdx != null) {
        effectiveSellX = math.min(buyIdx - index, sellX);
      }

      if (effectiveSellX > 0 && navList.length > index + effectiveSellX) {
        final double currentNav = navList[index];
        final double baseNav = navList[index + effectiveSellX];
        if (baseNav > 0) {
          final double rise = ((currentNav - baseNav) / baseNav) * 100.0;
          if (rise >= sellPct) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // 判断是否触发卖出警报
  bool get isSellSignal => isSellSignalAt(0);

  double get currentRise {
    if (optimalStrategy != null && optimalStrategy!['sell_x'] != null) {
      final int encodedVal = optimalStrategy!['sell_x'];
      int sellX;
      if (encodedVal >= 100) {
        sellX = encodedVal ~/ 1000;
      } else {
        sellX = encodedVal;
      }
      return getRiseOrDrop(sellX);
    }
    return 0.0;
  }

  // 完整的净值列表（含今日实时估值）
  List<double> get fullNavs {
    final double currentVal = isTodayValuation
        ? (double.tryParse(gsz) ?? (navs.isNotEmpty ? navs.first : 0.0))
        : (navs.isNotEmpty ? navs.first : 0.0);
    return isTodayValuation ? [currentVal, ...navs] : navs;
  }

  // 计算任意天数的涨跌幅
  double getRiseOrDrop(int days) {
    if (fullNavs.length > days && days > 0) {
      final double baseNav = fullNavs[days];
      if (baseNav > 0) {
        return ((fullNavs.first - baseNav) / baseNav) * 100.0;
      }
    }
    return 0.0;
  }

  /// 当日日期字符串缓存（每分钟失效一次）
  static String _todayDateStr = '';
  static DateTime _todayCacheTime = DateTime(2000);

  static String get _cachedToday {
    final now = DateTime.now();
    if (now.difference(_todayCacheTime).inMinutes >= 1) {
      _todayDateStr = now.toIso8601String().substring(0, 10);
      _todayCacheTime = now;
    }
    return _todayDateStr;
  }

  factory FundUIModel.fromInfo(FundInfo info) {
    return FundUIModel(
      code: info.code,
      name: info.name,
      sector: info.sector,
      isHeld: info.isHeld,
      isSpecial: info.isSpecial,
      isPinned: info.isPinned,
      amount: info.amount,
      yieldRate: info.yieldRate,
    );
  }
}

class FundProvider extends ChangeNotifier {
  // 黑名单：剔除没有场外联接基金的场内ETF（如跟踪中证能源指数的 159930、159945 等）
  static const Set<String> _blacklist = {
    '159930', // 能源ETF汇添富 (对应 000928 指数)
    '159945', // 能源ETF广发 (对应 000928 指数)
  };

  // 全局搜索框聚焦触发事件
  final _searchFocusController = StreamController<void>.broadcast();
  Stream<void> get searchFocusStream => _searchFocusController.stream;

  void triggerSearchFocus() {
    _searchFocusController.add(null);
  }

  @override
  void dispose() {
    _searchFocusController.close();
    super.dispose();
  }

  final Map<String, FundUIModel> myFunds = {};

  // 强周期榜单代表基金的独立数据容器（即使未关注也能计算百分位）
  final Map<String, FundUIModel> cycleFunds = {};

  static const List<String> cycleFundCodes = [
    '012725', // 畜牧养殖
    '008282', // 半导体存储
    '013275', // 煤炭能源
    '016708', // 有色稀金属
    '161725', // 白酒大消费
    '005224', // 基础建设水泥
    '161027', // 证券大金融（富国中证全指证券公司指数，8年数据）
    '014605', // 新能源光伏
    '163208', // 石油石化
    '019405', // 航运海运
    '160218', // 房地产
    '161726', // 医药生物
    '012551', // 面板LCD
  ];

  bool isRefreshing = false;

  List<String> _refreshErrors = [];
  List<String> get refreshErrors => _refreshErrors;

  Timer? _notifyThrottleTimer;

  void notifyListenersThrottled(
      {Duration duration = const Duration(milliseconds: 200)}) {
    if (_notifyThrottleTimer?.isActive ?? false) return;
    _notifyThrottleTimer = Timer(duration, () {
      notifyListeners();
    });
  }

  void clearRefreshErrors() {
    _refreshErrors.clear();
    notifyListeners();
  }

  int currentTabIndex = 0; // 默认选中持有基金 Tab
  String? selectedBacktestCode;

  void setCurrentTabIndex(int index) {
    currentTabIndex = index;
    notifyListeners();
  }

  void switchToBacktest(String code) {
    selectedBacktestCode = code;
    currentTabIndex = 6; // 策略中心
    notifyListeners();
  }

  void clearSelectedBacktestCode() {
    selectedBacktestCode = null;
    notifyListeners();
  }

  // 排行榜列表
  List<FundUIModel> topFunds = [];
  List<FundUIModel> botFunds = [];
  bool rankingLoaded = false;

  // 估值榜雷达数据
  List<Map<String, dynamic>> valuationList = [];
  bool valuationLoaded = false;

  // 1. 初始化自选基金列表
  void loadMyFunds() {
    final config = AppConfig();

    // 备份现有的估值和历史计算结果，避免被 clear() 丢弃
    final Map<String, FundUIModel> oldFunds = Map.from(myFunds);
    myFunds.clear();

    // 备份现有的周期基金计算结果，避免被 clear() 丢弃
    final Map<String, FundUIModel> oldCycleFunds = Map.from(cycleFunds);
    cycleFunds.clear();

    final List<FundUIModel> newlyAdded = [];
    final List<FundUIModel> newlyAddedCycle = [];

    config.fundsInfo.forEach((code, info) {
      final newModel = FundUIModel.fromInfo(info);
      final oldModel = oldFunds[code] ?? oldCycleFunds[code];
      if (oldModel != null) {
        // 复制之前已获取的实时估值和计算结果
        newModel.dwjz = oldModel.dwjz;
        newModel.gsz = oldModel.gsz;
        newModel.gszzl = oldModel.gszzl;
        newModel.jzrq = oldModel.jzrq;
        newModel.gztime = oldModel.gztime;
        newModel.yestZdf = oldModel.yestZdf;
        newModel.drops = Map.from(oldModel.drops);
        newModel.pcts = Map.from(oldModel.pcts);
        newModel.optimalStrategy = oldModel.optimalStrategy;
        newModel.navs = List.from(oldModel.navs);
        newModel.dates = List.from(oldModel.dates);
      } else {
        newlyAdded.add(newModel);
      }
      myFunds[code] = newModel;
    });

    for (final code in cycleFundCodes) {
      if (myFunds.containsKey(code)) {
        cycleFunds[code] = myFunds[code]!;
      } else {
        final oldModel = oldCycleFunds[code] ?? oldFunds[code];
        if (oldModel != null) {
          cycleFunds[code] = oldModel;
        } else {
          final name = PinyinSearch().getNameByCode(code);
          final newModel = FundUIModel(
            code: code,
            name: name != code ? name : '强周期代表基金',
            sector: '强周期监控',
          );
          newlyAddedCycle.add(newModel);
          cycleFunds[code] = newModel;
        }
      }
    }

    // 异步从本地数据库加载缓存的历史净值并计算历史指标（不请求网络，速度快）
    // 优化：仅对新加入的基金进行本地加载与计算，已有基金已完美继承，无需重复进行 DB 查询 and 计算
    _loadLocalHistoryAndCalculate([...newlyAdded, ...newlyAddedCycle]);

    // 异步更新所有基金的最优回测参数（防止策略中心更新了寻优参数而未同步）
    updateAllOptimalStrategies();

    notifyListeners();
  }

  // 异步从本地数据库加载缓存的历史净值并计算历史指标
  Future<void> _loadLocalHistoryAndCalculate(List<FundUIModel> targets) async {
    for (final model in targets) {
      await loadHistoryAndCalculateForModel(model, onlyLocal: true);
    }
    notifyListeners();
  }

  // 异步更新所有已加载基金的最优参数
  Future<void> updateAllOptimalStrategies() async {
    try {
      final db = FundHistoryDB();
      final allStrategies = await db.getAllOptimalStrategies();
      bool changed = false;

      bool updateModelStrategy(FundUIModel model) {
        final newStrategy = allStrategies[model.code];
        final bool hadStrategy = model.optimalStrategy != null;
        final bool hasNewStrategy = newStrategy != null;

        if (hadStrategy != hasNewStrategy) {
          model.optimalStrategy = newStrategy;
          return true;
        }

        if (hadStrategy && hasNewStrategy) {
          final s1 = model.optimalStrategy!;
          final s2 = newStrategy;
          final isDifferent = s1['buy_days'] != s2['buy_days'] ||
              s1['buy_drop'] != s2['buy_drop'] ||
              s1['target_profit'] != s2['target_profit'] ||
              s1['sell_x'] != s2['sell_x'];

          if (isDifferent) {
            model.optimalStrategy = newStrategy;
            return true;
          }
        }
        return false;
      }

      // 1. 更新自选基金中的基金最优策略
      for (final model in myFunds.values) {
        if (updateModelStrategy(model)) {
          changed = true;
        }
      }

      // 2. 更新排行榜领涨基金中的最优策略
      for (final model in topFunds) {
        if (updateModelStrategy(model)) {
          changed = true;
        }
      }

      // 3. 更新排行榜领跌基金中的最优策略
      for (final model in botFunds) {
        if (updateModelStrategy(model)) {
          changed = true;
        }
      }

      // 4. 更新估值雷达关联基金中的最优策略
      for (final item in valuationList) {
        final assoc = item['assocFund'];
        if (assoc is FundUIModel) {
          if (updateModelStrategy(assoc)) {
            changed = true;
          }
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('更新最优策略失败: $e');
    }
  }

  // 通用的加载历史净值并计算指标方法
  Future<void> loadHistoryAndCalculateForModel(FundUIModel model,
      {bool isForce = false, bool onlyLocal = false}) async {
    final db = FundHistoryDB();
    final gateway = FundDataGateway();
    final config = AppConfig();

    try {
      // 先尝试从本地数据库获取
      Map<String, dynamic>? history = await db.getHistory(model.code);
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      bool needApiUpdate = false;

      if (!onlyLocal) {
        if (history == null || history['dates'] == null) {
          needApiUpdate = true;
        } else {
          final String dMax = history['jzrq'] ?? '';
          final double updateTime =
              (history['update_time'] as num?)?.toDouble() ?? 0.0;
          final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

          if (dMax != todayStr) {
            // 如果最新净值日期不是今天，但距离上一次网络拉取（updateTime）不足 4 小时，则不重复发起网络请求
            if (nowTime - updateTime > 14400) {
              needApiUpdate = true;
            }
          }
        }
      }

      if ((needApiUpdate || isForce) && !onlyLocal) {
        // 从 API 抓取历史数据并写入数据库
        final onlineHis =
            await gateway.fetchHistory(model.code, name: model.name);
        if (onlineHis != null) {
          final List<double> navs = List<double>.from(onlineHis['navs'] ?? []);
          final List<String> dates =
              List<String>.from(onlineHis['dates'] ?? []);
          final List<double> ljjzs =
              List<double>.from(onlineHis['ljjzs'] ?? []);
          double? ma120Val;
          if (navs.length >= 120) {
            final maResult = await safeCompute(_calculateMaInIsolate, navs);
            ma120Val = maResult.closedMa120;
          }
          await db.saveHistory(model.code, onlineHis['jzrq'], navs, dates,
              ma120Val, ljjzs.length == navs.length ? ljjzs : null);

          // 自动代偿逻辑：若属于联接/新基金，则同时拉取并缓存对应的标的 ETF 历史净值
          final proxyCode = AppConfig.indexProxyMap[model.code];
          if (proxyCode != null) {
            try {
              final proxyHis = await gateway.fetchEtfHistory(proxyCode);
              if (proxyHis != null) {
                final List<double> pNavs =
                    List<double>.from(proxyHis['navs'] ?? []);
                final List<String> pDates =
                    List<String>.from(proxyHis['dates'] ?? []);
                double? pMa120Val;
                if (pNavs.length >= 120) {
                  final maResult =
                      await safeCompute(_calculateMaInIsolate, pNavs);
                  pMa120Val = maResult.closedMa120;
                }
                await db.saveHistory(
                    proxyCode, proxyHis['jzrq'], pNavs, pDates, pMa120Val);
              }
            } catch (e) {
              debugPrint('代偿标的历史净值同步失败 ($proxyCode): $e');
            }
          }

          history = await db.getHistory(model.code);
        }
      }

      if (history != null && history['navs'] != null) {
        final List<double> rawNavs = List<double>.from(history['navs'] ?? []);
        final List<String> rawDates = List<String>.from(history['dates'] ?? []);
        if (rawNavs.isNotEmpty) {
          model.navs = rawNavs;
          model.dates = rawDates;
          model.dwjz = rawNavs.first.toStringAsFixed(4);
          model.jzrq = history['jzrq'] ?? '';

          // 加载并计算 MA120/sumOf119 缓存（基于复权净值序列，与回测口径一致）
          if (rawNavs.length >= 120) {
            double sum120 = 0.0;
            for (int i = 0; i < 120; i++) {
              sum120 += rawNavs[i];
            }
            model.closedMa120 = sum120 / 120.0;
            model.sumOf119 = sum120 - rawNavs[119];
            // 回写与复权序列一致的 MA120 缓存（仅当与旧值不一致时）
            final double? dbMa120 = history['ma120'] as double?;
            if (dbMa120 == null ||
                (dbMa120 - model.closedMa120!).abs() > 1e-9) {
              await db.updateMa120(model.code, model.closedMa120!);
            }
          } else {
            model.closedMa120 = null;
            model.sumOf119 = null;
          }

          final double dwjzVal = double.tryParse(model.dwjz) ?? 0.0;
          final double gszVal = double.tryParse(model.gsz) ?? 0.0;
          final double gszzlVal = double.tryParse(model.gszzl) ?? 0.0;

          if (dwjzVal > 0) {
            if ((gszVal <= 0 || (gszVal - dwjzVal).abs() < 1e-5) && gszzlVal != 0.0) {
              model.gsz = (dwjzVal * (1.0 + gszzlVal / 100.0)).toStringAsFixed(4);
            } else if (gszVal > 0 && (gszVal - dwjzVal).abs() >= 1e-5 && gszzlVal == 0.0) {
              model.gszzl = ((gszVal - dwjzVal) / dwjzVal * 100.0).toStringAsFixed(2);
            } else if (model.gsz == '0.00' || model.gsz == '0') {
              model.gsz = model.dwjz;
            }
          }
          if ((model.gztime == '暂无数据' || model.gztime.isEmpty) &&
              model.jzrq.isNotEmpty) {
            model.gztime =
                '${model.jzrq} ${DateTime.now().toString().substring(11, 16)} [天天基金(手机)]';
          }

          if (rawNavs.length >= 2) {
            final double yestNav = rawNavs[0];
            final double prevNav = rawNavs[1];
            if (prevNav > 0) {
              model.yestZdf =
                  (((yestNav - prevNav) / prevNav) * 100).toStringAsFixed(2);
            } else {
              model.yestZdf = '0.00';
            }
          } else {
            model.yestZdf = '0.00';
          }

          final double currentVal;
          if (model.isTodayValuation) {
            final rawGsz = double.tryParse(model.gsz);
            if (model.source == '场内影子估值' &&
                rawGsz != null &&
                rawNavs.isNotEmpty) {
              // 影子 ETF 估值：gsz 是场内 ETF 价格，与基金历史净值量纲不同
              // 用最新实际净值 × (1 + gszzl%) 来估算今日基金估值
              final gszzlVal = double.tryParse(model.gszzl) ?? 0.0;
              currentVal = rawNavs.first * (1 + gszzlVal / 100.0);
            } else {
              currentVal = rawGsz ?? rawNavs.first;
            }
          } else {
            currentVal = rawNavs.first;
          }
          final List<double> fullNavs =
              model.isTodayValuation ? [currentVal, ...rawNavs] : rawNavs;

          // 跌幅计算
          model.drops.clear();
          for (final d in config.dropDays) {
            if (fullNavs.length > d) {
              final double baseNav = fullNavs[d];
              if (baseNav > 0) {
                model.drops[d] = ((currentVal - baseNav) / baseNav) * 100.0;
              }
            }
          }

          // 百分位计算 (采用统计百分位 Percentile Rank，与图表保持一致)
          model.pcts.clear();
          for (final m in config.percentileMonths) {
            final int days = m * 21;
            if (fullNavs.isNotEmpty) {
              final int limit = math.min(days + 1, fullNavs.length);
              int less = 0;
              int equal = 0;
              for (int i = 0; i < limit; i++) {
                final double x = fullNavs[i];
                if (x < currentVal) {
                  less++;
                } else if (x == currentVal) {
                  equal++;
                }
              }
              model.pcts[m] = (less + 0.5 * equal) / limit * 100.0;
            }
          }

          // 全量历史百分位（用于周期榜单，完整周期位置判断）
          if (fullNavs.length >= 2) {
            int less = 0;
            int equal = 0;
            for (int i = 0; i < fullNavs.length; i++) {
              final double x = fullNavs[i];
              if (x < currentVal) {
                less++;
              } else if (x == currentVal) {
                equal++;
              }
            }
            model.allHistoryPct =
                (less + 0.5 * equal) / fullNavs.length * 100.0;
          } else {
            model.allHistoryPct = null;
          }

          // === 周期榜单增强指标计算（2026-07改进） ===
          if (fullNavs.length >= 60) {
            // 1. 趋势方向：MA20 vs MA120
            final int maShort = math.min(20, fullNavs.length - 1);
            final int maLong = math.min(120, fullNavs.length - 1);
            double sumShort = 0, sumLong = 0;
            for (int i = 0; i < maShort; i++) {
              sumShort += fullNavs[i];
            }
            for (int i = 0; i < maLong; i++) {
              sumLong += fullNavs[i];
            }
            final double ma20 = sumShort / maShort;
            final double ma120 = sumLong / maLong;
            final double deviation = (ma20 - ma120) / ma120 * 100.0;
            if (deviation > 2.0) {
              model.trendDirection = TrendDirection.rising;
            } else if (deviation < -2.0) {
              model.trendDirection = TrendDirection.falling;
            } else {
              model.trendDirection = TrendDirection.sideways;
            }

            // 2. Z-score 与 3. 去趋势百分位：在对数净值(log-price)空间计算。
            // 基金净值近似复利增长，直接用原始净值做线性回归会系统性高/低估趋势、
            // 残差异方差；改用 log 净值可线性化指数增长，得到无偏去趋势残差与尺度不变的 Z 分数
            bool allPositive = currentVal > 0;
            for (int i = 0; i < fullNavs.length && allPositive; i++) {
              if (fullNavs[i] <= 0) allPositive = false;
            }
            final List<double> series =
                List<double>.filled(fullNavs.length, 0.0);
            for (int i = 0; i < fullNavs.length; i++) {
              series[i] = allPositive ? math.log(fullNavs[i]) : fullNavs[i];
            }
            final double curSeriesVal =
                allPositive ? math.log(currentVal) : currentVal;

            // 2. Z-score：偏离均值多少个标准差
            double sum = 0, sumSq = 0;
            for (int i = 0; i < series.length; i++) {
              sum += series[i];
            }
            final double mean = sum / series.length;
            for (int i = 0; i < series.length; i++) {
              final double diff = series[i] - mean;
              sumSq += diff * diff;
            }
            final double std = math.sqrt(sumSq / series.length);
            model.zScore = std > 0 ? (curSeriesVal - mean) / std : 0.0;

            // 3. 去趋势百分位：用线性回归拟合长期趋势，计算残差的百分位
            final int n = series.length;
            double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
            for (int i = 0; i < n; i++) {
              final double x = i.toDouble();
              final double y = series[i];
              sumX += x;
              sumY += y;
              sumXY += x * y;
              sumX2 += x * x;
            }
            final double slope =
                (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
            final double intercept = (sumY - slope * sumX) / n;

            // 当前值的趋势预期值 (index 0 = 最新)
            final double trendVal = intercept + slope * 0;
            // 计算所有残差
            final List<double> residuals = [];
            for (int i = 0; i < n; i++) {
              residuals.add(series[i] - (intercept + slope * i));
            }
            // 当前残差
            final double currentResidual = curSeriesVal - trendVal;
            // 残差百分位
            int resLess = 0, resEqual = 0;
            for (int i = 0; i < residuals.length; i++) {
              if (residuals[i] < currentResidual) {
                resLess++;
              } else if (residuals[i] == currentResidual) {
                resEqual++;
              }
            }
            model.detrendedPct =
                (resLess + 0.5 * resEqual) / residuals.length * 100.0;
          } else {
            model.trendDirection = TrendDirection.sideways;
            model.zScore = null;
            model.detrendedPct = null;
          }

          // 近1年/近3年百分位（从 pcts 映射）
          model.year1Pct = model.pcts[12];
          model.year3Pct = model.pcts[36];
        }
      }

      // 检索最优回测参数并设置
      final opt = await db.getOptimalStrategy(model.code);
      if (opt != null) {
        model.optimalStrategy = opt;
      }
    } catch (e) {
      final msg = '加载历史数据并计算失败 (${model.code}): $e';
      debugPrint(msg);
      model.errorMsg = msg;
    }
  }

  DateTime? _lastRefreshTime;

  bool _shouldAutoRefresh() {
    final now = DateTime.now();

    // 1. 检查是否在周一至周五 (DateTime.monday 为 1，DateTime.friday 为 5)
    if (now.weekday < DateTime.monday || now.weekday > DateTime.friday) {
      return false;
    }

    // 2. 检查交易时间段：09:30 - 11:30 和 13:00 - 15:00
    final currentMinutes = now.hour * 60 + now.minute;
    const range1Start = 9 * 60 + 30; // 09:30
    const range1End = 11 * 60 + 30; // 11:30
    const range2Start = 13 * 60; // 13:00
    const range2End = 15 * 60; // 15:00

    final inTradeHours =
        (currentMinutes >= range1Start && currentMinutes <= range1End) ||
            (currentMinutes >= range2Start && currentMinutes <= range2End);
    if (!inTradeHours) {
      return false;
    }

    // 3. 距离上一次刷新时间超过 5 分钟
    if (_lastRefreshTime != null) {
      if (now.difference(_lastRefreshTime!) < const Duration(minutes: 5)) {
        return false;
      }
    }

    return true;
  }

  // 限制最大并发数执行任务的辅助函数
  Future<List<T>> _runWithConcurrencyLimit<T>(
      List<Future<T> Function()> tasks, int limit) async {
    // 优化：使用队列模式，避免预分配大列表
    final results = List<T?>.filled(tasks.length, null);
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final int? current = synchronized(() {
          if (nextIndex >= tasks.length) return null;
          return nextIndex++;
        });
        if (current == null) break;

        final result = await tasks[current]();
        results[current] = result;
      }
    }

    // 错开并发 Worker 启动时间（相隔 50ms），防止微秒级高并发冲垮 HTTPS 握手
    final workers = List.generate(limit, (i) async {
      if (i > 0) {
        await Future.delayed(Duration(milliseconds: i * 50));
      }
      await worker();
    });
    await Future.wait(workers);
    return results.cast<T>();
  }

  // 简单的同步辅助方法（Dart 单线程，实际不需要锁）
  static T? synchronized<T>(T? Function() fn) => fn();

  // 2. 批量刷新自选基金实时估值与历史跌幅百分位
  Future<void> refreshAll({bool isForce = false}) async {
    if (isRefreshing) return;

    // 如果不是强制刷新，且不符合自动刷新条件，则直接跳过
    // 优化：如果是首次进入（_lastRefreshTime 为 null），则必须刷新一次
    // 此外，如果自选或持仓列表里有未初始化过的基金（gztime 为 '暂无数据'），为了避免一直显示0，也应该允许刷新
    final hasUninitialized =
        myFunds.values.any((model) => model.gztime == '暂无数据');
    if (!isForce &&
        !_shouldAutoRefresh() &&
        _lastRefreshTime != null &&
        !hasUninitialized) {
      return;
    }

    isRefreshing = true;
    final gateway = FundDataGateway();
    gateway.clearErrors();
    _refreshErrors.clear();
    notifyListeners();

    // 1. 整理自选基金以及周期榜单中尚未关注的基金列表
    final List<FundUIModel> fundList = [
      ...myFunds.values,
      ...cycleFunds.values.where((m) => !myFunds.containsKey(m.code)),
    ];

    // 2. 并行限流刷新：将任务组装为闭包，由并发调度器执行以控制网络并发数
    final List<Future<List<String>> Function()> tasks = [];

    for (int i = 0; i < fundList.length; i++) {
      final model = fundList[i];
      final preferredSourceIndex = (i % gateway.valuationSourceCount);

      tasks.add(() async {
        final localErrors = <String>[];
        model.errorMsg = null; // 每次刷新前重置
        try {
          // A. 抓取实时估值 (均匀轮询所有可用估值 API)
          final val = await gateway.fetchValuation(model.code,
              name: model.name,
              sector: model.sector,
              preferredSourceIndex: preferredSourceIndex);

          if (val != null) {
            model.gsz = val['gsz']?.toString() ?? model.gsz;
            model.gszzl =
                (val['gszzl']?.toString() ?? model.gszzl).replaceAll('%', '');
            model.jzrq = val['jzrq']?.toString() ?? model.jzrq;
            String srcName = val['source']?.toString() ?? '';
            if (srcName == 'EastMoneyGz') {
              srcName = '天天基金(网页)';
            } else if (srcName == 'EastMoneyMobileGz' ||
                srcName == 'EastMoneyMobile') {
              srcName = '天天基金(手机)';
            } else if (srcName == 'EastMoneyWeb') {
              srcName = '天天基金(历史)';
            } else if (srcName == 'TencentGz') {
              srcName = '腾讯财经';
            } else if (srcName == 'SinaGz') {
              srcName = '新浪财经';
            } else if (srcName == 'DanjuanGz') {
              srcName = '蛋卷基金';
            } else if (srcName == 'HowbuyGz') {
              srcName = '好买基金';
            } else if (srcName == '10JqkaGz') {
              srcName = '同花顺';
            } else if (srcName == 'ShadowETF') {
              srcName = '场内影子估值';
            }
            if (val['is_proxy'] == true) {
              srcName = '$srcName(代理)';
            }
            model.gztime = '${val['gztime']} [$srcName]';
          }

          // B. 加载历史与百分位计算 (包含三源降级逻辑)
          await loadHistoryAndCalculateForModel(model, isForce: isForce);
        } catch (e) {
          final msg = '刷新自选 ${model.code} 失败: $e';
          debugPrint(msg);
          model.errorMsg = msg;
          localErrors.add(msg);
        }
        return localErrors;
      });
    }

    // 限制最大并发数为 5 并发执行所有基金的刷新任务，避免冲击天天基金 SSL 握手与请求速率
    final results = await _runWithConcurrencyLimit(tasks, 5);

    // 合并所有局部错误列表
    _refreshErrors = results.expand((e) => e).toList();
    _lastRefreshTime = DateTime.now();
    isRefreshing = false;
    notifyListeners();

    // 触发模拟盘自动交易检测
    unawaited(SimulationProvider().checkAndExecute(myFunds.values.toList()));
  }

  // 3. 板块同质化过滤排行榜抓取（天天基金全市场盘中实时估值排行榜）
  Future<void> fetchRankings({bool isForce = false}) async {
    if (rankingLoaded && !isForce) return;
    try {
      final dio = FundDataGateway().dio;
      final headers = {
        'User-Agent': 'EMFund/6.5.5 (iPhone; iOS 16.6; Scale/3.00)',
        'Referer': 'https://fundmobapi.eastmoney.com',
      };

      // 天天基金官方全市场开放式基金盘中实时估值排行榜接口 (GSZZL 估算日涨跌幅排序)
      // 服务器单页硬编码限制最多返回30只，通过顺序拉取前5页（间隔100ms防并发拒绝）获取真正全市场前150只基金
      Future<List<Map<String, dynamic>>> fetchPagedValuations(
          String sort) async {
        try {
          final List<Map<String, dynamic>> combined = [];
          for (int p = 1; p <= 5; p++) {
            if (p > 1) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
            final res = await dio.get(
              'https://fundmobapi.eastmoney.com/FundMNewApi/FundMNValuationList?pageIndex=$p&pageSize=30&sortColumn=GSZZL&sort=$sort&deviceid=12345678901234567890123456789012&plat=Iphone&product=EFund&version=6.5.5',
              options: Options(headers: headers),
            );
            if (res.statusCode == 200) {
              final pageItems = _parseOfficialValuationResponse(res.data);
              combined.addAll(pageItems);
              if (pageItems.isEmpty) break;
            }
          }
          if (combined.isNotEmpty) return combined;
        } catch (e) {
          final errDetail = e is DioException
              ? (e.error?.toString() ?? e.message ?? e.toString())
              : e.toString();
          debugPrint('天天基金排行榜主接口异常 ($sort)，将启用东方财富降级备用源: $errDetail');
        }
        // 降级备用源：尝试东方财富全市场基金排行榜接口
        return _fetchRankingsFallbackEastMoney(sort);
      }

      final rawTop = await fetchPagedValuations('desc');
      await Future.delayed(const Duration(milliseconds: 200));
      final rawBot = await fetchPagedValuations('asc');

      final topMaps = _filterDistinctSectors(rawTop);
      final botMaps = _filterDistinctSectors(rawBot);

      topFunds = _convertToUIModels(topMaps);
      botFunds = _convertToUIModels(botMaps);

      // 异步并发加载这 20 个排行基金的历史数据
      final List<Future<void>> detailTasks = [];
      for (final model in [...topFunds, ...botFunds]) {
        detailTasks.add(loadHistoryAndCalculateForModel(model));
      }
      await Future.wait(detailTasks);

      rankingLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('获取排行榜失败: $e');
    }
  }

  /// 降级备用源：东方财富全市场基金实时排行榜（rankhandler.aspx）
  /// 天天基金主接口 FundMNValuationList 异常时启用，
  /// 返回按净值日涨跌幅排序的候选池作为兜底（无盘中实时估值，以单位净值与日涨跌幅替代）
  Future<List<Map<String, dynamic>>> _fetchRankingsFallbackEastMoney(
      String sort) async {
    final List<Map<String, dynamic>> result = [];
    try {
      final dio = FundDataGateway().dio;
      final st = (sort == 'asc') ? 'asc' : 'desc';
      // sc=rzdf 按日涨跌幅排序；pn=200 取足够候选以应对后续板块去重
      final url =
          'https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=kf&ft=all&rs=&gs=0&sc=rzdf&st=$st&pi=1&pn=200&dx=1';
      final response = await dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://fund.eastmoney.com/data/fundranking.html',
          },
        ),
      );
      if (response.statusCode == 200) {
        final text = response.data.toString();
        final todayStr = FundUIModel._cachedToday;
        // 返回格式：var rankData = {datas:["code,name,py,date,dwjz,ljjz,rzdf,...",...],...};
        final dataMatch = RegExp(r'datas:\[([^\]]*)\]').firstMatch(text);
        if (dataMatch != null) {
          final arrStr = dataMatch.group(1)!;
          // 每条记录为双引号包裹的逗号分隔字符串
          final recMatches = RegExp(r'"([^"]*)"').allMatches(arrStr);
          for (final m in recMatches) {
            final line = m.group(1);
            if (line == null || line.isEmpty) continue;
            final parts = line.split(',');
            if (parts.length < 7) continue;
            final code = parts[0].trim();
            if (code.isEmpty || code.length != 6) continue;
            final name = parts[1].trim();
            final jzrq = parts[3].trim();
            final dwjz = parts[4].trim();
            final gszzl = parts[6].trim(); // 日涨跌幅 rzdf
            result.add({
              'bzdm': code,
              'jjjc': name,
              'jzrq': jzrq.isNotEmpty ? jzrq : todayStr,
              'dwjz': dwjz.isNotEmpty ? dwjz : '0.00',
              'gsz': dwjz, // 降级源无实时估值，以单位净值兜底
              'gszzl': gszzl.isNotEmpty ? gszzl : '0.00',
              'gxrq': '$todayStr [东财降级]',
            });
          }
        }
      }
    } catch (e) {
      final errDetail = e is DioException
          ? (e.error?.toString() ?? e.message ?? e.toString())
          : e.toString();
      debugPrint('东方财富排行榜降级源请求失败: $errDetail');
    }
    return result;
  }

  List<FundUIModel> _convertToUIModels(List<Map<String, dynamic>> maps) {
    final List<FundUIModel> result = [];
    for (final item in maps) {
      final String code = item['code'] ?? '';
      final String name = item['name'] ?? '';
      final String sector = item['sector'] ?? '';
      final String rawGztime = item['gztime'] ?? '';
      final String gztimeVal = rawGztime.isNotEmpty
          ? (rawGztime.contains(':')
              ? rawGztime
              : '$rawGztime ${DateTime.now().toString().substring(11, 16)}')
          : '';
      final String gztimeWithSrc =
          gztimeVal.isNotEmpty ? '$gztimeVal [天天基金(估值)]' : '';

      // 如果自选里已经有，直接引用，保证状态完美同步
      if (myFunds.containsKey(code)) {
        final existing = myFunds[code]!;
        // 同步今日的实时估值数据到自选模型
        existing.gsz = item['gsz']?.toString() ?? existing.gsz;
        existing.gszzl =
            (item['gszzl']?.toString() ?? existing.gszzl).replaceAll('%', '');
        existing.dwjz = item['dwjz']?.toString() ?? existing.dwjz;
        existing.jzrq = item['jzrq']?.toString() ?? existing.jzrq;
        if (gztimeWithSrc.isNotEmpty) {
          existing.gztime = gztimeWithSrc;
        }
        result.add(existing);
      } else {
        final model = FundUIModel(
          code: code,
          name: name,
          sector: sector,
        );
        model.gsz = item['gsz']?.toString() ?? '0.00';
        model.gszzl = (item['gszzl']?.toString() ?? '0.00').replaceAll('%', '');
        model.dwjz = item['dwjz']?.toString() ?? '0.00';
        model.jzrq = item['jzrq']?.toString() ?? '';
        if (gztimeWithSrc.isNotEmpty) {
          model.gztime = gztimeWithSrc;
        }
        result.add(model);
      }
    }
    return result;
  }

  // 解析天天基金官方 FundMNValuationList API 响应 (全市场盘中实时估值榜)
  List<Map<String, dynamic>> _parseOfficialValuationResponse(dynamic data) {
    final List<Map<String, dynamic>> result = [];
    if (data == null || data is! Map) return result;

    try {
      final List datas = data['Datas'] ?? [];
      final todayStr = FundUIModel._cachedToday;

      for (final item in datas) {
        if (item is! Map) continue;
        final String code = item['FCODE']?.toString() ?? '';
        final String name = item['SHORTNAME']?.toString() ?? '';
        final String gsz = item['GSZ']?.toString() ?? '0.00';
        final String gszzl = item['GSZZL']?.toString() ?? '0.00';
        final String rawGztime = item['GZTIME']?.toString() ?? todayStr;

        if (code.isEmpty) continue;

        result.add({
          'bzdm': code,
          'jjjc': name,
          'jzrq':
              item['FSRQ']?.toString() ?? item['JZDB']?.toString() ?? todayStr,
          'dwjz': item['DWJZ']?.toString() ?? gsz,
          'gsz': gsz,
          'gszzl': gszzl,
          'gxrq': rawGztime,
        });
      }
    } catch (_) {}

    return result;
  }

  // 排行榜同质化板块去重
  List<Map<String, dynamic>> _filterDistinctSectors(List rawList) {
    final List<Map<String, dynamic>> result = [];
    final Set<String> seenSectors = {};
    final pinyinSearch = PinyinSearch();

    for (final item in rawList) {
      if (result.length >= 10) break;
      final String code = item['bzdm']?.toString() ?? '';

      // 过滤黑名单基金
      if (_blacklist.contains(code)) {
        continue;
      }

      // 板块清洗
      String name = pinyinSearch.getNameByCode(code);
      if (name == code && item['jjjc'] != null) {
        name = item['jjjc'].toString();
      }
      final String sector = pinyinSearch.getCleanSector(name, '其它');

      if (!seenSectors.contains(sector)) {
        seenSectors.add(sector);
        result.add({
          'code': code,
          'name': name,
          'sector': sector,
          'gsz': item['gsz']?.toString() ?? '0.00',
          'gszzl': (item['gszzl']?.toString() ?? '0.00').replaceAll('%', ''),
          'dwjz': item['dwjz']?.toString() ?? '0.00',
          'jzrq': item['jzrq']?.toString() ?? '',
          'gztime': item['gxrq']?.toString() ?? item['gzrq']?.toString() ?? '',
        });
      }
    }
    return result;
  }

  // 4. 指数估值榜与场外映射抓取
  Future<void> fetchValuations() async {
    if (valuationLoaded) return;
    try {
      final dio = FundDataGateway().dio;
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15',
        'Referer': 'https://unitmob.1234567.com.cn/'
      };

      // 拉取蛋卷估值数据以融合其 PB百分位 等数据
      final Map<String, dynamic> djMap = {};
      try {
        final djRes = await dio.get(
          'https://danjuanapp.com/djapi/index_eva/dj',
          options: Options(headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15',
          }),
        );
        if (djRes.statusCode == 200) {
          final List items = djRes.data['data']?['items'] ?? [];
          for (final djItem in items) {
            final rawCode = djItem['index_code']?.toString() ?? '';
            final match = RegExp(r'\d+').firstMatch(rawCode);
            if (match != null) {
              final cleanCode = match.group(0)!;
              djMap[cleanCode] = djItem;
            }
          }
        }
      } catch (e) {
        // 即使蛋卷接口获取失败，也不影响天天基金原始列表的加载
        debugPrint('Failed to fetch danjuan valuation: $e');
      }

      List datas = [];
      try {
        final res = await dio.get(
          'https://fundmobapi.eastmoney.com/FundMNewApi/FundMNIndexValuationList?pageIndex=1&pageSize=200&deviceid=Wap&plat=Wap&product=EFund&version=2.0.0',
          options: Options(headers: headers),
        );
        if (res.statusCode == 200 && res.data is Map) {
          datas = res.data['Datas'] ?? [];
        }
      } catch (e) {
        debugPrint('天天基金指数估值主接口异常，启用蛋卷全量列表降级备用源: $e');
      }

      final List<Map<String, dynamic>> temp = [];
      final Set<String> indexBlacklist = {
        '000928', // 800能源
        '930716', // CS物流
        '399602', // 中小成长
        '399660', // 中创EW
        '399337', // 深证民营
      };

      if (datas.isNotEmpty) {
        // 主源成功：基于天天基金列表组装
        for (final item in datas) {
          final indexCode = item['INDEXCODE']?.toString() ?? '';
          final match = RegExp(r'\d+').firstMatch(indexCode);
          final cleanCode = match != null ? match.group(0)! : indexCode;

          if (indexBlacklist.contains(cleanCode)) continue;

          final pe = item['PETTM']?.toString() ?? '--';
          final pb = item['PB']?.toString() ?? '--';
          final djItem = djMap[cleanCode];

          double pep = double.tryParse(item['PEP']?.toString() ?? '') ?? -1.0;
          if (pep < 0 && djItem != null) {
            pep = double.tryParse(djItem['pe_percentile']?.toString() ?? '') ??
                -1.0;
          }

          double pbp = double.tryParse(item['PBP']?.toString() ?? '') ?? -1.0;
          if (pbp < 0 && djItem != null) {
            pbp = double.tryParse(djItem['pb_percentile']?.toString() ?? '') ??
                -1.0;
          }

          if (pe != '--' || pb != '--') {
            String tag = '正常';
            final List<String> tags = [];
            if (pep >= 0.8) tags.add('PE高');
            if (pep > 0 && pep <= 0.2) tags.add('PE低');
            if (pbp >= 0.8) tags.add('PB高');
            if (pbp > 0 && pbp <= 0.2) tags.add('PB低');

            if (tags.isNotEmpty) tag = tags.join('/');

            temp.add({
              'code': indexCode,
              'name': item['INDEXNAME']?.toString() ?? '',
              'pe': pe,
              'pb': pb,
              'pe_percentile': pep >= 0 ? (pep * 100).toStringAsFixed(2) : '--',
              'pb_percentile': pbp >= 0 ? (pbp * 100).toStringAsFixed(2) : '--',
              'tag': tag,
            });
          }
        }
      } else if (djMap.isNotEmpty) {
        // 降级备用源：天天主接口失败时，直接使用蛋卷列表渲染
        for (final entry in djMap.entries) {
          final cleanCode = entry.key;
          if (indexBlacklist.contains(cleanCode)) continue;

          final djItem = entry.value as Map;
          final indexName = djItem['name']?.toString() ??
              djItem['index_name']?.toString() ??
              cleanCode;
          final pe = djItem['pe']?.toString() ?? '--';
          final pb = djItem['pb']?.toString() ?? '--';

          double pep =
              double.tryParse(djItem['pe_percentile']?.toString() ?? '') ??
                  -1.0;
          double pbp =
              double.tryParse(djItem['pb_percentile']?.toString() ?? '') ??
                  -1.0;

          String tag = '正常';
          final List<String> tags = [];
          if (pep >= 0.8) tags.add('PE高');
          if (pep > 0 && pep <= 0.2) tags.add('PE低');
          if (pbp >= 0.8) tags.add('PB高');
          if (pbp > 0 && pbp <= 0.2) tags.add('PB低');

          if (tags.isNotEmpty) tag = tags.join('/');

          temp.add({
            'code': cleanCode,
            'name': indexName,
            'pe': pe,
            'pb': pb,
            'pe_percentile': pep >= 0 ? (pep * 100).toStringAsFixed(2) : '--',
            'pb_percentile': pbp >= 0 ? (pbp * 100).toStringAsFixed(2) : '--',
            'tag': tag,
          });
        }
      }

      valuationList = temp;

      // 匹配关联基金并加载其详细数据（只针对有“低”或“高”估值标签的指数）
      final pinyinSearch = PinyinSearch();
      final gateway = FundDataGateway();
      final List<Future<void>> valuationDetailTasks = [];
      int valTaskIndex = 0;

      for (final item in valuationList) {
        final String indexCode = item['code'] ?? '';
        final String indexName = item['name'] ?? '';
        final String assocCode =
            pinyinSearch.findFundForIndex(indexCode, indexName);

        if (assocCode != indexCode) {
          final String assocName = pinyinSearch.getNameByCode(assocCode);
          FundUIModel fundModel;
          if (myFunds.containsKey(assocCode)) {
            fundModel = myFunds[assocCode]!;
          } else {
            final String tag = item['tag'] ?? '正常';
            if (tag.contains('低') || tag.contains('高')) {
              fundModel = FundUIModel(
                code: assocCode,
                name: assocName,
                sector: '估值雷达',
              );
            } else {
              continue;
            }
          }
          item['assocFund'] = fundModel;

          // 回填估值雷达融合的百分位数据
          final double? pep =
              double.tryParse(item['pe_percentile']?.toString() ?? '');
          final double? pbp =
              double.tryParse(item['pb_percentile']?.toString() ?? '');
          fundModel.pePercentile = (pep != null && pep >= 0) ? pep : null;
          fundModel.pbPercentile = (pbp != null && pbp >= 0) ? pbp : null;

          final String tag = item['tag'] ?? '正常';
          if (tag.contains('低') || tag.contains('高')) {
            final preferredSourceIndex =
                (valTaskIndex++ % gateway.valuationSourceCount);
            valuationDetailTasks.add(() async {
              await loadHistoryAndCalculateForModel(fundModel);
              try {
                final gateway = FundDataGateway();
                final val = await gateway.fetchValuation(fundModel.code,
                    name: fundModel.name,
                    sector: fundModel.sector,
                    preferredSourceIndex: preferredSourceIndex);
                if (val != null) {
                  fundModel.gsz = val['gsz']?.toString() ?? fundModel.gsz;
                  fundModel.gszzl =
                      (val['gszzl']?.toString() ?? fundModel.gszzl)
                          .replaceAll('%', '');
                  fundModel.jzrq = val['jzrq']?.toString() ?? fundModel.jzrq;
                  String srcName = val['source']?.toString() ?? '';
                  if (srcName == 'EastMoneyGz') {
                    srcName = '天天基金(网页)';
                  } else if (srcName == 'EastMoneyMobileGz' ||
                      srcName == 'EastMoneyMobile') {
                    srcName = '天天基金(手机)';
                  } else if (srcName == 'EastMoneyWeb') {
                    srcName = '天天基金(历史)';
                  } else if (srcName == 'TencentGz') {
                    srcName = '腾讯财经';
                  } else if (srcName == 'SinaGz') {
                    srcName = '新浪财经';
                  }
                  if (val['is_proxy'] == true) {
                    srcName = '$srcName(代理)';
                  }
                  fundModel.gztime = '${val['gztime']} [$srcName]';
                }
              } catch (e) {
                final fundName = fundModel.name.isNotEmpty ? '${fundModel.name} ' : '';
                debugPrint('获取关联估值失败 ${fundName}(${fundModel.code}): $e');
              }
            }());
          }
        }
      }

      if (valuationDetailTasks.isNotEmpty) {
        await Future.wait(valuationDetailTasks);
      }
      valuationLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('获取估值雷达失败: $e');
    }
  }

  // 手机端全局触发侧边栏菜单展开的回调
  VoidCallback? onOpenDrawer;
  void openDrawer() {
    onOpenDrawer?.call();
  }
}

class ColConfig {
  final String title;
  final double width;
  final bool alignLeft;
  final String? sortKey;

  ColConfig({
    required this.title,
    required this.width,
    this.alignLeft = false,
    this.sortKey,
  });
}

class FundSorter {
  static int compare(FundUIModel a, FundUIModel b, String key, bool ascending) {
    int result = 0;
    switch (key) {
      case 'pinned':
        final valA = a.isPinned ? 1 : 0;
        final valB = b.isPinned ? 1 : 0;
        result = valA.compareTo(valB);
        break;
      case 'special':
        final valA = a.isSpecial ? 1 : 0;
        final valB = b.isSpecial ? 1 : 0;
        result = valA.compareTo(valB);
        break;
      case 'code':
        result = a.code.compareTo(b.code);
        break;
      case 'name':
        result = a.name.compareTo(b.name);
        break;
      case 'sector':
        result = a.sector.compareTo(b.sector);
        break;
      case 'optimal':
        final hasA = a.optimalStrategy != null;
        final hasB = b.optimalStrategy != null;
        if (hasA && !hasB) return -1;
        if (!hasA && hasB) return 1;
        if (!hasA && !hasB) return 0;
        final dropA = a.optimalStrategy!['buy_drop'] ?? 0.0;
        final dropB = b.optimalStrategy!['buy_drop'] ?? 0.0;
        result = dropA.compareTo(dropB);
        break;
      case 'sell_optimal':
        final hasA =
            a.optimalStrategy != null && a.optimalStrategy!['sell_x'] != null;
        final hasB =
            b.optimalStrategy != null && b.optimalStrategy!['sell_x'] != null;
        if (hasA && !hasB) return -1;
        if (!hasA && hasB) return 1;
        if (!hasA && !hasB) return 0;
        final sellXA = a.optimalStrategy!['sell_x'] as int;
        final sellXB = b.optimalStrategy!['sell_x'] as int;
        result = sellXA.compareTo(sellXB);
        break;
      case 'holdAmount':
        result = a.yieldRate.compareTo(b.yieldRate);
        break;
      case 'yestZdf':
        final valA = double.tryParse(a.yestZdf) ?? 0.0;
        final valB = double.tryParse(b.yestZdf) ?? 0.0;
        result = valA.compareTo(valB);
        break;
      case 'todayProfit':
      case 'gszzl': // 兼容不同的排序关键字
        final changeA = double.tryParse(a.gszzl) ?? 0.0;
        final changeB = double.tryParse(b.gszzl) ?? 0.0;
        result = changeA.compareTo(changeB);
        break;
      case 'totalYield':
        final changeA = double.tryParse(a.gszzl) ?? 0.0;
        final changeB = double.tryParse(b.gszzl) ?? 0.0;
        final valA = a.yieldRate + changeA;
        final valB = b.yieldRate + changeB;
        result = valA.compareTo(valB);
        break;
      case 'src':
        result = a.source.compareTo(b.source);
        break;
      case 'gztime':
        String getTime(String timeStr) {
          if (timeStr.contains(' [')) {
            return timeStr.substring(0, timeStr.indexOf(' ['));
          }
          return timeStr;
        }
        result = getTime(a.gztime).compareTo(getTime(b.gztime));
        break;
      default:
        if (key.startsWith('drop_')) {
          final d = int.tryParse(key.substring(5)) ?? 0;
          final valA = a.drops[d] ?? 0.0;
          final valB = b.drops[d] ?? 0.0;
          result = valA.compareTo(valB);
        } else if (key.startsWith('percentile_')) {
          final m = int.tryParse(key.substring(11)) ?? 0;
          final valA = a.pcts[m] ?? -1.0;
          final valB = b.pcts[m] ?? -1.0;
          result = valA.compareTo(valB);
        }
        break;
    }
    return ascending ? result : -result;
  }
}

class MaCalculationResult {
  final double closedMa120;
  final double sumOf119;

  MaCalculationResult({
    required this.closedMa120,
    required this.sumOf119,
  });
}

// 独立的顶层 Isolate 运算函数，供 compute 调用
MaCalculationResult _calculateMaInIsolate(List<double> navs) {
  if (navs.length < 120) {
    return MaCalculationResult(closedMa120: 0.0, sumOf119: 0.0);
  }
  double sum120 = 0.0;
  for (int i = 0; i < 120; i++) {
    sum120 += navs[i];
  }
  return MaCalculationResult(
    closedMa120: sum120 / 120.0,
    sumOf119: sum120 - navs[119],
  );
}
