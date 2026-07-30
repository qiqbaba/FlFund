import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/fund_provider.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('FundUIModel isTodayValuation Tests', () {
    test('Should return true if gztime contains today date', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      model.gztime = '$todayStr 15:00 [EastMoneyGz]';
      expect(model.isTodayValuation, true);
    });

    test('Should return false if gztime contains another date', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      model.gztime = '2020-01-01 15:00 [EastMoneyGz]';
      expect(model.isTodayValuation, false);
    });

    test('Should return false if gztime is default/empty', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      expect(model.isTodayValuation, false);
    });
  });
}
