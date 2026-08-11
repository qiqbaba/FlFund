// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/data_gateway.dart';
import 'dart:io';

void main() {
  HttpOverrides.global = null;

  group('FundDataGateway fetchValuationBatch Unit Tests', () {
    test('fetchValuationBatch returns valid valuation map for multiple codes', () async {
      final gateway = FundDataGateway();
      final codes = ['000001', '005827', '161725', '007713'];
      final results = await gateway.fetchValuationBatch(codes);

      print('=== Batch Valuation Test Results ===');
      print('Total funds returned: ${results.length}');
      results.forEach((code, val) {
        print('  [$code] ${val['name']}: gsz=${val['gsz']}, gszzl=${val['gszzl']}%, gztime=${val['gztime']}');
      });

      expect(results.length, greaterThan(0));
      expect(results.containsKey('000001'), isTrue);
      expect(results['000001']?['gsz'], isNotNull);
      expect(results['000001']?['source'], equals('SinaGzBatch'));
    });

    test('fetchValuationBatch correctly handles money market funds', () async {
      final gateway = FundDataGateway();
      final codes = ['000009', '000001'];
      final results = await gateway.fetchValuationBatch(codes);

      expect(results.containsKey('000009'), isFalse);
      expect(results.containsKey('000001'), isTrue);
    });
  });
}
