import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/fund_provider.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('FundProvider Cycle Board Percentile Tests', () {
    test('Check cycleFundCodes definitions', () {
      expect(FundProvider.cycleFundCodes.length, 13);
      expect(FundProvider.cycleFundCodes.contains('012725'), true);
      expect(FundProvider.cycleFundCodes.contains('008282'), true);
      expect(FundProvider.cycleFundCodes.contains('013275'), true);
      expect(FundProvider.cycleFundCodes.contains('016708'), true);
      expect(FundProvider.cycleFundCodes.contains('161725'), true);
      expect(FundProvider.cycleFundCodes.contains('005224'), true);
      expect(FundProvider.cycleFundCodes.contains('161027'), true);
      expect(FundProvider.cycleFundCodes.contains('014605'), true);
    });

    test('Verify cycleFunds initialization', () {
      final provider = FundProvider();
      expect(provider.cycleFunds, isNotNull);
    });
  });
}
