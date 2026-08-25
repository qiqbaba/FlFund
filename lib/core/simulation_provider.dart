import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'config.dart';
import 'fund_provider.dart';
import 'supabase_manager.dart';

class SimulatedPosition {
  final String code;
  final String name;
  double volume; // 持有份额
  double buyPrice; // 平均买入成本价 (含网格加仓合并)
  double currentPrice; // 最新估值/净值
  String buyDateStr; // 首次买入的核算净值日期 (用于到期平仓计算)
  int gridCount; // 已加仓次数 (网格加仓计数)
  double firstBuyPrice; // 首次买入价 (止损基准，网格加仓不钝化止损)
  double lastBuyPrice; // 最近一次买入价 (网格步进基准，与回测 lastBuyPrice 对齐)
  double maxHoldNav; // 持仓期间最高净值 (追踪止盈)

  SimulatedPosition({
    required this.code,
    required this.name,
    required this.volume,
    required this.buyPrice,
    required this.currentPrice,
    this.buyDateStr = '',
    this.gridCount = 0,
    double? firstBuyPrice,
    double? lastBuyPrice,
    double? maxHoldNav,
  })  : firstBuyPrice = firstBuyPrice ?? buyPrice,
        lastBuyPrice = lastBuyPrice ?? buyPrice,
        maxHoldNav = maxHoldNav ?? currentPrice;

  double get amount {
    final v = volume * currentPrice;
    return v.isFinite ? v : 0.0;
  }

  double get totalCost {
    final v = volume * buyPrice;
    return v.isFinite ? v : 0.0;
  }

  double get profit {
    final v = amount - totalCost;
    return v.isFinite ? v : 0.0;
  }

  double get profitRate {
    final tc = totalCost;
    if (tc <= 0) return 0.0;
    final v = (profit / tc) * 100;
    return v.isFinite ? v : 0.0;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'volume': volume,
        'buyPrice': buyPrice,
        'currentPrice': currentPrice,
        'buyDateStr': buyDateStr,
        'gridCount': gridCount,
        'firstBuyPrice': firstBuyPrice,
        'lastBuyPrice': lastBuyPrice,
        'maxHoldNav': maxHoldNav,
      };

  factory SimulatedPosition.fromJson(Map<String, dynamic> json) =>
      SimulatedPosition(
        code: json['code'] ?? '',
        name: json['name'] ?? '',
        volume: (json['volume'] as num).toDouble(),
        buyPrice: (json['buyPrice'] as num).toDouble(),
        currentPrice: (json['currentPrice'] as num).toDouble(),
        buyDateStr: json['buyDateStr'] ?? '',
        gridCount: json['gridCount'] ?? 0,
        firstBuyPrice: (json['firstBuyPrice'] as num?)?.toDouble(),
        lastBuyPrice: (json['lastBuyPrice'] as num?)?.toDouble(),
        maxHoldNav: (json['maxHoldNav'] as num?)?.toDouble(),
      );
}

class SimulatedTransaction {
  final String id;
  final String code;
  final String name;
  final String type; // 'BUY' / 'SELL'
  final double price;
  final double volume;
  final double amount;
  final DateTime dateTime; // 操作系统时间
  final String dateTimeStr; // 成交的核算净值日期，比如 "2026-07-03"
  final String signalReason;

  SimulatedTransaction({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.price,
    required this.volume,
    required this.amount,
    required this.dateTime,
    required this.dateTimeStr,
    this.signalReason = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'type': type,
        'price': price,
        'volume': volume,
        'amount': amount,
        'dateTime': dateTime.toIso8601String(),
        'dateTimeStr': dateTimeStr,
        'signalReason': signalReason,
      };

  factory SimulatedTransaction.fromJson(Map<String, dynamic> json) =>
      SimulatedTransaction(
        id: json['id'] ?? '',
        code: json['code'] ?? '',
        name: json['name'] ?? '',
        type: json['type'] ?? '',
        price: (json['price'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
        amount: (json['amount'] as num).toDouble(),
        dateTime: DateTime.parse(json['dateTime']),
        dateTimeStr: json['dateTimeStr'] ?? '',
        signalReason: json['signalReason'] ?? '',
      );
}

class SimulationProvider extends ChangeNotifier {
  static final SimulationProvider _instance = SimulationProvider._internal();
  factory SimulationProvider() => _instance;
  SimulationProvider._internal();

  bool _isLoaded = false;

  // 并发控制锁，防止 checkAndExecute 被重入
  bool _isExecuting = false;

  double initialBalance = 1000000.0;
  double availableBalance = 1000000.0;
  double defaultBuyAmount = 10000.0;
  bool isAutoTradeEnabled = true;

  // === 风控与仓位管理参数 ===
  static const int maxTotalPositions = 25; // 全局最大同时持仓数
  static const int maxDailyBuys = 5; // 单日最大买入笔数
  static const int maxGridCount = 3; // 单只基金最大网格加仓次数
  static const double stopLossPct = -15.0; // 固定止损线 (-15%)
  static const int defaultHoldMax = 90; // 默认最大持仓天数 (无策略参数时的回退值)
  static const double defaultTargetProfit = 8.0; // 默认止盈线 (无策略参数时的回退值)
  static const double defaultTrailingDropPct = 2.0; // 默认追踪止盈回撤阈值
  static const double defaultSlippagePct = 0.0; // 默认滑点 (与回测引擎默认一致)
  static const double defaultPurchaseFeePct = 0.0; // 默认申购费率
  static const double defaultShortHoldPenaltyPct = 1.5; // 默认短持惩罚费率 (C类<7天)
  static const int defaultShortHoldDays = 7; // 默认短持惩罚天数

  Map<String, SimulatedPosition> positions = {};
  List<SimulatedTransaction> transactions = [];

  // 获取总资产 = 可用现金 + 所有持仓市值
  double get totalAssets {
    double posValue = positions.values.fold(0.0, (sum, pos) {
      final amt = pos.amount;
      return sum + (amt.isFinite ? amt : 0.0);
    });
    final v = availableBalance + posValue;
    return v.isFinite ? v : 0.0;
  }

  // 获取总盈亏
  double get totalProfit {
    final v = totalAssets - initialBalance;
    return v.isFinite ? v : 0.0;
  }

  // 获取总收益率
  double get totalProfitRate {
    if (initialBalance <= 0) return 0.0;
    final v = (totalProfit / initialBalance) * 100;
    return v.isFinite ? v : 0.0;
  }

  // 获取持仓市值
  double get totalPositionValue {
    return positions.values.fold(0.0, (sum, pos) {
      final amt = pos.amount;
      return sum + (amt.isFinite ? amt : 0.0);
    });
  }

  /// 获取当前用户标识，用于隔离模拟盘数据
  /// 已登录用户用 userId，未登录返回 null
  String? get _userId => SupabaseManager().currentUserId;

  /// 获取模拟盘文件所在目录
  Future<Directory> _getSimDir() async {
    if (!kIsWeb && Platform.isWindows) {
      // Windows 下优先使用当前工作目录
      return Directory(Directory.current.path);
    } else {
      // 安卓沙盒路径
      final dir = await getApplicationDocumentsDirectory();
      return dir;
    }
  }

  /// 获取当前用户的模拟盘文件路径
  /// 已登录 → simulated_portfolio_{userId}.json
  /// 未登录 → simulated_portfolio.json
  Future<File> _getSimFile() async {
    final dir = await _getSimDir();
    final userId = _userId;
    if (userId != null) {
      return File(path.join(dir.path, 'simulated_portfolio_$userId.json'));
    } else {
      return File(path.join(dir.path, 'simulated_portfolio.json'));
    }
  }

  // 加载数据
  Future<void> loadSimData() async {
    if (_isLoaded) return;
    try {
      final file = await _getSimFile();
      if (await file.exists()) {
        final content = await file.readAsString(encoding: utf8);
        final Map<String, dynamic> jsonMap = json.decode(content);

        initialBalance =
            (jsonMap['initialBalance'] as num?)?.toDouble() ?? 1000000.0;
        availableBalance =
            (jsonMap['availableBalance'] as num?)?.toDouble() ?? 1000000.0;
        defaultBuyAmount =
            (jsonMap['defaultBuyAmount'] as num?)?.toDouble() ?? 10000.0;
        isAutoTradeEnabled = jsonMap['isAutoTradeEnabled'] ?? true;

        final posMap = jsonMap['positions'] as Map<String, dynamic>? ?? {};
        positions = posMap
            .map((key, val) => MapEntry(key, SimulatedPosition.fromJson(val)));

        final txList = jsonMap['transactions'] as List<dynamic>? ?? [];
        transactions =
            txList.map((val) => SimulatedTransaction.fromJson(val)).toList();
      }
      _isLoaded = true;

      // 防御性校验：确保所有数值为有限值，防止 Infinity/NaN 污染
      _sanitizeValues();

      notifyListeners();
    } catch (e) {
      debugPrint('加载模拟盘数据失败: $e');
    }
  }

  // 保存数据
  Future<void> saveSimData() async {
    // 保存前防御性清理，防止损坏数据被写入磁盘
    _sanitizeValues();

    try {
      final file = await _getSimFile();
      final Map<String, dynamic> jsonMap = {
        'initialBalance': initialBalance,
        'availableBalance': availableBalance,
        'defaultBuyAmount': defaultBuyAmount,
        'isAutoTradeEnabled': isAutoTradeEnabled,
        'positions': positions.map((key, val) => MapEntry(key, val.toJson())),
        'transactions': transactions.map((val) => val.toJson()).toList(),
      };
      const encoder = JsonEncoder.withIndent('    ');
      await file.writeAsString(encoder.convert(jsonMap), encoding: utf8);
    } catch (e) {
      debugPrint('保存模拟盘数据失败: $e');
    }
  }

  // 重置账户
  Future<void> resetAccount(double initBal) async {
    initialBalance = initBal;
    availableBalance = initBal;
    positions.clear();
    transactions.clear();
    await saveSimData();
    notifyListeners();
  }

  // 更改单笔买入金额
  Future<void> updateDefaultBuyAmount(double amount) async {
    defaultBuyAmount = amount;
    await saveSimData();
    notifyListeners();
  }

  // 切换自动买卖开关
  Future<void> toggleAutoTrade(bool value) async {
    isAutoTradeEnabled = value;
    await saveSimData();
    notifyListeners();
  }

  /// 用户切换后重载模拟盘数据（登录/登出时调用）
  Future<void> reloadSimData() async {
    _isLoaded = false;
    await loadSimData();
  }

  // 判断是否处于交易日下午两点四十至三点之间 (尾盘申赎时间段)
  bool isTailTradeTime() {
    final now = DateTime.now();
    // 1. 必须是工作日周一至周五 (weekday 在 1 到 5 之间)
    if (now.weekday < DateTime.monday || now.weekday > DateTime.friday) {
      return false;
    }
    // 2. 时间范围在 14:40 - 15:00 之间 (以分钟为单位判断)
    final minutes = now.hour * 60 + now.minute;
    const startMinutes = 14 * 60 + 40; // 14:40
    const endMinutes = 15 * 60; // 15:00
    return minutes >= startMinutes && minutes < endMinutes;
  }

  // 信号检测与交易执行
  Future<void> checkAndExecute(List<FundUIModel> funds) async {
    if (!isAutoTradeEnabled) return;

    // 并发重入保护：防止多次 refreshAll 或手动触发同时执行
    if (_isExecuting) {
      debugPrint('[Simulation] 检测到并发重入，跳过本次执行');
      return;
    }
    _isExecuting = true;

    try {
      await _checkAndExecuteInternal(funds);
    } finally {
      _isExecuting = false;
    }
  }

  Future<void> _checkAndExecuteInternal(List<FundUIModel> funds) async {
    await loadSimData(); // 保证数据已加载

    bool changed = false;
    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);
    final bool tailTrade = isTailTradeTime();
    int dailyBuyCount = 0; // 当日买入计数器
    final appConfig = AppConfig();

    // 统计当日已发生的买入笔数（防止重启后重复计数）
    for (final tx in transactions) {
      if (tx.type == 'BUY' && tx.dateTimeStr == todayStr) {
        dailyBuyCount++;
      }
    }

    // 1. 静默同步当前持仓中基金的最新净值/估值
    for (final pos in positions.values) {
      final matchingFund = funds.firstWhere((f) => f.code == pos.code,
          orElse: () => FundUIModel(code: '', name: '', sector: ''));
      if (matchingFund.code.isNotEmpty) {
        double? currentPrice;
        if (tailTrade && matchingFund.isTodayValuation) {
          currentPrice = matchingFund.estimatedNav;
        }
        currentPrice ??=
            matchingFund.navs.isNotEmpty ? matchingFund.navs.first : null;

        if (currentPrice != null &&
            currentPrice > 0.0 &&
            currentPrice.isFinite) {
          if (pos.currentPrice != currentPrice) {
            pos.currentPrice = currentPrice;
            changed = true;
          }
          if (currentPrice > pos.maxHoldNav) {
            pos.maxHoldNav = currentPrice;
            changed = true;
          }
        }
      }
    }

    // 2. 遍历基金池检查信号
    for (final fund in funds) {
      final code = fund.code;
      final name = fund.name;

      // 确定研判的索引、结算价格、结算净值日期和信号原因标签
      int evalIndex;
      double price;
      String tradeDateStr;
      String signalReasonSuffix;

      if (tailTrade && fund.isTodayValuation) {
        evalIndex = 0;
        // 修复：使用修正估值（最新确认净值×当日估值涨跌幅），避免估值与净值
        // 基准不一致导致信号错位；估值不可用时回退到最新确认净值
        price = fund.estimatedNav ?? (fund.navs.isNotEmpty ? fund.navs.first : 0.0);
        tradeDateStr = todayStr;
        signalReasonSuffix = ' (尾盘估值信号)';
      } else {
        evalIndex = fund.isTodayValuation ? 1 : 0;
        price = fund.navs.isNotEmpty ? fund.navs.first : 0.0;
        tradeDateStr = fund.dates.isNotEmpty ? fund.dates.first : todayStr;
        signalReasonSuffix = ' (收盘净值信号)';
      }

      if (price <= 0.0 || !price.isFinite) continue;

      final bool isHeld = positions.containsKey(code);

      // ========== A. 卖出判断（优先级高于买入，且同日互斥） ==========
      if (isHeld) {
        final pos = positions[code]!;
        // 盈亏基于合并平均成本（与回测网格加仓后口径一致）
        final double profitRate = pos.buyPrice > 0
            ? ((price - pos.buyPrice) / pos.buyPrice) * 100.0
            : 0.0;

        // T+1 限制：同一日历日内刚买入的基金不能在当天卖出。
        // 修复：改用操作系统日历日比较，避免“尾盘买入后次日非尾盘时段
        // 净值日期仍为买入日”时被误判为同日而延误卖出。
        final lastBuyTx = transactions.firstWhere(
            (tx) => tx.code == code && tx.type == 'BUY',
            orElse: () => SimulatedTransaction(
                id: '',
                code: '',
                name: '',
                type: '',
                price: 0,
                volume: 0,
                amount: 0,
                dateTime: DateTime(2000),
                dateTimeStr: ''));
        final String todayCalStr =
            now.toIso8601String().substring(0, 10);
        final bool isBoughtToday =
            lastBuyTx.id.isNotEmpty &&
                lastBuyTx.dateTime.toIso8601String().substring(0, 10) ==
                    todayCalStr;

        // 防止同结算日内重复卖出
        final bool alreadySoldOnDate = transactions.any((tx) =>
            tx.code == code &&
            tx.type == 'SELL' &&
            tx.dateTimeStr == tradeDateStr);

        if (!isBoughtToday && !alreadySoldOnDate) {
          String? sellReason;

          // 策略参数读取（无策略时使用与回测引擎一致的默认值）
          final double stopLoss =
              (fund.optimalStrategy?['stop_loss_pct'] as num?)?.toDouble() ??
                  15.0;
          final double trailingDrop =
              (fund.optimalStrategy?['trailing_drop_pct'] as num?)?.toDouble() ??
                  defaultTrailingDropPct;
          final double trailingActivate =
              (fund.optimalStrategy?['trailing_activate_pct'] as num?)
                      ?.toDouble() ??
                  trailingDrop;
          final double slippagePct =
              (fund.optimalStrategy?['slippage_pct'] as num?)?.toDouble() ??
                  defaultSlippagePct;
          final double shortHoldPenalty =
              (fund.optimalStrategy?['short_hold_penalty_pct'] as num?)
                      ?.toDouble() ??
                  (fund.isExchangeTraded ? 0.0 : defaultShortHoldPenaltyPct);
          final int shortHoldDays =
              (fund.optimalStrategy?['short_hold_days'] as num?)?.toInt() ??
                  (fund.isExchangeTraded ? 0 : defaultShortHoldDays);

          // 更新持仓期最高净值（追踪止盈基准）
          if (price > pos.maxHoldNav) {
            pos.maxHoldNav = price;
            changed = true;
          }

          int holdDays = 0;
          if (pos.buyDateStr.isNotEmpty) {
            try {
              final buyDate = DateTime.parse(pos.buyDateStr);
              final tradeDate = DateTime.parse(tradeDateStr);
              holdDays = tradeDate.difference(buyDate).inDays;
            } catch (_) {}
          }

          // I. 固定止损平仓（基于首次买入价，网格加仓摊低均价不钝化止损）
          final double lossFromFirst = pos.firstBuyPrice > 0
              ? ((price - pos.firstBuyPrice) / pos.firstBuyPrice) * 100.0
              : 0.0;
          if (lossFromFirst <= -stopLoss) {
            sellReason =
                '止损平仓(${lossFromFirst.toStringAsFixed(1)}%≤-${stopLoss.toStringAsFixed(0)}%)$signalReasonSuffix';
          }

          // II. 固定目标止盈平仓（持有期少于 shortHoldDays 天包含惩罚费率，与回测对齐）
          if (sellReason == null) {
            final double targetProfit =
                (fund.optimalStrategy?['target_profit'] as num?)?.toDouble() ??
                    defaultTargetProfit;
            final double requiredProfit = (holdDays < shortHoldDays)
                ? targetProfit + shortHoldPenalty
                : targetProfit;
            if (profitRate >= requiredProfit) {
              sellReason =
                  '止盈平仓(${profitRate.toStringAsFixed(1)}%≥${requiredProfit.toStringAsFixed(1)}%)$signalReasonSuffix';
            }
          }

          // III. 到期平仓（按交易日计算持仓天数，与回测引擎对齐）
          if (sellReason == null && pos.buyDateStr.isNotEmpty) {
            final int holdMax =
                fund.optimalStrategy?['hold_max'] ?? defaultHoldMax;
            try {
              int tradeHoldDays = 0;
              final int buyDateIdx = fund.dates.indexOf(pos.buyDateStr);
              final int curDateIdx = fund.dates.indexOf(tradeDateStr);
              if (buyDateIdx >= 0 && curDateIdx >= 0 && buyDateIdx >= curDateIdx) {
                tradeHoldDays = buyDateIdx - curDateIdx;
              } else if (buyDateIdx >= 0 && curDateIdx == -1 && fund.isTodayValuation) {
                // 当日为盘中估值时，比昨日收盘多 1 个交易日
                tradeHoldDays = buyDateIdx + 1;
              } else {
                // 兜底：若未在历史净值中找到对应日期，按自然日的工作日比例（5/7）折算为交易日
                final buyDate = DateTime.parse(pos.buyDateStr);
                final tradeDate = DateTime.parse(tradeDateStr);
                final int calendarDays = tradeDate.difference(buyDate).inDays;
                tradeHoldDays = (calendarDays * 5 / 7).round();
              }
              if (tradeHoldDays >= holdMax) {
                sellReason =
                    '到期平仓(持仓$tradeHoldDays交易日≥$holdMax交易日)$signalReasonSuffix';
              }
            } catch (_) {/* 日期解析失败则跳过到期判断 */}
          }

          // IV. 追踪止盈平仓（与回测引擎 trailingStop 逻辑对齐）
          if (sellReason == null && trailingDrop > 0.0) {
            final double avgCost = pos.buyPrice;
            if (avgCost > 0.0) {
              final double maxProfitSoFar =
                  ((pos.maxHoldNav - avgCost) / avgCost) * 100.0;
              if (maxProfitSoFar >= trailingActivate) {
                final double dropFromPeak =
                    ((price - pos.maxHoldNav) / pos.maxHoldNav) * 100.0;
                if (dropFromPeak <= -trailingDrop) {
                  sellReason =
                      '追踪止盈(高点回撤${dropFromPeak.toStringAsFixed(1)}%)$signalReasonSuffix';
                }
              }
            }
          }

          // V. 卖出信号平仓（基准锚定实际买入日，与回测一致）
          if (sellReason == null &&
              fund.isSellSignalAt(evalIndex, buyDateStr: pos.buyDateStr)) {
            sellReason = '卖出信号触发$signalReasonSuffix';
          }

          // 执行卖出（扣除滑点与手续费，与回测对齐）
          if (sellReason != null) {
            final double sellVolume = pos.volume;
            final double sellAmt = sellVolume * price;
            double netSellAmt = sellAmt * (1.0 - slippagePct / 100.0);
            if (fund.isExchangeTraded) {
              final double commRate =
                  (fund.optimalStrategy?['etf_commission_rate'] as num?)
                          ?.toDouble() ??
                      appConfig.etfCommissionRate;
              final double minComm =
                  (fund.optimalStrategy?['etf_min_commission'] as num?)
                          ?.toDouble() ??
                      appConfig.etfMinCommission;
              final double sellFee =
                  math.max(sellAmt * (commRate / 100.0), minComm);
              netSellAmt -= sellFee;
            } else if (holdDays < shortHoldDays && shortHoldPenalty > 0) {
              netSellAmt -= sellAmt * (shortHoldPenalty / 100.0);
            }

            if (netSellAmt.isFinite && netSellAmt > 0) {
              availableBalance += netSellAmt;
              positions.remove(code);

              transactions.insert(
                  0,
                  SimulatedTransaction(
                    id: 'TX_${DateTime.now().millisecondsSinceEpoch}_$code',
                    code: code,
                    name: name,
                    type: 'SELL',
                    price: price,
                    volume: sellVolume,
                    amount: netSellAmt,
                    dateTime: DateTime.now(),
                    dateTimeStr: tradeDateStr,
                    signalReason: sellReason,
                  ));
              changed = true;
            }
            continue; // 同日互斥：已卖出则跳过该基金的买入判断
          }
        } else {
          continue; // T+1 或已卖出，跳过买入判断
        }
      }

      // ========== B. 买入判断 ==========
      if (!fund.isBuySignalAt(evalIndex)) continue;

      // 检查该结算净值日期是否已经对该基金买入过
      final bool alreadyBoughtOnDate = transactions.any((tx) =>
          tx.code == code &&
          tx.type == 'BUY' &&
          tx.dateTimeStr == tradeDateStr);
      if (alreadyBoughtOnDate) continue;

      // 单日买入笔数限制
      if (dailyBuyCount >= maxDailyBuys) continue;

      final bool stillHeld = positions.containsKey(code);

      if (!stillHeld) {
        // --- 新建仓位 ---
        // 全局最大持仓数限制
        if (positions.length >= maxTotalPositions) continue;
        if (availableBalance < 100.0) continue;

        final double buyAmt = math.min(defaultBuyAmount, availableBalance);
        double fee = 0.0;
        if (fund.isExchangeTraded) {
          final double commRate =
              (fund.optimalStrategy?['etf_commission_rate'] as num?)
                      ?.toDouble() ??
                  appConfig.etfCommissionRate;
          final double minComm =
              (fund.optimalStrategy?['etf_min_commission'] as num?)
                      ?.toDouble() ??
                  appConfig.etfMinCommission;
          fee = math.max(buyAmt * (commRate / 100.0), minComm);
        } else {
          final double purchaseFeePct =
              (fund.optimalStrategy?['purchase_fee_pct'] as num?)?.toDouble() ??
                  defaultPurchaseFeePct;
          fee = buyAmt * purchaseFeePct / 100.0;
        }

        if (buyAmt + fee > availableBalance) continue;
        final double volume = buyAmt / price;
        if (!volume.isFinite) continue;

        availableBalance -= buyAmt + fee;
        positions[code] = SimulatedPosition(
          code: code,
          name: name,
          volume: volume,
          buyPrice: price,
          currentPrice: price,
          buyDateStr: tradeDateStr,
          gridCount: 0,
          firstBuyPrice: price,
          lastBuyPrice: price,
          maxHoldNav: price,
        );

        transactions.insert(
            0,
            SimulatedTransaction(
              id: 'TX_${DateTime.now().millisecondsSinceEpoch}_$code',
              code: code,
              name: name,
              type: 'BUY',
              price: price,
              volume: volume,
              amount: buyAmt,
              dateTime: DateTime.now(),
              dateTimeStr: tradeDateStr,
              signalReason:
                  '买入信号触发$signalReasonSuffix${fee > 0 ? (fund.isExchangeTraded ? '(含${fee.toStringAsFixed(2)}元佣金)' : '(含${fee.toStringAsFixed(2)}元申购费)') : ''}',
            ));
        dailyBuyCount++;
        changed = true;
      } else {
        // --- 网格加仓：已持有但价格继续下跌时追加买入摊低成本 ---
        final pos = positions[code]!;
        if (pos.gridCount >= maxGridCount) continue;
        if (availableBalance < 100.0) continue;

        // 网格步进检查：当前价格必须相对最近一次买入价下跌超过网格间距
        // （与回测引擎基于 lastBuyPrice 的步进判断对齐）
        final double buyDrop =
            (fund.optimalStrategy?['buy_drop'] as num?)?.toDouble() ?? 5.0;
        final double gridSpacingPct = (buyDrop * 0.3).clamp(1.0, 5.0);
        final double dropFromLast =
            ((price - pos.lastBuyPrice) / pos.lastBuyPrice) * 100.0;
        if (dropFromLast > -gridSpacingPct) continue; // 跌幅不够，不加仓

        final double buyAmt = math.min(defaultBuyAmount, availableBalance);
        double fee = 0.0;
        if (fund.isExchangeTraded) {
          final double commRate =
              (fund.optimalStrategy?['etf_commission_rate'] as num?)
                      ?.toDouble() ??
                  appConfig.etfCommissionRate;
          final double minComm =
              (fund.optimalStrategy?['etf_min_commission'] as num?)
                      ?.toDouble() ??
                  appConfig.etfMinCommission;
          fee = math.max(buyAmt * (commRate / 100.0), minComm);
        } else {
          final double purchaseFeePct =
              (fund.optimalStrategy?['purchase_fee_pct'] as num?)?.toDouble() ??
                  defaultPurchaseFeePct;
          fee = buyAmt * purchaseFeePct / 100.0;
        }

        if (buyAmt + fee > availableBalance) continue;
        final double volume = buyAmt / price;
        if (!volume.isFinite) continue;

        availableBalance -= buyAmt + fee;
        // 更新平均成本
        final double totalCost = pos.volume * pos.buyPrice + buyAmt;
        final double totalVolume = pos.volume + volume;
        pos.volume = totalVolume;
        pos.buyPrice = totalCost / totalVolume;
        pos.currentPrice = price;
        pos.lastBuyPrice = price; // 更新最近买入价（网格步进基准）
        pos.gridCount++;

        transactions.insert(
            0,
            SimulatedTransaction(
              id: 'TX_${DateTime.now().millisecondsSinceEpoch}_$code',
              code: code,
              name: name,
              type: 'BUY',
              price: price,
              volume: volume,
              amount: buyAmt,
              dateTime: DateTime.now(),
              dateTimeStr: tradeDateStr,
              signalReason:
                  '网格加仓(第${pos.gridCount}次,跌${dropFromLast.toStringAsFixed(1)}%)$signalReasonSuffix${fee > 0 ? (fund.isExchangeTraded ? '(含${fee.toStringAsFixed(2)}元佣金)' : '(含${fee.toStringAsFixed(2)}元申购费)') : ''}',
            ));
        dailyBuyCount++;
        changed = true;
      }
    }

    if (changed) {
      await saveSimData();
      notifyListeners();
    }
  }

  // 手动买入 API（微调与测试）
  Future<bool> manualBuy(
      String code, String name, double amount, double price) async {
    if (availableBalance < amount ||
        amount <= 0 ||
        price <= 0 ||
        !price.isFinite) {
      return false;
    }
    await loadSimData();

    // 手动交易不计费率（用户主动操作，与自动信号交易的口径区分）
    if (amount > availableBalance) return false;

    final volume = amount / price;
    if (!volume.isFinite) return false;
    availableBalance -= amount;

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    if (positions.containsKey(code)) {
      final pos = positions[code]!;
      final double totalCost = pos.volume * pos.buyPrice + amount;
      final double totalVolume = pos.volume + volume;
      pos.volume = totalVolume;
      pos.buyPrice = totalCost / totalVolume;
      pos.currentPrice = price;
      pos.lastBuyPrice = price;
      pos.gridCount++;
    } else {
      positions[code] = SimulatedPosition(
        code: code,
        name: name,
        volume: volume,
        buyPrice: price,
        currentPrice: price,
        buyDateStr: todayStr,
        gridCount: 0,
        firstBuyPrice: price,
        lastBuyPrice: price,
        maxHoldNav: price,
      );
    }

    transactions.insert(
        0,
        SimulatedTransaction(
          id: 'TX_M_${DateTime.now().millisecondsSinceEpoch}_$code',
          code: code,
          name: name,
          type: 'BUY',
          price: price,
          volume: volume,
          amount: amount,
          dateTime: DateTime.now(),
          dateTimeStr: todayStr,
          signalReason: '手动买入',
        ));

    await saveSimData();
    notifyListeners();
    return true;
  }

  // 手动卖出 API
  Future<bool> manualSell(String code, double price) async {
    if (!positions.containsKey(code) || price <= 0 || !price.isFinite) {
      return false;
    }
    await loadSimData();

    final pos = positions[code]!;
    final double sellVolume = pos.volume;
    final double sellAmt = sellVolume * price;
    if (!sellAmt.isFinite) return false;

    // 手动交易不计费率
    final double afterSlippage = sellAmt;
    availableBalance += afterSlippage;
    positions.remove(code);

    transactions.insert(
        0,
        SimulatedTransaction(
          id: 'TX_M_${DateTime.now().millisecondsSinceEpoch}_$code',
          code: code,
          name: pos.name,
          type: 'SELL',
          price: price,
          volume: sellVolume,
          amount: afterSlippage,
          dateTime: DateTime.now(),
          dateTimeStr: DateTime.now().toIso8601String().substring(0, 10),
          signalReason: '手动卖出',
        ));

    await saveSimData();
    notifyListeners();
    return true;
  }

  // 防御性校验：确保所有数值为有限值，防止 Infinity/NaN 污染
  void _sanitizeValues() {
    if (!initialBalance.isFinite || initialBalance < 0) {
      initialBalance = 1000000.0;
    }
    if (!availableBalance.isFinite || availableBalance < 0) {
      availableBalance = initialBalance;
    }
    if (!defaultBuyAmount.isFinite || defaultBuyAmount <= 0) {
      defaultBuyAmount = 10000.0;
    }

    // 修复：不再对高盈利余额做“5倍上限截断”——合法的持续盈利会被静默清零造成数据丢失。
    // 仅保留异常告警日志，由用户自行决定是否重置账户。
    final double maxReasonableBalance = initialBalance + (initialBalance * 5.0);
    if (availableBalance > maxReasonableBalance) {
      debugPrint(
          '[Simulation] 提示: 可用余额高于初始资金的 5 倍 (¥${availableBalance.toStringAsFixed(0)})，若为异常数据请手动重置账户');
    }

    positions.removeWhere((code, pos) {
      if (!pos.volume.isFinite || pos.volume < 0) return true;
      if (!pos.buyPrice.isFinite || pos.buyPrice <= 0) return true;
      if (!pos.currentPrice.isFinite || pos.currentPrice <= 0) return true;
      if (!pos.firstBuyPrice.isFinite || pos.firstBuyPrice <= 0) {
        pos.firstBuyPrice = pos.buyPrice;
      }
      if (!pos.lastBuyPrice.isFinite || pos.lastBuyPrice <= 0) {
        pos.lastBuyPrice = pos.buyPrice;
      }
      if (!pos.maxHoldNav.isFinite || pos.maxHoldNav <= 0) {
        pos.maxHoldNav = pos.currentPrice;
      }
      return false;
    });
  }
}
