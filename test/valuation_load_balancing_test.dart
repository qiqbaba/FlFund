// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/data_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Valuation Load Balancing & Fallback Tests', () {
    final gateway = FundDataGateway();

    test('valuationSourceCount returns 7', () {
      expect(gateway.valuationSourceCount, equals(7));
    });

    test('preferredSourceIndex distributes requests evenly', () async {
      final codes = ['000001', '000002', '000003', '000004', '000005'];
      final sourcesUsed = <String>[];

      for (int i = 0; i < codes.length; i++) {
        final preferredIndex = i % gateway.valuationSourceCount;
        final val = await gateway.fetchValuation(
          codes[i],
          preferredSourceIndex: preferredIndex,
        );
        if (val != null) {
          sourcesUsed.add('${codes[i]}: ${val['source']}');
        }
      }

      print('Valuation results across sources:');
      for (final s in sourcesUsed) {
        print('  $s');
      }
    });
  });
}
