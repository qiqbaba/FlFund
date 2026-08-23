enum FundType {
  otc, // 场外开放式基金
  etf, // 场内 ETF 交易型开放式指数基金
  lof, // 场内 LOF 上市型开放式基金
  reit, // 场内 公募 REITs
}

extension FundTypeExtension on FundType {
  String get label {
    switch (this) {
      case FundType.etf:
        return 'ETF';
      case FundType.lof:
        return 'LOF';
      case FundType.reit:
        return 'REITs';
      case FundType.otc:
        return '场外';
    }
  }

  bool get isExchangeTraded => this != FundType.otc;

  String get codeName => name;
}

class FundInfo {
  final String code;
  String name;
  String sector;
  bool isHeld;
  bool isSpecial;
  bool isPinned;
  double amount;
  double yieldRate;
  DateTime updatedAt;
  bool isDeleted;

  // 场内基金特有字段
  FundType fundType;
  double shares; // 持股数量（股/份）
  double costPrice; // 持仓成本价（元）

  FundInfo({
    required this.code,
    required this.name,
    required this.sector,
    this.isHeld = false,
    this.isSpecial = false,
    this.isPinned = false,
    this.amount = 0.0,
    this.yieldRate = 0.0,
    DateTime? updatedAt,
    this.isDeleted = false,
    FundType? fundType,
    this.shares = 0.0,
    this.costPrice = 0.0,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        fundType = fundType ?? autoDetectFundType(code);

  static FundType autoDetectFundType(String code) {
    final cleanCode = code.replaceAll(RegExp(r'\D'), '');
    if (cleanCode.length != 6) return FundType.otc;

    // 上海/深圳常见 ETF
    if (cleanCode.startsWith('51') ||
        cleanCode.startsWith('56') ||
        cleanCode.startsWith('58') ||
        cleanCode.startsWith('159')) {
      return FundType.etf;
    }
    // LOF 基金
    if (cleanCode.startsWith('501') ||
        cleanCode.startsWith('502') ||
        cleanCode.startsWith('506') ||
        cleanCode.startsWith('16')) {
      return FundType.lof;
    }
    // REITs 基金
    if (cleanCode.startsWith('508') || cleanCode.startsWith('180')) {
      return FundType.reit;
    }
    return FundType.otc;
  }

  static String getMarketPrefix(String code) {
    final cleanCode = code.replaceAll(RegExp(r'\D'), '');
    if (cleanCode.startsWith('5') ||
        cleanCode.startsWith('6') ||
        cleanCode.startsWith('9')) {
      return 'sh';
    }
    if (cleanCode.startsWith('1') ||
        cleanCode.startsWith('0') ||
        cleanCode.startsWith('3')) {
      return 'sz';
    }
    if (cleanCode.startsWith('4') ||
        cleanCode.startsWith('8') ||
        cleanCode.startsWith('92')) {
      return 'bj';
    }
    return 'sh';
  }

  factory FundInfo.fromJson(String code, Map<String, dynamic> json) {
    FundType type;
    if (json['fund_type'] != null) {
      final tStr = json['fund_type'].toString().toLowerCase();
      if (tStr == 'etf') {
        type = FundType.etf;
      } else if (tStr == 'lof') {
        type = FundType.lof;
      } else if (tStr == 'reit' || tStr == 'reits') {
        type = FundType.reit;
      } else if (tStr == 'otc') {
        type = FundType.otc;
      } else {
        type = autoDetectFundType(code);
      }
    } else {
      // 兼容旧版 my_funds.json：若已存在持仓且仅有 amount/yield_rate 而无 shares/cost_price，则属于场外基金
      final rawAmount = json['amount']?.toString() ?? '';
      final rawShares = json['shares']?.toString() ?? '';
      final hasAmountOnly = rawAmount.isNotEmpty &&
          rawAmount != '0' &&
          rawAmount != '0.0' &&
          (rawShares.isEmpty || rawShares == '0' || rawShares == '0.0');
      if (hasAmountOnly) {
        type = FundType.otc;
      } else {
        type = autoDetectFundType(code);
      }
    }

    return FundInfo(
      code: code,
      name: json['name'] ?? '',
      sector: json['sector'] ?? '',
      isHeld: json['is_held'] ?? false,
      isSpecial: json['is_special'] ?? false,
      isPinned: json['is_pinned'] ?? false,
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0.0,
      yieldRate: double.tryParse(json['yield_rate']?.toString() ?? '') ?? 0.0,
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      isDeleted: json['is_deleted'] ?? false,
      fundType: type,
      shares: double.tryParse(json['shares']?.toString() ?? '') ?? 0.0,
      costPrice: double.tryParse(json['cost_price']?.toString() ?? '') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sector': sector,
      'is_held': isHeld,
      'is_special': isSpecial,
      'is_pinned': isPinned,
      'amount': amount == 0.0 ? "" : amount.toString(),
      'yield_rate': yieldRate == 0.0 ? "" : yieldRate.toString(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
      'fund_type': fundType.codeName,
      'shares': shares == 0.0 ? "" : shares.toString(),
      'cost_price': costPrice == 0.0 ? "" : costPrice.toString(),
    };
  }
}

