extension NumberFormatting on num {
  /// 转换为带千分位逗号的字符串表示。
  /// [precision] 指定小数位数（例如保留2位）。如果为null，则保留原始小数位数。
  /// [showSign] 如果为true且数值大于0，则添加 `+` 号前缀。
  String toThousand({int? precision, bool showSign = false}) {
    // 防御：Infinity / NaN 直接返回占位符
    if (!isFinite) {
      if (isNaN) return 'NaN';
      if (this > 0) return 'Infinity';
      return '-Infinity';
    }

    String str;
    if (precision != null) {
      str = toStringAsFixed(precision);
    } else {
      str = toString();
    }
    
    // 如果是科学计数法，则保留原始字符串以防解析出错
    if (str.contains('e') || str.contains('E')) {
      return str;
    }
    
    final parts = str.split('.');
    String integerPart = parts[0];
    final fractionalPart = parts.length > 1 ? '.${parts[1]}' : '';
    
    bool isNegative = false;
    if (integerPart.startsWith('-')) {
      isNegative = true;
      integerPart = integerPart.substring(1);
    } else if (integerPart.startsWith('+')) {
      integerPart = integerPart.substring(1);
    }
    
    final buffer = StringBuffer();
    final len = integerPart.length;
    for (int i = 0; i < len; i++) {
      buffer.write(integerPart[i]);
      if ((len - i - 1) % 3 == 0 && i != len - 1) {
        buffer.write(',');
      }
    }
    
    final sign = isNegative ? '-' : (showSign && this > 0 ? '+' : '');
    return '$sign${buffer.toString()}$fractionalPart';
  }
}
