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
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory FundInfo.fromJson(String code, Map<String, dynamic> json) {
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
    };
  }
}
