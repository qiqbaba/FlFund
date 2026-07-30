import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/utils/number_formatter.dart';

void main() {
  group('NumberFormatting extension tests', () {
    test('Should format integer with thousand separator', () {
      expect(1000.toThousand(), '1,000');
      expect(12345.toThousand(), '12,345');
      expect(1000000.toThousand(), '1,000,000');
    });

    test('Should format double with thousand separator and precision', () {
      expect(1234.56.toThousand(precision: 2), '1,234.56');
      expect(12345.6.toThousand(precision: 2), '12,345.60');
      expect(1234567.891.toThousand(precision: 2), '1,234,567.89');
    });

    test('Should keep values under 1000 as is', () {
      expect(999.toThousand(), '999');
      expect(123.45.toThousand(precision: 2), '123.45');
      expect(0.toThousand(), '0');
    });

    test('Should handle negative numbers correctly', () {
      expect((-1000).toThousand(), '-1,000');
      expect((-12345.67).toThousand(precision: 2), '-12,345.67');
      expect((-99.9).toThousand(precision: 1), '-99.9');
    });

    test('Should support showing positive sign (+)', () {
      expect(1000.toThousand(showSign: true), '+1,000');
      expect(123.45.toThousand(precision: 2, showSign: true), '+123.45');
      expect((-1234.56).toThousand(precision: 2, showSign: true), '-1,234.56');
      expect(0.toThousand(showSign: true), '0');
    });
  });
}
