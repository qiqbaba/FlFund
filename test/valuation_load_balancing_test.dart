// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/data_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Valuation Load Balancing & Fallback Tests', () {
    final gateway = FundDataGateway();

    test('valuationSourceCount returns 1', () {
      expect(gateway.valuationSourceCount, equals(1));
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
    test('isNoLiveValuationFund correctly identifies money and wealth funds', () {
      expect(FundDataGateway.isNoLiveValuationFund('000009', name: '易方达天天理财货币A'), isTrue);
      expect(FundDataGateway.isNoLiveValuationFund('000739', name: '广发天天红货币A'), isTrue);
      expect(FundDataGateway.isNoLiveValuationFund('015645', name: '惠升中证同业存单AAA指数'), isTrue);
      expect(FundDataGateway.isNoLiveValuationFund('000001', name: '华夏成长混合'), isFalse);
      expect(FundDataGateway.isNoLiveValuationFund('023918', name: '华夏国证自由现金流ETF发起式联接C'), isFalse);
    });

    test('fetchValuation skips polling for money market funds', () async {
      final val = await gateway.fetchValuation('000009', name: '易方达天天理财货币A');
      expect(val, isNull);
    });
  });
}
