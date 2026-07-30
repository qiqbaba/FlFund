import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'fund_provider.dart';
import 'supabase_manager.dart';

class SimulatedPosition {
  final String code;
  final String name;
  double volume; // 持有份额
  double buyPrice; // 平均买入成本价
  double currentPrice; // 最新估值/净值

  SimulatedPosition({
    required this.code,
    required this.name,
    required this.volume,
    required this.buyPrice,
    required this.currentPrice,
  });

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
  };

  factory SimulatedPosition.fromJson(Map<String, dynamic> json) => SimulatedPosition(
    code: json['code'] ?? '',
    name: json['name'] ?? '',
    volume: (json['volume'] as num).toDouble(),
    buyPrice: (json['buyPrice'] as num).toDouble(),
    currentPrice: (json['currentPrice'] as num).toDouble(),
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
  final DateTime dateTime;     // 操作系统时间
  final String dateTimeStr;    // 成交的核算净值日期，比如 "2026-07-03"
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

  factory SimulatedTransaction.fromJson(Map<String, dynamic> json) => SimulatedTransaction(
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
        
        initialBalance = (jsonMap['initialBalance'] as num?)?.toDouble() ?? 1000000.0;
        availableBalance = (jsonMap['availableBalance'] as num?)?.toDouble() ?? 1000000.0;
        defaultBuyAmount = (jsonMap['defaultBuyAmount'] as num?)?.toDouble() ?? 10000.0;
        isAutoTradeEnabled = jsonMap['isAutoTradeEnabled'] ?? true;
        
        final posMap = jsonMap['positions'] as Map<String, dynamic>? ?? {};
        positions = posMap.map((key, val) => MapEntry(key, SimulatedPosition.fromJson(val)));
        
        final txList = jsonMap['transactions'] as List<dynamic>? ?? [];
        transactions = txList.map((val) => SimulatedTransaction.fromJson(val)).toList();
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
    const endMinutes = 15 * 60;        // 15:00
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

    // 1. 静默同步当前持仓中基金的最新净值/估值（在不交易时，市值也需根据最新的收盘或实时估值随动更新）
    for (final pos in positions.values) {
      final matchingFund = funds.firstWhere((f) => f.code == pos.code, orElse: () => FundUIModel(code: '', name: '', sector: ''));
      if (matchingFund.code.isNotEmpty) {
        double? currentPrice;
        if (tailTrade && matchingFund.isTodayValuation) {
          currentPrice = double.tryParse(matchingFund.gsz);
        }
        currentPrice ??= matchingFund.navs.isNotEmpty ? matchingFund.navs.first : null;

        if (currentPrice != null && currentPrice > 0.0 && currentPrice.isFinite) {
          if (pos.currentPrice != currentPrice) {
            pos.currentPrice = currentPrice;
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
        // 交易日下午两点四十之后：以当时的估值进行买入、卖出计算
        evalIndex = 0;
        price = double.tryParse(fund.gsz) ?? (fund.navs.isNotEmpty ? fund.navs.first : 0.0);
        tradeDateStr = todayStr;
        signalReasonSuffix = ' (尾盘估值信号)';
      } else {
        // 其它时间段（早盘、午盘、停盘后或非交易日）：以上一个交易日的收盘净值进行计算
        evalIndex = fund.isTodayValuation ? 1 : 0;
        price = fund.navs.isNotEmpty ? fund.navs.first : 0.0;
        tradeDateStr = fund.dates.isNotEmpty ? fund.dates.first : todayStr;
        signalReasonSuffix = ' (收盘净值信号)';
      }

      if (price <= 0.0 || !price.isFinite) continue;

      // A. 自动买入信号触发
      if (fund.isBuySignalAt(evalIndex)) {
        // 检查该结算净值日期 (tradeDateStr) 是否已经对该基金买入过
        final bool alreadyBoughtOnDate = transactions.any((tx) => 
          tx.code == code && 
          tx.type == 'BUY' && 
          tx.dateTimeStr == tradeDateStr
        );

        final bool isHeld = positions.containsKey(code);

        if (!isHeld && !alreadyBoughtOnDate && availableBalance >= 100.0) {
          final double buyAmt = math.min(defaultBuyAmount, availableBalance);
          final double volume = buyAmt / price;
          if (!volume.isFinite) continue;

          availableBalance -= buyAmt;
          positions[code] = SimulatedPosition(
            code: code,
            name: name,
            volume: volume,
            buyPrice: price,
            currentPrice: price,
          );

          transactions.insert(0, SimulatedTransaction(
            id: 'TX_${DateTime.now().millisecondsSinceEpoch}_$code',
            code: code,
            name: name,
            type: 'BUY',
            price: price,
            volume: volume,
            amount: buyAmt,
            dateTime: DateTime.now(),
            dateTimeStr: tradeDateStr,
            signalReason: '买入信号触发$signalReasonSuffix',
          ));
          changed = true;
        }
      }

      // B. 自动卖出信号触发
      if (fund.isSellSignalAt(evalIndex)) {
        final bool isHeld = positions.containsKey(code);
        if (isHeld) {
          // T+1 限制：同一净值日刚买入的基金不能在同一天卖出
          final lastBuyTx = transactions.firstWhere(
            (tx) => tx.code == code && tx.type == 'BUY',
            orElse: () => SimulatedTransaction(
              id: '', code: '', name: '', type: '', price: 0, volume: 0, amount: 0, dateTime: DateTime(2000), dateTimeStr: ''
            )
          );
          final bool isBoughtSameDate = lastBuyTx.id.isNotEmpty && lastBuyTx.dateTimeStr == tradeDateStr;

          // 防止同结算日内重复卖出
          final bool alreadySoldOnDate = transactions.any((tx) => 
            tx.code == code && 
            tx.type == 'SELL' && 
            tx.dateTimeStr == tradeDateStr
          );

          if (!isBoughtSameDate && !alreadySoldOnDate) {
            final pos = positions[code]!;
            final double sellVolume = pos.volume;
            final double sellAmt = sellVolume * price;
            if (!sellAmt.isFinite) continue;

            availableBalance += sellAmt;
            positions.remove(code);

            transactions.insert(0, SimulatedTransaction(
              id: 'TX_${DateTime.now().millisecondsSinceEpoch}_$code',
              code: code,
              name: name,
              type: 'SELL',
              price: price,
              volume: sellVolume,
              amount: sellAmt,
              dateTime: DateTime.now(),
              dateTimeStr: tradeDateStr,
              signalReason: '卖出信号触发$signalReasonSuffix',
            ));
            changed = true;
          }
        }
      }
    }

    if (changed) {
      await saveSimData();
      notifyListeners();
    }
  }

  // 手动买入 API（微调与测试）
  Future<bool> manualBuy(String code, String name, double amount, double price) async {
    if (availableBalance < amount || amount <= 0 || price <= 0 || !price.isFinite) return false;
    await loadSimData();

    final volume = amount / price;
    if (!volume.isFinite) return false;
    availableBalance -= amount;

    if (positions.containsKey(code)) {
      final pos = positions[code]!;
      final double totalCost = pos.volume * pos.buyPrice + amount;
      final double totalVolume = pos.volume + volume;
      pos.volume = totalVolume;
      pos.buyPrice = totalCost / totalVolume;
      pos.currentPrice = price;
    } else {
      positions[code] = SimulatedPosition(
        code: code,
        name: name,
        volume: volume,
        buyPrice: price,
        currentPrice: price,
      );
    }

    transactions.insert(0, SimulatedTransaction(
      id: 'TX_M_${DateTime.now().millisecondsSinceEpoch}_$code',
      code: code,
      name: name,
      type: 'BUY',
      price: price,
      volume: volume,
      amount: amount,
      dateTime: DateTime.now(),
      dateTimeStr: DateTime.now().toIso8601String().substring(0, 10),
      signalReason: '手动买入',
    ));

    await saveSimData();
    notifyListeners();
    return true;
  }

  // 手动卖出 API
  Future<bool> manualSell(String code, double price) async {
    if (!positions.containsKey(code) || price <= 0 || !price.isFinite) return false;
    await loadSimData();

    final pos = positions[code]!;
    final double sellVolume = pos.volume;
    final double sellAmt = sellVolume * price;
    if (!sellAmt.isFinite) return false;

    availableBalance += sellAmt;
    positions.remove(code);

    transactions.insert(0, SimulatedTransaction(
      id: 'TX_M_${DateTime.now().millisecondsSinceEpoch}_$code',
      code: code,
      name: pos.name,
      type: 'SELL',
      price: price,
      volume: sellVolume,
      amount: sellAmt,
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
    if (!initialBalance.isFinite || initialBalance < 0) initialBalance = 1000000.0;
    if (!availableBalance.isFinite || availableBalance < 0) availableBalance = initialBalance;
    if (!defaultBuyAmount.isFinite || defaultBuyAmount <= 0) defaultBuyAmount = 10000.0;

    // 可用余额合理性上限：最多允许盈利 500%
    final double maxReasonableBalance = initialBalance + (initialBalance * 5.0);
    if (availableBalance > maxReasonableBalance) {
      debugPrint('[Simulation] 警告: 可用余额异常偏高 (¥${availableBalance.toStringAsFixed(0)})，已截断至初始资金');
      availableBalance = initialBalance;
    }

    positions.removeWhere((code, pos) {
      if (!pos.volume.isFinite || pos.volume < 0) return true;
      if (!pos.buyPrice.isFinite || pos.buyPrice <= 0) return true;
      if (!pos.currentPrice.isFinite || pos.currentPrice <= 0) return true;
      return false;
    });
  }
}
